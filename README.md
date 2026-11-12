# app-lista-asistencia

App de lista de asistencia por clase para la escuela. Proyecto de servicio social.
*(El nombre definitivo de la app todavía no está decidido).*

- **Profesores:** pasan lista en cada clase desde Android o desde el navegador (iPhone y computadoras). Funciona sin internet y sincroniza después.
- **Encargados de orden:** ven los ausentes de cada grupo y copian un mensaje listo para el grupo de padres.
- **Administrativos:** suben las listas en CSV, dan de alta clases e invitan usuarios.

**Stack:** Flutter (Android + web) · Firebase Authentication (Google) · Cloud Firestore · Firebase Hosting.
**Entrega:** antes del 10 de diciembre de 2026.

> ⚠️ **Regla del repo:** nunca se suben datos reales de alumnos. Para pruebas se usan solo los
> archivos inventados de [`test/fixtures/`](test/fixtures/csv/LEEME.md). El `.gitignore` bloquea
> cualquier otro `.csv` o `.xlsx`.

## Preparar tu computadora

1. Instala el [Flutter SDK](https://docs.flutter.dev/get-started/install) (canal `stable`) y VS Code
   con la extensión de Flutter (o Android Studio).
2. Revisa que todo esté bien. Debe salir sin errores al menos en *Android toolchain* y *Chrome*:
   ```bash
   flutter doctor
   ```
3. Acepta la invitación al repo que te llegó por correo y clónalo:
   ```bash
   git clone https://github.com/Ricky182771/app-lista-asistencia.git
   cd app-lista-asistencia
   flutter pub get
   ```
4. Corre la app:
   ```bash
   flutter run -d chrome     # versión web
   flutter run               # en un celular Android conectado por USB
   ```

## Cómo trabajamos

`main` está protegida: nadie hace push directo, todo entra por pull request y Ricardo lo aprueba.

```bash
git switch main && git pull                 # parte siempre de lo más nuevo
git switch -c feat/importador-csv           # una rama por tarea
# ...cambios...
flutter analyze && flutter test             # antes de subir
git add -A
git commit -m "csv: detectar BOM y separador"
git push -u origin feat/importador-csv
gh pr create --fill                         # o ábrelo desde la página del repo
```

Nombres de rama: `feat/…` para algo nuevo, `fix/…` para corregir.
Si tu rama se queda atrás de `main`: `git fetch origin && git rebase origin/main`.

## Quién hace qué

| Quién | Módulo | Hito |
| --- | --- | --- |
| Ricardo | Base, Firebase, login y roles, reglas, pase de lista del profesor (vista por día y mensual, modo sin internet) | H0, H1, H3 |
| Compañero 1 | Pantallas del encargado de orden y generador del mensaje para padres | H4 |
| Compañero 2 | Importador de CSV con vista previa, alta de clases, manual de usuario | H2 |
| Los tres | Piloto con profes (30 nov – 4 dic) y correcciones | H5 |

## Estructura

```
firestore.rules          Reglas de seguridad por rol
firestore.indexes.json   Índices compuestos (vista mensual)
firebase.json            Hosting (build/web) y emuladores
scripts/bootstrap.sh     Genera el esqueleto de Flutter (solo se corrió una vez)
test/fixtures/csv/       CSV de prueba inventados
lib/                     Código de la app (se genera en el hito 0)
```

## Firebase (solo Ricardo)

```bash
firebase use --add                                   # liga el repo al proyecto de Firebase
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android,web        # genera lib/firebase_options.dart (sí se sube)
firebase emulators:start                             # probar reglas y login sin tocar producción
firebase deploy --only firestore:rules,firestore:indexes
flutter build web && firebase deploy --only hosting
```
