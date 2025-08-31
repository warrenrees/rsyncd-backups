#!/bin/sh
set -e

SECRETS="/var/lib/rsyncd/rsyncd.secrets"
CONF_TMPL="/etc/rsyncd.conf.template"
CONF_OUT="/var/lib/rsyncd/rsyncd.conf"
LOGFILE="/var/lib/rsyncd/rsyncd.log"

# Build secrets from env
if [ -n "${RSYNC_USERS:-}" ]; then
  : > "$SECRETS"
  AUTH_USERS=""
  IFS=',' 
  for pair in $RSYNC_USERS; do
    pair_trimmed=$(echo "$pair" | tr -d ' ')
    user=$(echo "$pair_trimmed" | awk -F: '{print $1}')
    pass=$(echo "$pair_trimmed" | awk -F: '{print $2}')
    if [ -z "$user" ] || [ -z "$pass" ]; then
      echo "[entrypoint] ERROR: Invalid RSYNC_USERS entry: '$pair' (expected user:pass)" >&2
      exit 1
    fi
    echo "${user}:${pass}" >> "$SECRETS"
    [ -z "$AUTH_USERS" ] && AUTH_USERS="$user" || AUTH_USERS="$AUTH_USERS,$user"
  done
  unset IFS
  export RSYNC_USER="$AUTH_USERS"
elif [ -n "${RSYNC_USER:-}" ] && [ -n "${RSYNC_PASS:-}" ]; then
  echo "${RSYNC_USER}:${RSYNC_PASS}" > "$SECRETS"
else
  echo "[entrypoint] ERROR: Set RSYNC_USERS=\"user:pass,...\" OR RSYNC_USER and RSYNC_PASS." >&2
  exit 1
fi

chmod 600 "$SECRETS"

# Render config with resolved user list
sed "s/\${RSYNC_USER}/${RSYNC_USER}/g" "$CONF_TMPL" > "$CONF_OUT"

# Ensure log file exists for tailing
: > "$LOGFILE"

# Startup logs
echo "[entrypoint] Rsync daemon starting..."
echo "[entrypoint] Users configured: $RSYNC_USER"
echo "[entrypoint] Backups share path: /backups"
echo "[entrypoint] Config file: $CONF_OUT"
echo "[entrypoint] Log file: $LOGFILE"

# Stream rsyncd log to stdout so `docker logs` shows ongoing activity
# (background; rsync remains PID1 after exec)
tail -F "$LOGFILE" &

# IMPORTANT: Do NOT chown /backups here (non-root, and it may be a bind mount).
# Ensure /backups exists; if it’s a bind mount, the host must grant UID 1000 write perms.
mkdir -p /backups || true

# Launch rsyncd in foreground (non-detached) with our config
exec rsync --daemon --no-detach --config="$CONF_OUT"
