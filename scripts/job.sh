#!/usr/bin/env bash
# Detached, identifiable long job: results/jobs/<name>.{log,pid,done}. Refuses to reuse a name.
# usage: scripts/job.sh <name> <command> [args...]
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_name=${1:?usage: job.sh name command...}
shift
[[ "$task_name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo 'invalid job name' >&2; exit 2; }
task_dir="$task_root/results/jobs"
mkdir -p "$task_dir"
for task_suffix in log pid done; do
    if test -e "$task_dir/$task_name.$task_suffix"; then
        echo "job $task_name already exists; choose a new name" >&2
        exit 1
    fi
done
cd "$task_root"
setsid nohup bash -c 'date -Is; "$@"; task_status=$?; date -Is; echo "$task_status" > "'"$task_dir/$task_name.done"'"' \
    job "$@" > "$task_dir/$task_name.log" 2>&1 < /dev/null &
echo $! > "$task_dir/$task_name.pid"
echo "started $task_name pid $(cat "$task_dir/$task_name.pid")"
