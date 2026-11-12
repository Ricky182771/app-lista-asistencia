#!/usr/bin/env bash
# Genera el esqueleto de Flutter (Android + web) y agrega las dependencias.
# Lo corre UNA sola vez Ricardo (hito 0) y sube el resultado al repo.
# Tus compañeros NO lo corren: solo hacen `flutter pub get`.
set -euo pipefail

ORG="${ORG:-io.github.ricky182771}"   # define el applicationId de Android: $ORG.app_lista_asistencia
cd "$(dirname "$0")/.."

if [[ -f pubspec.yaml ]]; then
  echo "pubspec.yaml ya existe: el proyecto ya fue generado. Nada que hacer." >&2
  exit 1
fi

flutter create \
  --org "$ORG" \
  --project-name app_lista_asistencia \
  --platforms android,web \
  --description "App de lista de asistencia por clase" \
  .

flutter pub add \
  firebase_core firebase_auth cloud_firestore google_sign_in \
  csv intl file_picker

flutter analyze
echo
echo "Listo. Revisa con 'git status' y haz commit del esqueleto."
