"""Component numeric checks of the native SM86 build on the real IQ3_S target; not full-size quality parity.

Native counterpart of check_eddoursul_native.py for the 3x3090 host (no image). Each GPU check runs on the
one card named by --gpu (nvidia-smi numbering). Run only while no inference service owns that card.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build' / 'strata'
SHARD = ROOT / 'models/gsq-iq3_s/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf'
TESTS = [
    ('sampler', 'sampler_parity', ['--selftest']),
    ('ple-reader', 'ple_reader_test', ['--selftest', '--dir', '/tmp']),
    ('pinned-shared', 'pinned_shared_test', []),
    ('coupled-draft', 'coupled_draft_test', []),
    ('conversation-cache', 'conversation_cache_test', []),
    ('conversation-memory', 'conversation_memory_test', []),
    ('qsa-prompt-attention', 'qsa_prompt_attn_parity', []),
    ('iq3-native-experts', 'native_expert_parity', [str(SHARD)]),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--gpu', default='1')
    ap.add_argument('--out', default=str(ROOT / 'results/native-components.json'))
    args = ap.parse_args()
    out = Path(args.out)
    if out.exists():
        raise SystemExit(f'{out} exists; choose a new --out')
    env = dict(os.environ, CUDA_DEVICE_ORDER='PCI_BUS_ID', CUDA_VISIBLE_DEVICES=args.gpu)
    report = {'scope': 'Component numeric tests on the real GSQ IQ3_S target; not full-size quality parity.',
              'observed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'source_pin': '99f3dbd0b21d1401b3769e0c0d963913607f380b', 'cuda_arch': 'sm_86',
              'gpu': args.gpu, 'native_sha256': hashlib.sha256((BUILD / 'strata').read_bytes()).hexdigest(),
              'tests': []}
    for label, executable, test_args in TESTS:
        start = time.monotonic()
        try:
            run = subprocess.run([str(BUILD / executable), *test_args], env=env, text=True,
                                 capture_output=True, timeout=900)
            row = {'name': label, 'passed': run.returncode == 0, 'exit_code': run.returncode,
                   'elapsed_s': round(time.monotonic() - start, 2), 'stdout': run.stdout[-20000:],
                   'stderr': run.stderr[-4000:]}
        except subprocess.TimeoutExpired:
            row = {'name': label, 'passed': False, 'error': 'Component check exceeded 900 seconds'}
        report['tests'].append(row)
        report['summary'] = {'passed': sum(t['passed'] for t in report['tests']), 'total': len(TESTS)}
        out.write_text(json.dumps(report, indent=2) + '\n')
        print(label, row['passed'], row.get('elapsed_s'), flush=True)
    if report['summary']['passed'] != len(TESTS):
        raise SystemExit('Native component check failed')


if __name__ == '__main__':
    main()
