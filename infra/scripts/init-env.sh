#!/bin/sh
# Génère infra/.env à partir de .env.example en remplaçant chaque CHANGE_ME
# par un secret aléatoire. Fonctionne sous Linux, macOS et Git Bash (Windows).
#
#   sh scripts/init-env.sh          # crée .env s'il n'existe pas
#   sh scripts/init-env.sh --force  # écrase un .env existant
set -eu

cd "$(dirname "$0")/.."

if [ -f .env ] && [ "${1:-}" != "--force" ]; then
  echo ".env existe déjà (utiliser --force pour l'écraser)." >&2
  exit 1
fi

# $1 = nombre d'octets aléatoires -> 2*$1 caractères hexadécimaux
rand_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'
  fi
}

secret_for() {
  case "$1" in
    GARAGE_RPC_SECRET|S3_SECRET_ACCESS_KEY|AUTHENTIK_SECRET_KEY) rand_hex 32 ;;
    S3_ACCESS_KEY_ID|RALLLY_SECRET_PASSWORD) rand_hex 16 ;;
    *) rand_hex 18 ;;
  esac
}

tmp=".env.tmp.$$"
: > "$tmp"
# tr -d '\r' : tolère un .env.example converti en CRLF par Git sous Windows
tr -d '\r' < .env.example | while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    *=CHANGE_ME)
      key=${line%%=*}
      printf '%s=%s\n' "$key" "$(secret_for "$key")" >> "$tmp"
      ;;
    *)
      printf '%s\n' "$line" >> "$tmp"
      ;;
  esac
done
mv "$tmp" .env
chmod 600 .env 2>/dev/null || true

echo ".env généré. Mot de passe akadmin (Authentik) :"
grep '^AUTHENTIK_BOOTSTRAP_PASSWORD=' .env | cut -d= -f2
