#!/usr/bin/env python3
"""Da de alta en lote las clases de PaseLista a partir de los CSV de clases de cada profesor.

Cada CSV es de un solo profe, sin encabezado, con tres columnas: MATERIA, SALÓN, GRUPO.
El profe sale del nombre del archivo ("TOXQUI ALARCÓN HUGO EDUARDO - Clases.csv") y su correo se
busca en el mismo CSV de correos que usa invitar_desde_csv.py (columnas NOMBRE y CORREO).

Uso:
    # 1. Revisión local: solo lee los CSV, no toca Firestore
    python3 clases_desde_csv.py --correos correos-profes.csv clases/*.csv

    # 2. Simulación contra Firestore: busca profes, grupos y clases existentes, no escribe nada
    python3 clases_desde_csv.py --correos correos-profes.csv clases/*.csv \\
        --credenciales ~/llaves/paselista-sa.json

    # 3. Escribir
    python3 clases_desde_csv.py --correos correos-profes.csv clases/*.csv \\
        --credenciales ~/llaves/paselista-sa.json --aplicar

Qué hace, igual que "Dar de alta clase" en la app:
- Una clase = profe + grupo + materia. Si la misma materia viene con dos salones en el mismo grupo
  (el aula y el laboratorio, por ejemplo), queda una sola clase con el primer salón como "el de
  siempre"; el profe cambia el salón del día al pasar lista.
- Crea `clases/{id generado}` y agrega al profe a `grupos/{id}.profesores` en el mismo lote.
- No duplica: si el profe ya tiene esa materia en ese grupo, la salta. Se puede correr las veces
  que sea necesario, por ejemplo después de que entren los profes que faltaban.
- Se salta (y lo reporta) al profe que todavía no entra a la app y al grupo que no existe.
- La materia se guarda con 40 caracteres como máximo (lo que permite la app). Si es más larga se
  usa lo que va antes del primer ". " ("LENGUA Y COMUNICACIÓN III. DESCRIBIR..." → "LENGUA Y
  COMUNICACIÓN III"); si aún así no cabe, va en el archivo de --materias.
"""

import argparse
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

PROYECTO = "paselista-9326a"
MAX_ETIQUETA = 40  # lib/models/clase.dart: maxEtiqueta
LOTE = 450  # un WriteBatch acepta hasta 500 escrituras

# ── Igual que lib/models/grupo.dart ─────────────────────────────────────────────
_SIN_ACENTO = str.maketrans("áàäâãéèëêíìïîóòöôõúùüûñç", "aaaaaeeeeiiiiooooouuuunc")


def sin_acentos(texto):
    return texto.lower().translate(_SIN_ACENTO)


def limpiar(texto):
    return " ".join((texto or "").split())


def id_grupo(nombre):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", sin_acentos(nombre.strip())))


def llave_materia(materia):
    return sin_acentos(limpiar(materia))


# ── Lectura de archivos ─────────────────────────────────────────────────────────
def leer_texto(ruta):
    datos = Path(ruta).read_bytes()
    if datos.startswith(b"\xef\xbb\xbf"):
        datos = datos[3:]
    try:
        return datos.decode("utf-8")
    except UnicodeDecodeError:
        return datos.decode("latin-1")  # Excel en Windows


def filas_csv(ruta):
    return list(csv.reader(leer_texto(ruta).splitlines()))


def leer_correos(ruta):
    """NOMBRE y CORREO del CSV de invitaciones → lista de (nombre, correo)."""
    filas = filas_csv(ruta)
    if not filas:
        sys.exit(f"{ruta}: está vacío.")
    encabezado = [limpiar(c).upper() for c in filas[0]]
    try:
        i_nombre, i_correo = encabezado.index("NOMBRE"), encabezado.index("CORREO")
    except ValueError:
        sys.exit(f"{ruta}: necesita las columnas NOMBRE y CORREO en la primera fila.")
    personas = []
    for fila in filas[1:]:
        if len(fila) <= max(i_nombre, i_correo):
            continue
        nombre, correo = limpiar(fila[i_nombre]), fila[i_correo].strip().lower()
        if nombre and correo:
            personas.append((nombre, correo))
    return personas


def leer_materias(ruta):
    """Archivo de abreviaturas: MATERIA COMPLETA, MATERIA CORTA (encabezado opcional)."""
    cortas = {}
    if not ruta:
        return cortas
    for n, fila in enumerate(filas_csv(ruta), start=1):
        if len(fila) < 2 or not limpiar(fila[0]):
            continue
        larga, corta = limpiar(fila[0]), limpiar(fila[1])
        if n == 1 and larga.upper() in ("MATERIA", "MATERIA COMPLETA"):
            continue
        if len(corta) > MAX_ETIQUETA:
            sys.exit(f"{ruta}, línea {n}: \"{corta}\" tiene más de {MAX_ETIQUETA} caracteres.")
        cortas[llave_materia(larga)] = corta
    return cortas


def materia_corta(materia, cortas):
    """La materia como se guarda, o None si no cabe y no está en el archivo de abreviaturas."""
    if llave_materia(materia) in cortas:
        return cortas[llave_materia(materia)]
    if len(materia) <= MAX_ETIQUETA:
        return materia
    antes_del_punto = materia.split(". ", 1)[0].strip()
    if len(antes_del_punto) <= MAX_ETIQUETA:
        return cortas.get(llave_materia(antes_del_punto), antes_del_punto)
    return cortas.get(llave_materia(antes_del_punto))


# ── Profe a partir del nombre del archivo ───────────────────────────────────────
def nombre_del_archivo(ruta):
    nombre = Path(ruta).stem
    nombre = re.sub(r"^[0-9a-f]{8}-", "", nombre)  # prefijo que agregan algunas descargas
    nombre = re.sub(r"[\s_]*-[\s_]*clases$", "", nombre, flags=re.IGNORECASE)
    return nombre


def _partes(texto):
    return [p for p in re.split(r"[^a-z0-9]+", sin_acentos(texto)) if p]


def _coincide(palabra, pedazo):
    # Algunas descargas cambian Ñ, Á, Ó... por "_": "ALARC_N" llega como "alarc" + "n".
    return palabra == pedazo or (
        len(pedazo) >= 3 and (palabra.startswith(pedazo) or palabra.endswith(pedazo))
    )


def mismo_nombre(del_archivo, de_la_lista):
    """True si todas las palabras de uno de los dos nombres están en el otro, en cualquier orden.
    Así "TOXQUI ALARCÓN HUGO EDUARDO" = "HUGO EDUARDO TOXQUI ALARCÓN" = "HUGO TOXQUI ALARCÓN"."""
    pedazos = [p for p in _partes(del_archivo) if len(p) >= 3]
    palabras = [p for p in _partes(de_la_lista) if len(p) >= 3]
    if len(pedazos) < 2 or len(palabras) < 2:
        return False
    archivo_en_lista = all(any(_coincide(w, p) for w in palabras) for p in pedazos)
    lista_en_archivo = all(any(_coincide(w, p) for p in pedazos) for w in palabras)
    return archivo_en_lista or lista_en_archivo


def buscar_correo(ruta, personas, forzados):
    """(correo, nombre) del profe del archivo, o (None, motivo)."""
    archivo = Path(ruta).name
    if archivo in forzados:
        return forzados[archivo], "(asignado con --profesor)"
    buscado = nombre_del_archivo(ruta)
    candidatos = {c: n for n, c in personas if mismo_nombre(buscado, n)}
    if len(candidatos) == 1:
        correo, nombre = next(iter(candidatos.items()))
        return correo, nombre
    if not candidatos:
        return None, f"\"{buscado}\" no está en el CSV de correos"
    return None, f"\"{buscado}\" coincide con varios: {', '.join(sorted(candidatos.values()))}"


