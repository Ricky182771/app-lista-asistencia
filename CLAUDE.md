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
scripts/publicar-apk.sh "Notas"    # desde main: sube el APK a GitHub Releases (ver README)
flutter build web && firebase deploy --only hosting
```

Para correr la web en otro puerto no uses el 8080: es del emulador de Firestore.

## Roles

| Rol | Valor en `rol` | Qué hace |
| --- | --- | --- |
| Profesor | `profesor` | Pasa lista de sus clases y edita pases de los últimos 28 días |
| Encargado de orden | `orden` | Ve ausentes por grupo y copia un mensaje para el grupo de padres; consulta la vista mensual de cualquier clase y la exporta. Solo lee |
| Administrativo | `admin` | Sube listas en CSV, da de alta clases, renombra o elimina grupos e invita usuarios; consulta la vista mensual de cualquier clase y la exporta (sin editar pases) |

Los alumnos no usan la app. Entra solo quien tiene invitación: el admin crea `invitaciones/{correo}` y,
en el primer inicio de sesión, la app crea `usuarios/{uid}` con el rol de la invitación. El primer
admin se crea a mano en la consola de Firebase.

## Modelo de datos (Firestore)

```
usuarios/{uid}               nombre, email, fotoUrl, rol
invitaciones/{email}         rol, creadoPor                  // ID = correo en minúsculas
grupos/{grupoId}             nombre, profesores: [uid], alumnos: [{num, nombre, activo}]
clases/{id generado}         profesorUid, profesorNombre, grupoId, materia, salon (el de siempre)
pases/{claseId}_{fecha}      claseId, grupoId, profesorUid, materia, salon (el real de ese día),
                             fecha "AAAA-MM-DD", marcadoEn, enviadoEn, editadoEn,
                             estados: { "<N.L>": 0 | 1 | 2 }
