#!/usr/bin/env bash
# Publica el APK release de la versión de pubspec.yaml en GitHub Releases como PaseLista.apk.
# El enlace fijo .../releases/latest/download/PaseLista.apk siempre apunta a la última versión.
# Uso, desde main actualizado y con la versión ya subida en pubspec.yaml:
#   scripts/publicar-apk.sh "Notas de la versión"
set -euo pipefail
cd "$(dirname "$0")/.."

notas="${1:-}"
if [[ -z "$notas" ]]; then
  echo "Uso: scripts/publicar-apk.sh \"Qué cambia en esta versión\"" >&2
  exit 1
fi

# Sin la llave de release, Gradle firma con la de depuración y el APK no se instala encima del anterior.
if [[ ! -f android/key.properties ]]; then
  echo "Falta android/key.properties: el APK quedaría firmado con la llave de depuración." >&2
  exit 1
fi
if [[ "$(git rev-parse --abbrev-ref HEAD)" != main ]]; then
  echo "Publica desde main (git switch main && git pull)." >&2
  exit 1
fi
git fetch -q origin main
if [[ -n "$(git status --porcelain)" || "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "main tiene cambios sin subir o no está al día con origin/main." >&2
  exit 1
fi

linea="$(grep -m1 '^version:' pubspec.yaml)"      # version: 1.1.0+2
completa="${linea#version: }"
version="${completa%%+*}"
build="${completa##*+}"
etiqueta="v$version"
if git ls-remote --exit-code --tags origin "refs/tags/$etiqueta" > /dev/null; then
  echo "Ya existe $etiqueta: sube la versión en pubspec.yaml (y el número después del +)." >&2
  exit 1
fi

flutter build apk --release
mkdir -p build/publicar
cp build/app/outputs/flutter-apk/app-release.apk build/publicar/PaseLista.apk

gh release create "$etiqueta" build/publicar/PaseLista.apk \
  --target main --title "PaseLista $version" --notes "$notas"

repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
cat <<FIN

Publicado $etiqueta. Ahora, en la consola de Firebase, Firestore → config/app:
  versionActual  (string)  $version
  buildActual    (number)  $build
  urlApk         (string)  https://github.com/$repo/releases/latest/download/PaseLista.apk
  buildMinimo    (number)  solo si esta versión es obligatoria; si no, déjalo como está
FIN