# ── Clases de un archivo ────────────────────────────────────────────────────────
def leer_clases(ruta, cortas):
    """Las clases del archivo ya juntas por (grupo, materia), y los errores por línea."""
    clases = {}  # (grupoId, llave materia corta) -> dict
    errores, faltan_cortas = [], set()
    for n, fila in enumerate(filas_csv(ruta), start=1):
        if not any(c.strip() for c in fila):
            continue
        if len(fila) < 3:
            errores.append(f"línea {n}: se esperaban 3 columnas (materia, salón, grupo)")
            continue
        materia, salon, grupo = (limpiar(c) for c in fila[:3])
        if n == 1 and materia.upper() in ("MATERIA", "ASIGNATURA"):
            continue  # encabezado
        if not materia or not salon or not id_grupo(grupo):
            errores.append(f"línea {n}: falta la materia, el salón o el grupo")
            continue
        corta = materia_corta(materia, cortas)
        if corta is None:
            faltan_cortas.add(materia)
            continue
        if len(salon) > MAX_ETIQUETA:
            errores.append(f"línea {n}: el salón \"{salon}\" tiene más de {MAX_ETIQUETA} caracteres")
            continue
        llave = (id_grupo(grupo), llave_materia(corta))
        if llave not in clases:
            clases[llave] = {
                "grupo": grupo,
                "materia": corta,
                "completa": materia,
                "salon": salon,
                "otros_salones": [],
            }
            continue
        c = clases[llave]
        if llave_materia(c["completa"]) != llave_materia(materia):
            errores.append(
                f"línea {n}: \"{materia}\" y \"{c['completa']}\" quedan como la misma materia "
                f"\"{corta}\" en {grupo}; dales abreviaturas distintas en --materias"
            )
        elif salon not in [c["salon"], *c["otros_salones"]]:
            c["otros_salones"].append(salon)
    return list(clases.values()), errores, faltan_cortas


# ── Firestore ───────────────────────────────────────────────────────────────────
def conectar(credenciales):
    import firebase_admin
    from firebase_admin import credentials, firestore

    cred = credentials.Certificate(credenciales) if credenciales else None
    firebase_admin.initialize_app(cred, {"projectId": PROYECTO})
    return firestore.client(), firestore


def resolver_en_firestore(db, por_profe):
    """Agrega uid, grupoId real y si la clase ya existe. Devuelve (nuevas, avisos)."""
    from google.cloud.firestore_v1.base_query import FieldFilter

    # Grupos por nombre, como la app: un grupo renombrado conserva el ID de su nombre original.
    grupos = {}
    for d in db.collection("grupos").stream():
        grupos.setdefault(d.id, d.id)
        grupos[id_grupo(str((d.to_dict() or {}).get("nombre", "")))] = d.id

    nuevas, avisos = [], defaultdict(list)
    existentes_por_grupo = {}
    for correo, (nombre, clases) in por_profe.items():
        usuarios = list(
            db.collection("usuarios").where(filter=FieldFilter("email", "==", correo)).limit(1).stream()
        )
        if not usuarios:
            invitado = db.document(f"invitaciones/{correo}").get().exists
            motivo = "invitado, pero todavía no entra a la app" if invitado else "no está invitado"
            avisos["Profes que faltan"].append(f"{nombre} <{correo}>: {motivo} ({len(clases)} clases)")
            continue
        uid, datos = usuarios[0].id, usuarios[0].to_dict() or {}
        if datos.get("rol") != "profesor":
            avisos["Profes que faltan"].append(
                f"{nombre} <{correo}>: tiene rol '{datos.get('rol')}', no 'profesor' ({len(clases)} clases)"
            )
            continue
        for c in clases:
            gid = grupos.get(id_grupo(c["grupo"]))
            if gid is None:
                avisos["Grupos que no existen (importa su lista primero)"].append(
                    f"{c['grupo']}: {nombre} · {c['materia']}"
                )
                continue
            if gid not in existentes_por_grupo:
                existentes_por_grupo[gid] = [
                    d.to_dict() or {}
                    for d in db.collection("clases").where(filter=FieldFilter("grupoId", "==", gid)).stream()
                ]
            ya = any(
                e.get("profesorUid") == uid and llave_materia(str(e.get("materia", ""))) == llave_materia(c["materia"])
                for e in existentes_por_grupo[gid]
            )
            if ya:
                avisos["Ya existían (sin cambios)"].append(f"{c['grupo']}: {nombre} · {c['materia']}")
                continue
            nuevas.append({**c, "uid": uid, "grupoId": gid, "profe": nombre})
    return nuevas, avisos