config/app                   versionActual, buildActual, buildMinimo (opcional), urlApk
```

- **Estados de asistencia:** `0` presente, `1` falta, `2` falta justificada (sin motivo, solo la marca).
- **Una clase = profesor + grupo + materia.** Un profe puede dar varias materias al mismo grupo; lo que no
  se repite es el mismo profe con la misma materia en un grupo (`materiaRepetida`, sin distinguir
  mayúsculas ni acentos). El ID lo genera Firestore en el cliente (`collection('clases').doc()`) al dar de
  alta, así la materia y el salón se corrigen con un `update()` sin cambiar el ID del que dependen los
  pases. Hay clases viejas con ID `{profesorUid}_{grupoId}`: siguen sirviendo porque todo usa `doc.id`.
- `clases.profesorNombre` es una copia de `usuarios/{profesorUid}.nombre`, porque el encargado de orden
  no puede leer `usuarios` (las reglas solo dejan al admin y a cada quien su documento). La pone el admin al
  dar de alta la clase, y `AdminHome` la llena en clases viejas y la corrige si el profe cambió de nombre
  (`nombresDesactualizados`), así que se pone al día la próxima vez que un admin abre la app. Si el profe
  pierde el acceso, su clase conserva el último nombre.
- **Un pase por clase por día.** Una materia que dura dos módulos seguidos es un solo pase.
- `grupos.profesores` lo mantiene el admin en el mismo `WriteBatch` con el que crea o borra una clase;
  las reglas lo usan para que un profe solo lea sus grupos. Al borrar una clase, el profe solo sale de
  `profesores` si ya no le queda otra clase con ese grupo (`quitarProfeDelGrupo`).
- **Renombrar grupo** = `update()` solo de `nombre`. El ID (que sale de `idGrupo(nombre)` al importar)
  **no cambia**, porque de él dependen `clases.grupoId` y `pases.grupoId`: un grupo renombrado conserva el
  ID de su nombre original. Por eso no se repiten nombres (`errorRenombrar`, `grupoConMismoNombre`, sin
  distinguir mayúsculas, acentos ni símbolos) y el importador revisa nombres **y** IDs.
- **Eliminar grupo** (`borrarGrupo`, menú ⋮ en la lista de grupos y en la pantalla del grupo) borra en
  cascada sus pases, sus clases y el grupo, en lotes de 400 (límite de `WriteBatch`: 500). Es lo único que
  **sí** espera con `await` y **pide internet**: clases y pases se leen con `Source.server`, porque la
  caché podría no tener todos los pases y quedarían huérfanos. El grupo va en el último lote: si algo
  falla a medio camino, sigue en la lista y se reintenta. Después de borrar las clases ya no entra ningún
  pase atrasado (las reglas piden que la clase exista), y un repaso final borra los que llegaron mientras
  tanto. Se confirma escribiendo el nombre del grupo (`confirmaNombre`). No se puede deshacer.
- **Quitar acceso** = borrar `usuarios/{uid}` + `invitaciones/{correo}` en el mismo `WriteBatch`. Si
  solo se borra el usuario, la invitación sigue y la persona se da de alta sola al volver a entrar.
- **Cambiar rol** (`cambiarRol`, menú ⋮ del usuario) actualiza `usuarios/{uid}.rol` y `invitaciones/{correo}.rol`
  (con `merge`: el primer admin puede no tener invitación) en el mismo `WriteBatch`; el usuario ve su
  pantalla nueva al instante. Candados en `errorCambioRol`: nadie cambia su propio rol y un profe con clases
  no cambia de rol hasta que se reasignen o se borren.
- Los IDs de `pases` son **determinísticos** para que un reintento sin internet no duplique documentos.
  Los de `clases` ya no: se generan una sola vez en el cliente, y un reintento reusa ese mismo ID.
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
  estado con `metadata.hasPendingWrites`. En web la persistencia en disco se activa solo si la
  computadora no es compartida (`configurarWeb()` en `lib/services/sesion.dart`, ver abajo).
- **Computadoras compartidas (web):** "Entrar con Google" siempre muestra el selector de cuentas
  (`prompt: select_account`). La casilla "Computadora compartida" siempre empieza marcada y la elección se
  guarda en `localStorage` al tocar "Entrar con Google". Lo guardado solo lo usa `configurarWeb()` al cargar
  la página: compartida = sesión de pestaña (`Persistence.SESSION`) y caché de Firestore solo en memoria
  (además borra la de IndexedDB). En ese modo, sin internet solo se conserva lo que esté abierto en la
  pestaña: si se cierra o recarga, se pierde lo no sincronizado.
  **Riesgo que queda:** si un profe desmarca la casilla en una computadora compartida, la siguiente carga
  de la página usa caché en disco, y los datos del siguiente profe pueden quedar en IndexedDB hasta la
  carga siguiente, cuando `configurarWeb()` los borra (porque ese profe entró con la casilla marcada).
- **Teléfono (menos de 600 px de ancho, `esCompacto`):** la vista por día y la mensual usan su versión
  compacta. En la del día, el encabezado (fecha, estado, salón y leyenda) va dentro de la lista y se va
  con el scroll; el botón Enviar/Guardar queda fijo. Leyenda con cuadros chicos y "Justificada" en vez de
  "Falta justificada". En la mensual, columnas de 60 px con cabecera "lun 23" (`encabezadoDia`, la fecha
  completa en el tooltip) y nombres en letra chica en hasta dos líneas. Las filas conservan 48 px de alto.
- **Vista mensual del profe:** una columna por cada día que tiene pase (no se guarda horario), cabecera
  con la fecha `AAAA-MM-DD` (en el teléfono, "lun 23"). Palomita verde = 0, equis roja = 1, punto negro sobre amarillo pastel = 2.
  Las columnas de hace más de 28 días son de solo lectura. La columna Nombre se ensancha arrastrando su
  borde (doble clic la regresa al ancho automático; `anchoNombre()` la limita al 75 % de la pantalla). En
  web el ancho se guarda en `localStorage` (`paselista.anchoNombre`); en Android dura mientras la app esté
  abierta.
- **Resumen del día (admin):** primera pestaña del inicio del admin (`ResumenDia`, lógica en
  `lib/models/resumen_dia.dart`). Une todas las clases con los pases de un día (hoy por omisión, con
  selector de fecha): "X de Y clases con pase", faltas del día, profes con clases y ningún pase, y la
  lista de clases con filtro (Todas / Sin pase / Con pase) y por grupo. Tocar una clase abre su vista
  mensual en solo consulta. **No hay horario**: una clase sin pase puede no haber tenido clase ese día,
  así que solo se resalta (`resaltar`) si alguien más pasó lista ese día; en un día sin ningún pase
  (fin de semana, festivo) no se resalta nada. Solo lee (`todasLasClases` y `pasesDeLaFecha`).
- **Inicio del admin:** tres pestañas (Resumen, Grupos y Usuarios). **Grupos**: importar CSV; cada grupo con sus alumnos y número de
  clases, y al tocarlo su pantalla con las clases. **Usuarios**: "Invitar usuario", filtro por rol
  (Todos, Profesores, Encargados de orden, Administrativos, con cuántos hay de cada uno), "Esperando su
  primer inicio de sesión" (invitaciones sin usar, con la ✕ para cancelarlas) y "Con acceso" (quitar
  acceso), con buscador (nombre, correo o rol) y el filtro "Profesores sin clases". Cada usuario tiene un
  menú ⋮ con **Cambiar rol** y **Quitar acceso** (el admin no puede hacer ninguna de las dos consigo
  mismo). Una invitación sale de "Esperando…" en cuanto esa persona entra (`invitacionesSinUsar`, que
  compara correos normalizados); la pestaña cuenta las que esperan. La cuenta y cerrar sesión van en el
  menú del avatar de la barra (`_MenuCuenta`); los otros roles siguen usando `Inicio`.
- **Vista mensual para admin y orden:** `PaseMensual(soloLectura: true)` vía `abrirConsultaMensual`. Admin
  la abre desde cada clase en la pantalla del grupo; orden, desde el detalle del grupo (ícono de calendario,
  elige la clase si hay varias). No se edita nada y las consultas van **sin** `profesorUid`
  (`pasesDelMes(null, …)`), lo que usa el índice `claseId + fecha` de `firestore.indexes.json`: hay que
  desplegarlo (`firebase deploy --only firestore:indexes`) o Firestore rechaza la consulta.
- **Exportar registro** (botón de descarga en la vista mensual, para los tres roles): lee todos los pases
  de la clase con una sola consulta (`pasesDeLaClase`), se eligen meses y formato, y se guarda con
  `FilePicker.saveFile` (en web se descarga; en Android abre "Guardar como"). **.xlsx**: una hoja por mes
  con P/F/J en los colores de la app, totales con `COUNTIF` (con el resultado ya guardado), % de
  asistencia y faltas por día; con varios meses, una hoja "Resumen" al principio. **.csv**: una sola
  tabla plana, UTF-8 con BOM, comas y CRLF. % asistencia = P / (P + F + J). El .xlsx lo arma
  `lib/models/xlsx.dart` sin paquetes (ZIP sin compresión); no agregues uno para esto.
- **Profe y salón en la vista de orden:** el pase de la mañana, las otras clases del día, el selector
  "Vista mensual de…" y la vista mensual en solo consulta muestran "Prof. Nombre · Salón A7"
  (`profeYSalon`). En el detalle del grupo el salón es el real del pase; en la vista mensual, el de siempre
  de la clase. El .xlsx exportado lleva lo mismo en el título de cada hoja (el nombre del archivo no).
- **Actualizaciones del APK:** el APK se publica en GitHub Releases como `PaseLista.apk` con
  `scripts/publicar-apk.sh` (ver README, "Publicar una versión"). `config/app` dice cuál es la última:
  si el `+N` de `pubspec.yaml` de este APK es menor que `buildActual`, cada inicio muestra la tarjeta
  "Ya está disponible…" (`AvisoActualizacionTarjeta`); si es menor que `buildMinimo`,
  `PuertaActualizacion` (alrededor del inicio de cada rol en `main.dart`) muestra "Actualiza la app" en
  vez del inicio. Solo en Android: la web siempre es la desplegada. Si `config/app` no existe, viene mal
  (`avisoActualizacion` exige `buildActual` numérico y `urlApk` https) o no se puede leer, no avisa ni
  bloquea. Lo lee cualquier usuario dado de alta (`registrado()` en las reglas); solo el admin lo escribe,
  por ahora desde la consola de Firebase.
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
- **Versión vieja en web después de desplegar:** Firebase Hosting manda `max-age=3600` por omisión y los
  archivos de Flutter web (`main.dart.js`, `flutter_bootstrap.js`) no llevan hash en el nombre, así que el
  navegador seguía usando el build anterior hasta una hora. `firebase.json` manda `Cache-Control: no-cache`
  para todo: el navegador revalida en cada carga (con ETag; si no cambió, la respuesta es un 304 vacío).
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
