# PaseLista

App de lista de asistencia por clase para una escuela. Proyecto de servicio social de un equipo de 3
estudiantes; Ricardo (Ricky182771) es el líder técnico y revisa todos los PR.
**Entrega: miércoles 9 de diciembre de 2026** (límite: antes del 10).

## Stack

- Flutter, solo **Android y web**. No hay iOS, Linux, Windows ni macOS: los profes con iPhone y
  quienes usan computadora entran por la versión web.
- Firebase, proyecto `paselista-9326a`, plan **Spark** (gratuito). **No hay Cloud Functions ni custom
  claims** (requieren el plan de pago): toda la lógica vive en la app y los permisos en `firestore.rules`.
- Firebase Auth con Google, Cloud Firestore y Firebase Hosting (sirve `build/web`).
- Android se distribuye como **APK directo**, sin Google Play. `applicationId`:
  `io.github.ricky182771.app_lista_asistencia`.

## Comandos

```bash
flutter pub get
flutter analyze                    # debe salir sin errores antes de cada commit
flutter test                       # debe pasar antes de cada commit
flutter run -d chrome              # web (Chromium vía CHROME_EXECUTABLE)
flutter run                        # Android con el celular conectado
firebase emulators:start           # Auth 9099, Firestore 8080, Hosting 5000
npm --prefix test/rules install    # una vez: dependencias de las pruebas de reglas
firebase emulators:exec --only firestore "npm --prefix test/rules test"   # pruebas de firestore.rules
firebase deploy --only firestore:rules,firestore:indexes
flutter build apk --release
flutter build web && firebase deploy --only hosting
```

Para correr la web en otro puerto no uses el 8080: es del emulador de Firestore.

## Roles

| Rol | Valor en `rol` | Qué hace |
| --- | --- | --- |
| Profesor | `profesor` | Pasa lista de sus clases y edita pases de los últimos 28 días |
| Encargado de orden | `orden` | Ve ausentes por grupo y copia un mensaje para el grupo de padres. Solo lee |
| Administrativo | `admin` | Sube listas en CSV, da de alta clases e invita usuarios |

Los alumnos no usan la app. Entra solo quien tiene invitación: el admin crea `invitaciones/{correo}` y,
en el primer inicio de sesión, la app crea `usuarios/{uid}` con el rol de la invitación. El primer
admin se crea a mano en la consola de Firebase.

## Modelo de datos (Firestore)

```
usuarios/{uid}               nombre, email, fotoUrl, rol
invitaciones/{email}         rol, creadoPor                  // ID = correo en minúsculas
grupos/{grupoId}             nombre, profesores: [uid], alumnos: [{num, nombre, activo}]
clases/{profesorUid}_{grupoId}
                             profesorUid, grupoId, materia (solo etiqueta), salon (el de siempre)
pases/{claseId}_{fecha}      claseId, grupoId, profesorUid, materia, salon (el real de ese día),
                             fecha "AAAA-MM-DD", marcadoEn, enviadoEn, editadoEn,
                             estados: { "<N.L>": 0 | 1 | 2 }
```

- **Estados de asistencia:** `0` presente, `1` falta, `2` falta justificada (sin motivo, solo la marca).
- **Una clase = profesor + grupo.** La materia es solo una etiqueta y el salón puede cambiar, así que
  ninguno de los dos forma parte del ID.
- **Un pase por clase por día.** Una materia que dura dos módulos seguidos es un solo pase.
- `grupos.profesores` lo mantiene el admin en el mismo `WriteBatch` con el que crea o borra una clase;
  las reglas lo usan para que un profe solo lea sus grupos.
- **Quitar acceso** = borrar `usuarios/{uid}` + `invitaciones/{correo}` en el mismo `WriteBatch`. Si
  solo se borra el usuario, la invitación sigue y la persona se da de alta sola al volver a entrar.
- Los IDs de `clases` y `pases` son **determinísticos** para que un reintento sin internet no duplique
  documentos.
- Editar un pase es un `update()` que solo toca `estados` y `editadoEn`
  (`{'estados.3': 2, 'editadoEn': FieldValue.serverTimestamp()}`). Las reglas solo dejan cambiar `estados`,
  `enviadoEn` y `editadoEn`; el salón y `marcadoEn` se fijan al crear el pase. Así, un pase del mismo día
  enviado sin internet desde otro dispositivo (otra hora en `marcadoEn`) se rechaza al sincronizar y el
  original queda intacto.
- El profe puede **crear o editar** pases de hoy y de los **últimos 28 días**, nunca de fechas futuras.
- Las consultas deben filtrar igual que las reglas (por ejemplo `where('profesorUid', isEqualTo: uid)`);
  si no, Firestore rechaza la consulta completa.

## Comportamiento clave

- **Sin internet:** el profe pasa lista y edita igual. Firestore guarda en caché y sincroniza solo. **No
  esperes con `await` el `set()`/`update()`**: el `Future` no se completa sin conexión. Muestra el
  estado con `metadata.hasPendingWrites`. En web hay que activar la persistencia:
  `FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);`
- **Vista mensual del profe:** una columna por cada día que tiene pase (no se guarda horario), cabecera
  con la fecha `AAAA-MM-DD`. Palomita verde = 0, equis roja = 1, punto negro sobre amarillo pastel = 2.
  Las columnas de hace más de 28 días son de solo lectura.
- **Mensaje para padres:** uno por grupo al día, a partir del **pase de la mañana** (el primero del día
  según `marcadoEn`). Lista solo nombres con falta sin justificar (`1`), sin materia. La app no se
  conecta a WhatsApp: genera el texto y lo copia al portapapeles.
- **Importación de CSV** (`N.L,Nombre completo`): quitar BOM, intentar UTF-8 y si falla usar `latin1`
  (Excel en Windows guarda en Windows-1252), detectar el separador (`,` `;` o tabulador), parsear con el
  paquete `csv` (nunca `split(',')`), descartar encabezado opcional y validar N.L enteros sin repetir.
  Los casos de prueba están en `test/fixtures/csv/` (ver su `LEEME.md`).

## Convenciones

- Interfaz y mensajes en **español de México**. Commits y PR en español.
- Código en `lib/models/`, `lib/services/` y `lib/screens/`. Sin paquetes de estado o navegación
  extra salvo que se justifiquen en el PR.
- Pruebas unitarias para la lógica pura (parseo de CSV, estados, fechas, armado del mensaje).
- Cualquier cambio a `firestore.rules` viene con sus pruebas en `test/rules/reglas.test.js`.
- Una rama por tarea (`feat/…`, `fix/…`, `chore/…`, `docs/…`). `main` está protegida: todo entra por PR
  con aprobación de Ricardo, con squash. Llena la plantilla `.github/pull_request_template.md`.

## Prohibido

- **El repo es público.** Nunca subir datos reales de alumnos ni de personal (nombres, correos, listas),
  ni CSV/Excel reales. Solo datos inventados en `test/fixtures/`. El `.gitignore` bloquea `*.csv` y
  `*.xlsx` fuera de esa carpeta: no lo saltes con `git add -f`.
- Nunca subir llaves de firma (`*.jks`, `key.properties`) ni cuentas de servicio de Firebase Admin.
  `firebase_options.dart` y `google-services.json` **sí** se suben: no son secretos.
- Pedir a Google más scopes que `openid email profile`. El login es solo para identificar al usuario.
- Agregar dependencias que requieran el plan de pago de Firebase (Cloud Functions, etc.).
- Cambiar `firestore.rules` sin explicarlo en el PR y probarlo en el emulador.

## Problemas conocidos

- **`google_sign_in` 7.x** cambió su API respecto a la 6. Lee el README de la versión instalada en
  `~/.pub-cache/hosted/pub.dev/google_sign_in-*/` en vez de usar ejemplos viejos. En web se usa
  `FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider())`, no `google_sign_in`.
- **`ApiException: 10` en Android** = falta la SHA-1 de la llave de depuración de esa computadora en
  Firebase. Cada integrante registra la suya:
  `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`.
- **Las reglas se despliegan solo desde `main` actualizado** (`git switch main && git pull` antes de
  `firebase deploy --only firestore:rules`). `deploy` sube el `firestore.rules` de la carpeta actual: desde
  una rama creada antes de un cambio de reglas se despliegan las reglas viejas y se deshace ese cambio en
  producción sin aviso. Si una rama de app queda atrás de un PR de reglas, actualízala con `git merge origin/main`.
- Si `flutter create` se vuelve a correr, revisa que `.metadata` siga listando `android` **y** `web`.
- **`firebase` instalado como binario standalone** (`curl -sL firebase.tools | bash`): dentro de
  `emulators:exec` usa su propio `npm`, que falla con `/bin/sh: --: opción inválida`. Instala la CLI con
  npm (`npm i -g firebase-tools`) o corre las pruebas con `npx firebase-tools emulators:exec …`.
- Las advertencias de AGP 9 sobre `org.jetbrains.kotlin.android` vienen de los plugins de Firebase; se
  pueden ignorar hasta que los actualicen.
- **Fechas UTC contra fecha local:** las reglas comparan contra fechas en UTC y la app usa la fecha
  local de México (detrás de UTC). El margen de un día en `editable()` (29 días contra la fecha UTC)
  cubre la diferencia para que hoy−28 local se acepte a cualquier hora.
- **`resource.data` y documentos que no existen:** una regla que lee `resource.data` niega la lectura
  de un documento que no existe (`resource` es `null`). Para documentos que pueden no existir todavía
  (por ejemplo el pase de hoy), se escucha una consulta filtrada igual que las reglas en vez del
  documento.
