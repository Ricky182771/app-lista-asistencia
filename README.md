# PaseLista

App de lista de asistencia por clase para la escuela. Proyecto de servicio social.
*(El repo conserva el nombre `app-lista-asistencia`; el paquete de Dart es `app_lista_asistencia`).*

- **Profesores:** pasan lista en cada clase desde Android o desde el navegador (iPhone y computadoras). Funciona sin internet y sincroniza después.
- **Encargados de orden:** ven los ausentes de cada grupo y copian un mensaje listo para el grupo de padres.
- **Administrativos:** suben las listas en CSV, dan de alta clases, renombran o eliminan grupos e invitan usuarios.

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
| Ricardo | Base, Firebase, login, roles y reglas (terminados); pase de lista del profesor (vista por día y mensual, modo sin internet); vista del encargado de orden y mensaje para padres; revisión de PR | H0, H1, H3, H4 |
| Compañero de programación | Importador de CSV con vista previa, edición de alumnos y alta de clases | H2 |
| Compañero de documentación | Documento para la materia de proyectos, manual de usuario y coordinación del piloto (no programa) | — |
| Los tres | Piloto con profes (30 nov – 4 dic) y correcciones | H5 |

## Iniciar sesión en Android: registra tu SHA-1 (cada integrante)

El login con Google en Android solo funciona si la huella **SHA-1** de la llave con la que se
compila la app está registrada en Firebase. Cada computadora tiene su propia llave de depuración,
así que **cada integrante** debe registrar la suya una vez. Si falta, la app muestra
"Google rechazó esta instalación de la app (ApiException: 10)".

1. Saca tu SHA-1 (Linux/macOS; en Windows usa `%USERPROFILE%\.android\debug.keystore`):
   ```bash
   keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore \
     -storepass android -keypass android | grep SHA1
   ```
   (También sale con `cd android && ./gradlew signingReport`).
2. Mándasela a Ricardo. Él la agrega en Firebase → ⚙️ Configuración del proyecto → Tus apps →
   app de Android → **Agregar huella digital**.
3. Espera unos minutos y vuelve a intentar. No hace falta cambiar código ni `google-services.json`.

En web (`flutter run -d chrome`) no se necesita SHA-1.

## Crear el primer administrativo (una sola vez, solo Ricardo)

Nadie puede entrar sin invitación, y solo un admin puede invitar. El primero se crea a mano:

1. Firebase → **Firestore Database** → colección `invitaciones` → **Agregar documento**.
2. ID del documento: el correo de Google del admin **en minúsculas** (ej. `ana.perez@gmail.com`).
3. Un campo: `rol` (string) = `admin`.
4. Entra a la app con esa cuenta: se crea `usuarios/{uid}` con su nombre, foto y rol.

Desde ahí, ese admin invita a los demás con **Invitar usuario** (roles: `profesor`, `orden`, `admin`).

## Estructura

```
firestore.rules          Reglas de seguridad por rol
firestore.indexes.json   Índices compuestos (vista mensual)
firebase.json            Hosting (build/web) y emuladores
scripts/bootstrap.sh     Genera el esqueleto de Flutter (solo se corrió una vez)
scripts/publicar-apk.sh  Publica el APK en GitHub Releases (ver "Publicar una versión")
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

## Publicar una versión (solo Ricardo)

La web se actualiza sola con `firebase deploy --only hosting`. El APK se reparte por GitHub Releases con
un enlace fijo que siempre apunta a la última versión (es el que va en el manual y en el QR):

```
https://github.com/Ricky182771/app-lista-asistencia/releases/latest/download/PaseLista.apk
```

1. En un PR, sube la versión en `pubspec.yaml`: `1.1.0+2` → `1.1.1+3`. El número después del `+` es el
   `versionCode` de Android y **siempre** tiene que crecer; si no, el APK no se instala encima.
2. Ya fusionado, desde `main` actualizado: `scripts/publicar-apk.sh "Qué cambia"`. Revisa que exista
   `android/key.properties`: el APK se firma **siempre con la misma llave** (respáldala; si se pierde,
   todos tendrían que desinstalar y volver a instalar).
3. En la consola de Firebase, Firestore → `config/app`, pon los valores que imprime el script. A partir de
   ahí, cada APK viejo muestra "Ya está disponible PaseLista x.y.z" con el botón Descargar.
4. Solo si la versión anterior ya no debe usarse (por ejemplo, un cambio de reglas que la rompe), sube
   también `buildMinimo` al `buildActual` nuevo: los APK más viejos quedan bloqueados en la pantalla
   "Actualiza la app" hasta instalar la nueva. Úsalo poco: un profe sin datos en el celular no podría
   pasar lista hasta conseguir internet (le queda la web).

