#!/bin/sh
set -eu

say() { printf "%s\n" "$*"; }
warn() { printf "WARN: %s\n" "$*"; }
err() { printf "ERROR: %s\n" "$*" >&2; }

# Defaults (non-installing image)
: "${MAUTIC_RUN_INSTALLER:=false}"
: "${MAUTIC_DB_DRIVER:=pdo_mysql}"
: "${MAUTIC_DB_HOST:=localhost}"
: "${MAUTIC_DB_PORT:=3306}"
: "${MAUTIC_DB_NAME:=mautic}"
: "${MAUTIC_DB_USER:=mautic}"
: "${MAUTIC_DB_PASSWORD:=}"
: "${MAUTIC_SITE_URL:=http://localhost}"
: "${MAUTIC_SECRET_KEY:=}"
: "${MAUTIC_REMEMBERME_KEY:=}"

WEB_ROOT="/var/www/html"
CONFIG_FILE_A="$WEB_ROOT/config/local.php"
CONFIG_FILE_B="$WEB_ROOT/app/config/local.php"
TEMPLATE_PATH="/usr/local/share/mautic/local.php.template"

say "Starting php-fpm and Apache (web-only). Installer default: $MAUTIC_RUN_INSTALLER"

# Start php-fpm first
service php8.3-fpm start

# Lightweight DB readiness check (non-fatal).
# Prefer mariadb-admin ping for connectivity; log an optional mariadb-check for diagnostics.
DB_READY=0
if command -v mariadb-admin >/dev/null 2>&1; then
  for i in $(seq 1 60); do
    if [ -n "$MAUTIC_DB_PASSWORD" ]; then
      if mariadb-admin ping -h "$MAUTIC_DB_HOST" -P "$MAUTIC_DB_PORT" -u "$MAUTIC_DB_USER" -p"$MAUTIC_DB_PASSWORD" --silent; then
        DB_READY=1; break
      fi
    else
      if mariadb-admin ping -h "$MAUTIC_DB_HOST" -P "$MAUTIC_DB_PORT" -u "$MAUTIC_DB_USER" --silent 2>/dev/null; then
        DB_READY=1; break
      fi
    fi
    sleep 2
  done
else
  warn "mariadb-admin not found; skipping DB ping"
fi

if [ "$DB_READY" -eq 1 ]; then
  say "Database reachable at $MAUTIC_DB_HOST:$MAUTIC_DB_PORT"
  if command -v mariadb-check >/dev/null 2>&1; then
    # Non-fatal sanity check against the target DB (suppress output on success)
    if [ -n "$MAUTIC_DB_PASSWORD" ]; then
      mariadb-check -h "$MAUTIC_DB_HOST" -P "$MAUTIC_DB_PORT" -u "$MAUTIC_DB_USER" -p"$MAUTIC_DB_PASSWORD" "$MAUTIC_DB_NAME" >/dev/null 2>&1 || warn "mariadb-check reported issues (non-fatal)"
    else
      mariadb-check -h "$MAUTIC_DB_HOST" -P "$MAUTIC_DB_PORT" -u "$MAUTIC_DB_USER" "$MAUTIC_DB_NAME" >/dev/null 2>&1 || warn "mariadb-check reported issues (non-fatal)"
    fi
  fi
else
  warn "Database NOT reachable after timeout; proceeding to start web anyway"
fi

# If no local.php exists, render from template using environment values
if [ ! -f "$CONFIG_FILE_A" ] && [ ! -f "$CONFIG_FILE_B" ]; then
  if [ -f "$TEMPLATE_PATH" ]; then
    say "Rendering local.php from template"
    # Generate secrets if not provided
    if [ -z "$MAUTIC_SECRET_KEY" ]; then
      if command -v openssl >/dev/null 2>&1; then
        MAUTIC_SECRET_KEY="$(openssl rand -hex 32)"
      else
        MAUTIC_SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
      fi
    fi
    if [ -z "$MAUTIC_REMEMBERME_KEY" ]; then
      if command -v openssl >/dev/null 2>&1; then
        MAUTIC_REMEMBERME_KEY="$(openssl rand -hex 20)"
      else
        MAUTIC_REMEMBERME_KEY="$(head -c 20 /dev/urandom | od -An -tx1 | tr -d ' \n')"
      fi
    fi

    mkdir -p "$(dirname "$CONFIG_FILE_A")"
    TMP_FILE="${CONFIG_FILE_A}.tmp"
    sed -e "s/{{DB_DRIVER}}/${MAUTIC_DB_DRIVER}/g" \
        -e "s/{{DB_HOST}}/${MAUTIC_DB_HOST}/g" \
        -e "s/{{DB_PORT}}/${MAUTIC_DB_PORT}/g" \
        -e "s/{{DB_NAME}}/${MAUTIC_DB_NAME}/g" \
        -e "s/{{DB_USER}}/${MAUTIC_DB_USER}/g" \
        -e "s/{{DB_PASSWORD}}/${MAUTIC_DB_PASSWORD}/g" \
        -e "s#{{SITE_URL}}#${MAUTIC_SITE_URL}#g" \
        -e "s/{{SECRET_KEY}}/${MAUTIC_SECRET_KEY}/g" \
        -e "s/{{REMEMBERME_KEY}}/${MAUTIC_REMEMBERME_KEY}/g" \
        "$TEMPLATE_PATH" > "$TMP_FILE"
    mv "$TMP_FILE" "$CONFIG_FILE_A"
    chown www-data:www-data "$CONFIG_FILE_A"
  else
    warn "Template not found at $TEMPLATE_PATH; local.php will not be pre-rendered"
  fi
fi

# Optional non-interactive installer (disabled by default)
if [ "$MAUTIC_RUN_INSTALLER" = "true" ]; then
  if [ ! -f "$CONFIG_FILE_A" ] && [ ! -f "$CONFIG_FILE_B" ]; then
    say "MAUTIC_RUN_INSTALLER=true and no local.php found; running CLI installer"
    cd "$WEB_ROOT"
    PHP_BIN="$(command -v php || true)"
    if [ -z "$PHP_BIN" ]; then
      err "php binary not found in PATH"; exit 1
    fi
    # Minimal install args to generate local.php. Admin user can be set later if not provided.
    ARGS="--db_driver=$MAUTIC_DB_DRIVER --db_host=$MAUTIC_DB_HOST --db_port=$MAUTIC_DB_PORT --db_name=$MAUTIC_DB_NAME --db_user=$MAUTIC_DB_USER --db_password=$MAUTIC_DB_PASSWORD"
    if [ -n "${MAUTIC_ADMIN_USERNAME:-}" ] && [ -n "${MAUTIC_ADMIN_EMAIL:-}" ] && [ -n "${MAUTIC_ADMIN_PASSWORD:-}" ] && [ -n "${MAUTIC_ADMIN_FIRSTNAME:-}" ] && [ -n "${MAUTIC_ADMIN_LASTNAME:-}" ]; then
      ARGS="$ARGS --admin_firstname=$MAUTIC_ADMIN_FIRSTNAME --admin_lastname=$MAUTIC_ADMIN_LASTNAME --admin_username=$MAUTIC_ADMIN_USERNAME --admin_email=$MAUTIC_ADMIN_EMAIL --admin_password=$MAUTIC_ADMIN_PASSWORD"
    fi
    "$PHP_BIN" -d memory_limit=-1 bin/console mautic:install $ARGS "$MAUTIC_SITE_URL" || warn "Installer exited non-zero"
  else
    say "local.php already present; skipping installer"
  fi
fi

# Finally, start Apache in foreground
exec apache2ctl -D FOREGROUND
