#!/bin/sh
set -e

log() { echo "[mautic-entrypoint] $*"; }

# Respect arbitrary commands; default to apache2-foreground if no args are passed.
first="$1"
if [ -z "$first" ]; then
  set -- apache2-foreground
  first="$1"
fi

case "$first" in
  apache2-foreground|php-fpm|php-fpm8.3)
    DB_HOST="${MAUTIC_DB_HOST:-}"
    DB_PORT="${MAUTIC_DB_PORT:-3306}"
    DB_USER="${MAUTIC_DB_USER:-root}"
    DB_PASS="${MAUTIC_DB_PASSWORD:-}"
    DB_NAME="${MAUTIC_DB_NAME:-mautic}"
    # Determine DB client and auth flags
    PASS_ARGS=""
    if [ -n "$DB_PASS" ]; then
      PASS_ARGS="-p$DB_PASS"
    fi

    if command -v mysql >/dev/null 2>&1; then
      DB_CLIENT="mysql"
    elif command -v mariadb >/dev/null 2>&1; then
      DB_CLIENT="mariadb"
    else
      log "No MySQL/MariaDB client found; skipping DB checks"
      exec docker-php-entrypoint "$@"
    fi

    if [ -n "$DB_HOST" ]; then
      ATTEMPTS=0
      MAX_ATTEMPTS="${DB_WAIT_ATTEMPTS:-60}"
      while ! "$DB_CLIENT" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $PASS_ARGS -e 'SELECT 1' >/dev/null 2>&1; do
        ATTEMPTS=$((ATTEMPTS+1))
        if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
          log "MySQL not ready after $ATTEMPTS attempts; continuing startup"
          break
        fi
        log "Waiting for MySQL at $DB_HOST:$DB_PORT... (attempt $ATTEMPTS/$MAX_ATTEMPTS)"
        sleep 2
      done

      if "$DB_CLIENT" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" $PASS_ARGS -N -B \
        -e "SELECT 1 FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name IN ('users','migrations') LIMIT 1;" \
        >/dev/null 2>&1; then
        log "Detected existing Mautic database '$DB_NAME'. Disabling installer."
        export MAUTIC_RUN_INSTALLER=false
      else
        log "No Mautic tables detected in '$DB_NAME'."
      fi
    fi
    ;;
  *)
    # Arbitrary command; skip checks
    :
    ;;
esac

# Chain to the upstream entrypoint with all original args
exec docker-php-entrypoint "$@"
