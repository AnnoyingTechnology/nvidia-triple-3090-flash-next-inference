#!/usr/bin/env bash
# Install the qualified drop-in; preserve the existing unit's limits and boot policy.
set -euo pipefail
test "$(id -u)" = 0 || { echo 'Run as root' >&2; exit 1; }
task_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
test -x "$task_root/updates/20261108/strata/.venv/bin/python"
test -x "$task_root/updates/20261108/build/strata/strata"
test -x "$task_root/build/vision/bin/strata-vision"
test -f /etc/systemd/system/qwen3.8-flash-next.service
task_dropin=/etc/systemd/system/qwen3.8-flash-next.service.d
mkdir -p "$task_dropin"
sed "s#@ROOT@#$task_root#g" "$task_root/updates/2026-11-08/selected.service.conf.in" > "$task_dropin/90-runtime-update.conf"
chmod 0644 "$task_dropin/90-runtime-update.conf"
systemctl daemon-reload
systemd-analyze verify qwen3.8-flash-next.service
echo 'Installed selected runtime; boot enablement and running requests are unchanged.'
