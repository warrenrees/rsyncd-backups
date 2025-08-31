#!/bin/sh
set -e

SECRETS="/var/lib/rsyncd/rsyncd.secrets"
CONF_TMPL="/etc/rsyncd.conf.template"
CONF_OUT="/var/lib/rsyncd/rsyncd.conf"

# Defaults for K8s friendliness
RSYNC_PORT="${RSYNC_PORT:-873}"
RSYNC_ADDR="${RSYNC_ADDR:-0.0.0.0}"

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

# Render config
sed -e "s/\${RSYNC_USER}/${RSYNC_USER}/g" \
    -e "s/\${RSYNC_PORT}/${RSYNC_PORT}/g" \
    -e "s/\${RSYNC_ADDR}/${RSYNC_ADDR}/g" \
    "$CONF_TMPL" > "$CONF_OUT"

# Preflight: ensure writable state dir and share exist
mkdir -p /var/lib/rsyncd || true
mkdir -p /backups || true

# Write test in state dir (common K8s issue if wrong fsGroup/permissions)
if ! sh -c "echo test > /var/lib/rsyncd/.writable"; then
  echo "[entrypoint] ERROR: /var/lib/rsyncd is not writable by UID $(id -u). In K8s set fsGroup or fix volume perms." >&2
  ls -ld /var/lib/rsyncd >&2 || true
  id >&2 || true
  exit 1
fi
rm -f /var/lib/rsyncd/.writable || true

echo "[entrypoint] Container version: ${RSYNCD_VERSION:-unknown}"
echo "[entrypoint] Rsync daemon starting"
echo "[entrypoint] UID:GID $(id -u):$(id -g)"
echo "[entrypoint] Users: ${RSYNC_USER}"
echo "[entrypoint] Bind: ${RSYNC_ADDR}:${RSYNC_PORT}"
echo "[entrypoint] State dir: /var/lib/rsyncd"
echo "[entrypoint] Share: /backups"
echo "[entrypoint] Config: ${CONF_OUT}"

# Exec rsync in foreground; logs go to stdout per template
exec rsync --daemon --no-detach --config="$CONF_OUT" --verbose
