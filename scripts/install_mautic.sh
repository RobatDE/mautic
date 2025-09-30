#!/bin/sh
set -eu

# install_mautic.sh
# Installs Mautic non-interactively using the CLI inside the container or host.
# It supports two modes:
#  1) Config-file mode:  install_mautic.sh --config=/path/to/install_config.php [--root=/var/www/symfony]
#  2) Env-var mode:      provide MAUTIC_DB_* and MAUTIC_ADMIN_* variables and it will pass them to mautic:install
#     (Backwards-compatible: legacy DB_*/ADMIN_*/SITE_URL are still accepted if MAUTIC_* are not set.)
#
# Defaults:
#  - MAUTIC_ROOT defaults to /var/www/symfony
#  - MAUTIC_DB_DRIVER defaults to pdo_mysql
#  - MAUTIC_DB_PORT   defaults to 3306
#
# Example (env-var mode):
#  MAUTIC_ROOT=/var/www/symfony \
#  DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=mautic DB_USER=mautic DB_PASSWORD=secret \
#  ADMIN_FIRSTNAME=Admin ADMIN_LASTNAME=User ADMIN_USERNAME=admin ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=Secret123 \
#  /home/install_mautic.sh
#
# Example (config-file mode):
#  /home/install_mautic.sh --config=/home/install_config.php --root=/var/www/symfony

say() { printf "%s\n" "$*"; }
err() { printf "ERROR: %s\n" "$*" >&2; }
hr()  { printf "%s\n" "------------------------------------------------------------"; }

MAUTIC_ROOT="${MAUTIC_ROOT:-/var/www/symfony}"
CONFIG_FILE=""
MAUTIC_SITE_URL="${MAUTIC_SITE_URL:-${SITE_URL:-http://localhost}}"
MAUTIC_ROOT=. 
MAUTIC_DB_DRIVER=pdo_mysql 
MAUTIC_DB_HOST=db 
MAUTIC_DB_PORT=3306 
MAUTIC_DB_NAME=mautic 
MAUTIC_DB_USER=mautic 
MAUTIC_DB_PASSWORD=mautic_password 
MAUTIC_ADMIN_FIRSTNAME=Admin 
MAUTIC_ADMIN_LASTNAME=User 
MAUTIC_ADMIN_USERNAME=admin 
MAUTIC_ADMIN_EMAIL=admin@expona.ai 
MAUTIC_ADMIN_PASSWORD=NextExpona1234 

# Parse args
for arg in "$@"; do
  case "$arg" in
    --config=*) CONFIG_FILE="${arg#*=}" ;;
    --root=*)   MAUTIC_ROOT="${arg#*=}" ;;
    --site_url=*|--site-url=*) MAUTIC_SITE_URL="${arg#*=}" ;;
    -h|--help)
      cat <<EOF
Usage:
  $0 [--root=/var/www/symfony] [--config=/path/to/install_config.php] [--site_url=https://example.com]

If --config is omitted, the script expects these environment variables:
  MAUTIC_DB_DRIVER (default: pdo_mysql)
  MAUTIC_DB_HOST, MAUTIC_DB_PORT (default: 3306), MAUTIC_DB_NAME, MAUTIC_DB_USER, MAUTIC_DB_PASSWORD
  MAUTIC_ADMIN_FIRSTNAME, MAUTIC_ADMIN_LASTNAME, MAUTIC_ADMIN_USERNAME, MAUTIC_ADMIN_EMAIL, MAUTIC_ADMIN_PASSWORD
  MAUTIC_SITE_URL (optional, default: http://localhost) — the public base URL for this Mautic instance

Legacy fallback (if corresponding MAUTIC_* vars are not set):
  DB_DRIVER, DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
  ADMIN_FIRSTNAME, ADMIN_LASTNAME, ADMIN_USERNAME, ADMIN_EMAIL, ADMIN_PASSWORD
  SITE_URL
EOF
      exit 0
      ;;
  esac
done

# Basic checks
if [ ! -d "$MAUTIC_ROOT" ]; then
  err "Mautic root not found: $MAUTIC_ROOT"
  exit 1
fi
if [ ! -f "$MAUTIC_ROOT/bin/console" ]; then
  err "Symfony console not found at $MAUTIC_ROOT/bin/console"
  exit 1
fi

PHP_BIN="${PHP_BIN:-$(command -v php || true)}"
if [ -z "$PHP_BIN" ]; then
  err "php binary not found in PATH; set PHP_BIN or install PHP"
  exit 1
fi

# If already installed, warn and continue only if MAUTIC_FORCE=1
LOCAL_PHP="$MAUTIC_ROOT/config/local.php"
if [ -f "$LOCAL_PHP" ] && [ "${MAUTIC_FORCE:-0}" != "1" ]; then
  say "Detected existing install: $LOCAL_PHP"
  say "Set MAUTIC_FORCE=1 to proceed anyway."
  exit 0
fi

cd "$MAUTIC_ROOT"

if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    err "Config file not found: $CONFIG_FILE"
    exit 1
  fi
  say "Running Mautic installer (config-file mode)"
  hr
  set -x
  "$PHP_BIN" -d memory_limit=-1 bin/console mautic:install --config="$CONFIG_FILE" "$MAUTIC_SITE_URL"
  set +x
else
  # Env-var mode (prefer MAUTIC_*; fallback to legacy names)
  E_DB_DRIVER="${MAUTIC_DB_DRIVER:-${DB_DRIVER:-pdo_mysql}}"
  E_DB_HOST="${MAUTIC_DB_HOST:-${DB_HOST:-}}"
  E_DB_PORT="${MAUTIC_DB_PORT:-${DB_PORT:-3306}}"
  E_DB_NAME="${MAUTIC_DB_NAME:-${DB_NAME:-}}"
  E_DB_USER="${MAUTIC_DB_USER:-${DB_USER:-}}"
  E_DB_PASSWORD="${MAUTIC_DB_PASSWORD:-${DB_PASSWORD:-}}"

  E_ADMIN_FIRSTNAME="${MAUTIC_ADMIN_FIRSTNAME:-${ADMIN_FIRSTNAME:-}}"
  E_ADMIN_LASTNAME="${MAUTIC_ADMIN_LASTNAME:-${ADMIN_LASTNAME:-}}"
  E_ADMIN_USERNAME="${MAUTIC_ADMIN_USERNAME:-${ADMIN_USERNAME:-}}"
  E_ADMIN_EMAIL="${MAUTIC_ADMIN_EMAIL:-${ADMIN_EMAIL:-}}"
  E_ADMIN_PASSWORD="${MAUTIC_ADMIN_PASSWORD:-${ADMIN_PASSWORD:-}}"
  E_SITE_URL="${MAUTIC_SITE_URL:-${SITE_URL:-http://localhost}}"

  # Validate required envs
  missing=""
  for v in E_DB_HOST E_DB_NAME E_DB_USER E_DB_PASSWORD E_ADMIN_FIRSTNAME E_ADMIN_LASTNAME E_ADMIN_USERNAME E_ADMIN_EMAIL E_ADMIN_PASSWORD E_SITE_URL; do
    eval "val=\${$v:-}"
    [ -n "$val" ] || missing="$missing ${v#E_}"
  done
  if [ -n "$missing" ]; then
    err "Missing required environment variables:$missing"
    exit 1
  fi

  say "Running Mautic installer (env-var mode)"
  hr
  set -x
  "$PHP_BIN" -d memory_limit=-1 bin/console mautic:install \
    --db_driver="$E_DB_DRIVER" \
    --db_host="$E_DB_HOST" \
    --db_port="$E_DB_PORT" \
    --db_name="$E_DB_NAME" \
    --db_user="$E_DB_USER" \
    --db_password="$E_DB_PASSWORD" \
    --admin_firstname="$E_ADMIN_FIRSTNAME" \
    --admin_lastname="$E_ADMIN_LASTNAME" \
    --admin_username="$E_ADMIN_USERNAME" \
    --admin_email="$E_ADMIN_EMAIL" \
    --admin_password="$E_ADMIN_PASSWORD" \
    "$E_SITE_URL"
  set +x
fi

say "Installation command completed."
