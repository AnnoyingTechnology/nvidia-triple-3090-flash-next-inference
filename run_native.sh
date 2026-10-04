#!/usr/bin/env bash
# Start one 3x3090 profile as the transient systemd unit flashnext-x3090 (no Docker on this host).
# Run as root: only root can grant the unlimited memlock the pinned expert arena and the locked
# n-gram table need. The server itself runs as the checkout owner, on loopback, without swap.
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")" && pwd)
task_profile=${1:?usage: run_native.sh <profile>}
task_unit=flashnext-x3090
task_memory=${X3090_MEMORY_MAX:-88G}
task_owner=$(stat -c %U "$task_root")
[[ "$task_profile" =~ ^x3090-[a-z0-9-]+$ ]] || { echo 'expected an x3090-* profile' >&2; exit 2; }
test -f "$task_root/profiles/$task_profile.json"
test "$(id -u)" = 0 || { echo 'run as root (memlock)' >&2; exit 1; }
# Refuse resource collisions: either model service, our own unit, or any foreign compute process.
for task_other in qwen-3.8-27b.service qwen3.8-flash-next.service "$task_unit.service"; do
    if systemctl is-active --quiet "$task_other"; then
        echo "$task_other is active; stop it first" >&2
        exit 1
    fi
done
systemctl reset-failed "$task_unit.service" 2>/dev/null || true
task_foreign=$(nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader \
    | grep -v 'gnome-remote-desktop-daemon' || true)
if test -n "$task_foreign"; then
    echo "foreign GPU compute workload: $task_foreign" >&2
    exit 1
fi
task_config=$(runuser -u "$task_owner" -- python3 "$task_root/scripts/x3090_runtime.py" "$task_profile")
runuser -u "$task_owner" -- env ULMUS_ROOT="$task_root" ULMUS_MEMORY_MAX="$task_memory" \
    python3 "$task_root/launch_record.py" "$task_profile" native
task_env=()
if test "${ULMUS_DECODE_TIMING:-0}" = 1; then
    task_env+=(--setenv=STRATA_DECODE_TIMING=1)
fi
systemd-run --unit="$task_unit" --uid="$task_owner" --gid="$task_owner" \
    --working-directory="$task_root/upstream/strata" \
    --property=LimitMEMLOCK=infinity --property=MemoryMax="$task_memory" --property=MemorySwapMax=0 \
    --property=KillMode=control-group --property=TimeoutStopSec=90 \
    --setenv=HOME="$(getent passwd "$task_owner" | cut -d: -f6)" \
    --setenv=PATH="$task_root/upstream/strata/.venv/bin:/usr/bin:/bin" \
    --setenv=PYTHONUNBUFFERED=1 "${task_env[@]}" \
    "$task_root/upstream/strata/.venv/bin/python" -m serve.server --engine strata \
    --config "$task_config" --port 19623
