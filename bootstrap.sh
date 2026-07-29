#!/usr/bin/env bash
# Descarga el examen y prepara el entorno de una sola vez.
#   curl -sL https://raw.githubusercontent.com/TU-USUARIO/cka-helm-practice/main/bootstrap.sh | bash
set -uo pipefail

GH_USER="${GH_USER:-TU-USUARIO}"
BRANCH="${GH_BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${GH_USER}/cka-helm-practice/${BRANCH}"
DEST="${HOME}/cka-helm-practice"

echo
echo "  Descargando cka-helm-practice desde ${GH_USER}..."
mkdir -p "$DEST" && cd "$DEST" || exit 1

for f in setup.sh exam.sh; do
  curl -fsSL "${RAW}/${f}" -o "$f" || { echo "  no he podido descargar ${f} desde ${RAW}"; exit 1; }
done
chmod +x setup.sh exam.sh

exec ./setup.sh
