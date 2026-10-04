#!/usr/bin/env bash
# build_grader.sh for the 3x3090 host: wget fallback, slim grader base, host-network build (the Docker
# daemon there has no bridge and no iptables), then the four isolated grader controls.
set -euo pipefail
task_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
task_rev=28fef95ea8c9f7a547c8329f2cd3d32b92c1fa24
task_image=x3090/eval:lcb-28fef95
mkdir -p "$task_root/eval-source"
for task_file in lcb_runner/evaluation/testing_util.py LICENSE; do
    wget --quiet --tries=3 --output-document "$task_root/eval-source/$(basename "$task_file")" \
        "https://raw.githubusercontent.com/LiveCodeBench/LiveCodeBench/$task_rev/$task_file"
done
echo "b7cb6a8a69807bb868150a61742e25d7bb5328bbe01d514471b6ec43c9fa9ed2  $task_root/eval-source/testing_util.py" \
    | sha256sum --check
docker build --network host -f "$task_root/Dockerfile.eval-x3090" -t "$task_image" "$task_root"
cd "$task_root"
ULMUS_GRADER="$task_image" python3 -c 'import json, eval; print(json.dumps(eval.control(), indent=2))' \
    > "$task_root/results/grader-controls-x3090.json"
echo "grader controls passed: $task_image $(docker image inspect "$task_image" --format '{{.Id}}')"
