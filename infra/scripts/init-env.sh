#!/bin/sh
# Génère ou complète infra/.env à partir de .env.example.
# Fonctionne sous Linux, macOS et Git Bash (Windows).
#
#   sh scripts/init-env.sh          # 1er lancement : crée .env avec des secrets aléatoires
#                                   # ensuite      : ajoute seulement les clés manquantes ou vides
#                                   #                (les secrets existants ne sont JAMAIS modifiés)
#   sh scripts/init-env.sh --force  # régénère tout (à combiner avec "docker compose down -v")
set -eu

cd "$(dirname "$0")/.."

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
    GARAGE_RPC_SECRET|S3_SECRET_ACCESS_KEY|AUTHENTIK_SECRET_KEY|RALLLY_OIDC_CLIENT_SECRET) rand_hex 32 ;;
    S3_ACCESS_KEY_ID|RALLLY_SECRET_PASSWORD) rand_hex 16 ;;
    DEMO_USERS_PASSWORD) printf 'Demo-%s' "$(rand_hex 4)" ;;
    *) rand_hex 18 ;;
  esac
}

# Valeur d'une ligne d'exemple, avec génération si CHANGE_ME
resolve() { # $1=clé $2=valeur exemple
  if [ "$2" = "CHANGE_ME" ]; then secret_for "$1"; else printf '%s' "$2"; fi
}

if [ "${1:-}" = "--force" ]; then
  rm -f .env
fi

tmp=".env.tmp.$$"
trap 'rm -f "$tmp"' EXIT

if [ ! -f .env ]; then
  # --- Création complète ------------------------------------------------------
  : > "$tmp"
  # tr -d '\r' : tolère un fichier converti en CRLF sous Windows
  tr -d '\r' < .env.example | while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) printf '%s\n' "$line" >> "$tmp" ;;
      *=*) key=${line%%=*}; printf '%s=%s\n' "$key" "$(resolve "$key" "${line#*=}")" >> "$tmp" ;;
      *) printf '%s\n' "$line" >> "$tmp" ;;
    esac
  done
  mv "$tmp" .env
  echo ".env créé."
else
  # --- Mise à jour : clés absentes ajoutées, clés vides complétées ------------
  tr -d '\r' < .env > "$tmp"
  tr -d '\r' < .env.example | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | while IFS= read -r line; do
    key=${line%%=*}
    example_value=${line#*=}
    [ -z "$example_value" ] && continue
    current=$(grep -E "^${key}=" "$tmp" | head -n 1 | cut -d= -f2- || true)
    if ! grep -qE "^${key}=" "$tmp"; then
      printf '%s=%s\n' "$key" "$(resolve "$key" "$example_value")" >> "$tmp"
      echo "  + $key (ajoutée)"
    elif [ -z "$current" ]; then
      value=$(resolve "$key" "$example_value")
      awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k && !done {print k "=" v; done=1; next} {print}' "$tmp" > "$tmp.2"
      mv "$tmp.2" "$tmp"
      echo "  ~ $key (était vide, complétée)"
    fi
  done
  mv "$tmp" .env
  echo ".env mis à jour (valeurs existantes conservées)."
fi
chmod 600 .env 2>/dev/null || true

echo
echo "Admin Authentik  : akadmin / $(grep '^AUTHENTIK_BOOTSTRAP_PASSWORD=' .env | cut -d= -f2-)"
echo "Comptes de démo  : alice, bob, charlie / $(grep '^DEMO_USERS_PASSWORD=' .env | cut -d= -f2-)"
