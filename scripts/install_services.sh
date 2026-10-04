#!/usr/bin/env bash
# Render and install the two mutually exclusive model services of the 3x3090 host (root).
# usage: install_services.sh [qwen-serving checkout]   (default: <checkout owner's home>/qwen-serving)
# Enables nothing: choose the boot default with `systemctl enable <unit>` afterwards.
set -euo pipefail
test "$(id -u)" = 0 || { echo 'run as root' >&2; exit 1; }
task_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_user=$(stat -c %U "$task_root")
task_home=$(getent passwd "$task_user" | cut -d: -f6)
task_serving=${1:-$task_home/qwen-serving}
test -x "$task_root/upstream/strata/.venv/bin/python"
test -x "$task_root/build/strata/strata"
test -f "$task_serving/single-user/start_qwen.sh"
for task_unit in qwen3.8-flash-next qwen-3.8-27b; do
    sed -e "s#@ROOT@#$task_root#g" -e "s#@SERVING@#$task_serving#g" \
        -e "s#@USER@#$task_user#g" -e "s#@HOME@#$task_home#g" \
        "$task_root/systemd/$task_unit.service.in" > "/etc/systemd/system/$task_unit.service"
    chmod 0644 "/etc/systemd/system/$task_unit.service"
done
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/qwen3.8-flash-next.service /etc/systemd/system/qwen-3.8-27b.service
echo 'installed qwen3.8-flash-next.service and qwen-3.8-27b.service'
