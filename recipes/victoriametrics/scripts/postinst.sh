#!/bin/sh
set -eu

if ! getent group victoriametrics >/dev/null 2>&1; then
  groupadd --system victoriametrics >/dev/null 2>&1 || groupadd victoriametrics
fi

if ! getent passwd victoriametrics >/dev/null 2>&1; then
  useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin \
    --gid victoriametrics victoriametrics >/dev/null 2>&1 \
    || useradd -M -r -d /nonexistent -s /sbin/nologin -g victoriametrics victoriametrics
fi

install -d -m 0755 -o victoriametrics -g victoriametrics /var/lib/victoria-metrics

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi
