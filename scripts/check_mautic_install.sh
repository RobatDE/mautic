#!/bin/sh
set -eu

say() { printf "%s\n" "$*"; }
hr()  { printf "%s\n" "------------------------------------------------------------"; }

# 1) Locate Mautic root (tries common paths, then searches for local.php)
detect_root() {
  for d in \
    /var/www/symfony \
    /var/www/html \
    /opt/bitnami/mautic \
    /bitnami/mautic
  do
    [ -f "$d/config/local.php" ] && { echo "$d"; return 0; }
  done

  p="$(find / -maxdepth 5 -type f -name local.php 2>/dev/null | head -n1 || true)"
  if [ -n "${p:-}" ] && echo "$p" | grep -q "/config/local.php$"; then
    echo "${p%/config/local.php}"
    return 0
  fi

  # Fall back to probable docroot if present
  [ -f /var/www/html/index.php ] && { echo /var/www/html; return 0; }

  echo ""
  return 1
}

ROOT="$(detect_root || true)"
CONFIG=""
VAR=""
MEDIA=""

if [ -n "$ROOT" ]; then
  CONFIG="$ROOT/config"
  VAR="$ROOT/var"
  MEDIA="$ROOT/media"
fi

say "Mautic filesystem check (v2)"
hr
say "ROOT    : ${ROOT:-<not found>}"
say "CONFIG  : ${CONFIG:-<not found>}"
say "VAR     : ${VAR:-<not found>}"
say "MEDIA   : ${MEDIA:-<not found>}"
hr

# 2) Confirm mounts/space/permissions
say "# mounts"
mount | grep -E "$ROOT($|/config|/var|/media)" || true
hr

say "# space"
df -h "$CONFIG" "$VAR" "$MEDIA" 2>/dev/null || true
hr

say "# ownership & mode"
ls -ld "$CONFIG" "$VAR" "$MEDIA" 2>/dev/null || true
hr

# 3) Core file: config/local.php
LOCAL="$CONFIG/local.php"
say "# config/local.php"
if [ -f "$LOCAL" ]; then
  ls -l "$LOCAL"
  say ""
  say ">> key settings found:"
  # Extract common keys from the PHP array (safe grep; won't execute PHP)
  grep -E "'(installed|db_driver|db_host|db_name|db_user|site_url)'" "$LOCAL" || true
else
  say "NOT FOUND: $LOCAL"
  say "Hint: Inside this image, Mautic sources are expected under /var/www/symfony."
  say "If this is a fresh container, Mautic likely hasn't been installed yet (no config/local.php)."
  say "Use the web installer or CLI to complete installation, then re-run this check."
fi
hr

# 4) Cache and logs footprints (created after install/first run)
say "# cache directories (expect entries if app ran)"
[ -d "$VAR/cache" ] && find "$VAR/cache" -maxdepth 2 -type d -printf "%TY-%Tm-%Td %TH:%TM  %p\n" 2>/dev/null | head -n 50 || echo "no $VAR/cache"
hr

say "# log files (expect prod.log or similar)"
if [ -d "$VAR/log" ]; then
  ls -l "$VAR/log" 2>/dev/null || true
  tail -n 50 "$VAR/log"/prod.log 2>/dev/null || true
elif [ -d "$VAR/logs" ]; then
  ls -l "$VAR/logs" 2>/dev/null || true
  tail -n 50 "$VAR/logs"/prod.log 2>/dev/null || true
else
  echo "no $VAR/log or $VAR/logs"
fi
hr

# 5) Media directory existence (uploads live here)
say "# media directory"
[ -d "$MEDIA" ] && ls -lah "$MEDIA" | head -n 50 || echo "no $MEDIA"

# 6) Save a machine-readable snapshot too
OUT="/tmp/mautic_fs_snapshot_$(date +%s).txt"
say ""
say "Writing snapshot to: $OUT"
{
  echo "# ROOT=$ROOT"
  echo "# CONFIG=$CONFIG"
  echo "# VAR=$VAR"
  echo "# MEDIA=$MEDIA"
  echo "# ---- file listing (mode user:group size date path) ----"
  for d in "$CONFIG" "$VAR" "$MEDIA"; do
    [ -d "$d" ] || continue
    find "$d" -xdev -printf "%M %u:%g %s %TY-%Tm-%Td %TH:%TM %p\n" 2>/dev/null
  done
} > "$OUT"

say "Done."
