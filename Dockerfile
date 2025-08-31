# syntax=docker/dockerfile:1.7
FROM alpine:latest

# ---- Metadata ----
ARG REPO_URL="https://github.com/warrenrees/rsyncd-backups"
ARG TITLE="rsyncd-backups"
ARG DESCRIPTION="Non-root rsyncd exposing /backups with env-based authentication."
ARG VERSION="0.1.0"
ARG LICENSE="MIT"

LABEL org.opencontainers.image.title="${TITLE}" \
      org.opencontainers.image.description="${DESCRIPTION}" \
      org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="${LICENSE}"

# ---- Packages ----
RUN apk add --no-cache rsync netcat-openbsd

# ---- Non-root user & writable dirs ----
RUN addgroup -g 1000 rsync && adduser -D -u 1000 -G rsync rsync \
  && mkdir -p /backups /var/lib/rsyncd \
  && chown -R rsync:rsync /backups /var/lib/rsyncd

# ---- Config template (points to /var/lib/rsyncd) ----
RUN set -eux; \
  cat > /etc/rsyncd.conf.template <<'CONF'
uid = rsync
gid = rsync
use chroot = no
max connections = 10
strict modes = yes
pid file = /var/lib/rsyncd/rsyncd.pid
log file = /var/lib/rsyncd/rsyncd.log
timeout = 300
auth users = ${RSYNC_USER}
secrets file = /var/lib/rsyncd/rsyncd.secrets

[backups]
    path = /backups
    comment = Backups Share
    read only = false
    list = yes
CONF

# ---- Entrypoint ----
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && sed -i 's/\r$//' /entrypoint.sh

# Pre-create runtime files where the non-root user can write
RUN : > /var/lib/rsyncd/rsyncd.secrets \
 && : > /var/lib/rsyncd/rsyncd.conf \
 && chown rsync:rsync /var/lib/rsyncd/rsyncd.secrets /var/lib/rsyncd/rsyncd.conf \
 && chmod 600 /var/lib/rsyncd/rsyncd.secrets

# ---- Runtime user ----
USER rsync

EXPOSE 873/tcp

# ---- Healthcheck ----
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD nc -z localhost 873 || exit 1

# ---- Start (invoke via /bin/sh to avoid shebang/CRLF issues) ----
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
