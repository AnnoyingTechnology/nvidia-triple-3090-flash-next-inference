#!/usr/bin/env bash
# Stop the transient flashnext-x3090 unit only; models, builds and results stay.
set -euo pipefail
test "$(id -u)" = 0 || { echo 'run as root' >&2; exit 1; }
if systemctl is-active --quiet flashnext-x3090.service; then
    systemctl stop flashnext-x3090.service
fi
systemctl reset-failed flashnext-x3090.service 2>/dev/null || true
for task_try in {1..60}; do
    if test -z "$(nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader \
        | grep -v 'gnome-remote-desktop-daemon' || true)"; then
        exit 0
    fi
    sleep 1
done
echo 'GPU compute processes remain after stopping the unit' >&2
exit 1
