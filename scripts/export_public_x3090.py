"""Export the evidence allowlist to results/public and summarize the placement probes.

Drops per-sample telemetry, local paths and private addresses; the manifest records the private
source and public export hashes (checked by scripts/check_public.py).
"""
import hashlib
import json
from pathlib import Path
import re
import statistics

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'results/public'
FILES = [
    'native-components.json', 'grader-controls-x3090.json',
    'api-check-smoke-20261004.json', 'api-check-gpu12-b-20261004.json', 'api-check-gpu12-c-20261004.json',
    'api-check-service-20261004.json',
    'context-decode-gpu12-a-20261004.json', 'context-decode-gpu102-a-20261004.json',
    'context-decode-gpu1-a-20261004.json', 'context-decode-gpu12-c-20261004.json',
    'context-decode-gpu12-b-long-20261004.json',
    'practical30-gpu12-low-s42.json', 'vision15-gpu12-low-20261004.json',
    'large-images-gpu12-b-20261004.json',
]
PROBES = {'gpu1-a': 'One card (GPU1), KV streaming past 32K', 'gpu12-a': 'Split GPU1+GPU2, launch a',
          'gpu12-c': 'Split GPU1+GPU2, launch c', 'gpu102-a': 'Split GPU1, GPU0, GPU2',
          'gpu12-b-long': 'Split GPU1+GPU2, launch b, 256K/64K anchors'}


def clean(value):
    if isinstance(value, dict):
        return {key: clean(item) for key, item in value.items() if key != 'telemetry'}
    if isinstance(value, list):
        return [clean(item) for item in value]
    if isinstance(value, str):
        value = re.sub(r'/home/[^/\s]+/[^\s"\n]+', '<local-path>', value)
        value = re.sub(r'/tmp/[^\s"\n]+', '<temp-path>', value)
        return re.sub(r'(?<![\d.])(?:10|192\.168)\.\d+\.\d+(?:\.\d+)?(?![\d.])', '<host-address>', value)
    return value


def summarize():
    rows = {}
    for key, label in PROBES.items():
        path = ROOT / 'results' / f'context-decode-{key}-20261004.json'
        if not path.exists():
            continue
        report = json.loads(path.read_text())
        row = {'label': label, 'documents_sha256': report['documents_sha256'], 'contexts': {}}
        for size in sorted({c['context_k'] for c in report['cells']}):
            cells = [c for c in report['cells'] if c['context_k'] == size]
            first = cells[0]
            row['contexts'][str(size)] = {
                'decode_tok_s': [c['decode_tok_s'] for c in cells],
                'decode_median_tok_s': statistics.median(c['decode_tok_s'] for c in cells),
                'first_read': {'read_tokens': first['read_tokens'], 'reused_tokens': first['reused_tokens'],
                               'prompt_s': round(first['prompt_ms'] / 1000, 2)},
                'all_board_power_median_w': round(statistics.median(c['median_power_w'] for c in cells), 1),
                'acceptance': round(sum(c['draft_n_accepted'] for c in cells) / sum(c['draft_n'] for c in cells), 4),
                'finish_reasons': sorted({c['finish_reason'] for c in cells}),
                'input_sha256': [c['input_sha256'] for c in cells]}
        rows[key] = row
    return {'scope': 'Fixed 512-token low-reasoning performance cells (not quality evidence); 225 W on every card. '
                     'Power is board power summed over all three GPUs, including the idle vision/desktop card.',
            'matched_with_ulmus': '32K/64K/128K documents and the 32K/128K request hashes equal the Ulmus '
                                  'adapt-batch ABBA cells (results/public/adapt-batch-20261004-summary.json).',
            'probes': rows}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {'method': 'Explicit allowlist; remove per-sample telemetry, local paths and private addresses',
                'private_exclusions': ['Engine/server logs', 'Host inventory', 'Downloaded binaries and model files'],
                'sources': {}}
    for name in FILES:
        source = ROOT / 'results' / name
        if not source.exists():
            continue
        raw = source.read_bytes()
        public = json.dumps(clean(json.loads(raw)), indent=2) + '\n'
        (OUT / name).write_text(public)
        manifest['sources'][name] = {'private_sha256': hashlib.sha256(raw).hexdigest(),
                                     'public_export_sha256': hashlib.sha256(public.encode()).hexdigest()}
    summary = json.dumps(summarize(), indent=2) + '\n'
    (OUT / 'placement-20261004-summary.json').write_text(summary)
    (OUT / 'export-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    leaks = [p.name for p in OUT.glob('*.json') if re.search(r'/home/|(?<![\d.])10\.\d+\.\d+\.\d+', p.read_text())]
    if leaks:
        raise SystemExit(f'private identifiers remain in {leaks}')
    print('exported', len(manifest['sources']), 'files to', OUT.relative_to(ROOT))


if __name__ == '__main__':
    main()
