## Quick start
```bash
docker run -d --name rsyncd \
  -e RSYNC_USER=backupuser \
  -e RSYNC_PASS=SuperSecret123 \
  -v /host/backups:/backups \
  -p 873:873 \
  --restart unless-stopped \
  warrenrees/rsyncd-backups:latest
