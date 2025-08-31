# syntax=docker/dockerfile:1.7
FROM alpine:latest

# ---- Metadata ----
ARG REPO_URL="https://github.com/warrenrees/rsyncd-backups"
ARG TITLE="rsyncd-backups"
ARG DESCRIPTION="Non-root rsyncd exposing /backups with env-based authentication."
ARG LICENSE="MIT"
ARG VERSION="dev"

LABEL org.opencontainers.image.title="${TITLE}" \
      org.opencontainers.image.description="${DESCRIPTION}" \
      org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="${LICENSE}"

ENV RSYNCD_VERSION=$VERSION

# ---- Packages ----
RUN apk add --no-cache rsync netcat-openbsd libcap

# ---- Non-root user & writable dirs ----
RUN addgroup -g 1000 rsync && adduser -D -u 1000 -G rsync rsync \
  && mkdir -p /backups /var/lib/rsyncd \
  && chown -R rsync:rsync /backups /var/lib/rsyncd

# ---- Grant the needed file capabilities to the rsync binary ----
#    - cap_setgid, cap_setuid: lets rsyncd call setgroups() / switch creds
#    - cap_fowner: lets non-owners set times/modes (utime/chmod) when needed
RUN setcap 'cap_setgid,cap_setuid,cap_fowner=ep' /usr/bin/rsync \
 && getcap /usr/bin/rsync

# ---- Config template (points to /var/lib/rsyncd) ----

RUN set -eux; cat > /etc/rsyncd.conf.template <<'CONF'
use chroot = no
strict modes = yes
list = no
munge symlinks = yes
reverse lookup = no
refuse options = devices specials xattrs
max connections = 10
pid file  = /var/lib/rsyncd/rsyncd.pid
log file  = /dev/stdout
lock file = /var/lib/rsyncd/rsyncd.lock
timeout   = 300

# Bind/port come from env; entrypoint substitutes these:
port    = ${RSYNC_PORT}
address = ${RSYNC_ADDR}

# Auth is still required:
auth users   = ${RSYNC_USER}
secrets file = /var/lib/rsyncd/rsyncd.secrets

transfer logging = yes

[backups]
    path = /backups
    comment = Backups Share
    read only = false
    list = no
    numeric ids = yes
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
#HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
#  CMD nc -z localhost 873 || exit 1

# ---- Start (invoke via /bin/sh to avoid shebang/CRLF issues) ----
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