def escribir(db, firestore, nuevas):
    batch, ops, hechas = db.batch(), 0, 0
    for c in nuevas:
        if ops + 2 > LOTE:
            batch.commit()
            batch, ops = db.batch(), 0
        batch.set(
            db.collection("clases").document(),
            {"profesorUid": c["uid"], "grupoId": c["grupoId"], "materia": c["materia"], "salon": c["salon"]},
        )
        batch.update(db.document(f"grupos/{c['grupoId']}"), {"profesores": firestore.ArrayUnion([c["uid"]])})
        ops += 2
        hechas += 1
    if ops:
        batch.commit()
    return hechas


# ── Principal ───────────────────────────────────────────────────────────────────
def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("clases", nargs="+", help="CSV de clases, uno por profe")
    p.add_argument("--correos", required=True, help="CSV con NOMBRE y CORREO (el de las invitaciones)")
    p.add_argument("--materias", help="CSV de abreviaturas: MATERIA COMPLETA, MATERIA CORTA")
    p.add_argument(
        "--profesor",
        action="append",
        default=[],
        metavar="ARCHIVO=CORREO",
        help="asigna el correo a mano cuando el nombre del archivo no se encuentra (se puede repetir)",
    )
    p.add_argument("--credenciales", help="JSON de la cuenta de servicio; con esto revisa Firestore")
    p.add_argument("--aplicar", action="store_true", help="escribir en Firestore (sin esto solo simula)")
    args = p.parse_args()

    forzados = {}
    for f in args.profesor:
        archivo, _, correo = f.partition("=")
        if not correo:
            sys.exit(f"--profesor {f}: usa ARCHIVO=CORREO")
        forzados[Path(archivo).name] = correo.strip().lower()

    personas = leer_correos(args.correos)
    cortas = leer_materias(args.materias)

    por_profe, problemas, faltan_cortas = {}, [], set()
    for ruta in args.clases:
        correo, nombre = buscar_correo(ruta, personas, forzados)
        if correo is None:
            problemas.append(f"{Path(ruta).name}: {nombre}. Usa --profesor \"{Path(ruta).name}=correo\"")
            continue
        clases, errores, faltan = leer_clases(ruta, cortas)
        problemas += [f"{Path(ruta).name}, {e}" for e in errores]
        faltan_cortas |= faltan
        if correo in por_profe:
            problemas.append(f"{Path(ruta).name}: {correo} ya salió en otro archivo; se juntan")
            por_profe[correo][1].extend(clases)
        else:
            por_profe[correo] = (nombre, clases)

    total = 0
    for correo, (nombre, clases) in por_profe.items():
        print(f"\n{nombre} <{correo}>")
        for c in sorted(clases, key=lambda c: (id_grupo(c["grupo"]), c["materia"])):
            extra = f"  (también en {', '.join(c['otros_salones'])})" if c["otros_salones"] else ""
            print(f"  {c['grupo']:<8} {c['materia']:<{MAX_ETIQUETA}}  Salón {c['salon']}{extra}")
        total += len(clases)
    print(f"\nClases leídas: {total} de {len(por_profe)} profes.")

    if faltan_cortas:
        print(f"\nMaterias de más de {MAX_ETIQUETA} caracteres sin abreviatura. Agrégalas a --materias")
        print("(las clases con estas materias no se dan de alta):")
        for m in sorted(faltan_cortas):
            print(f'  "{m}",')
    if problemas:
        print("\nProblemas:")
        for x in problemas:
            print(f"  {x}")

    if not args.credenciales and not args.aplicar:
        print("\nRevisión local. Agrega --credenciales para revisar profes y grupos en Firestore.")
        return 1 if problemas or faltan_cortas else 0

    db, firestore = conectar(args.credenciales)
    nuevas, avisos = resolver_en_firestore(db, por_profe)
    for titulo, lineas in avisos.items():
        print(f"\n{titulo}: {len(lineas)}")
        for x in sorted(lineas):
            print(f"  {x}")
    print(f"\nClases por dar de alta: {len(nuevas)}")

    if not args.aplicar:
        print("Simulación. Agrega --aplicar para escribir en Firestore.")
        return 0
    hechas = escribir(db, firestore, nuevas)
    print(f"Dadas de alta: {hechas}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
