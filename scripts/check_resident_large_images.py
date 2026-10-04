"""Check new/cached/new maximum-budget images on a loaded RESIDENT-vision profile (3x3090 host).

Same images and payloads as check_swap_large_images.py; resident vision never lends cache memory,
so every request must show zero LEND/RECLAIM events. Binds to the native unit (X3090_UNIT)."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bench import request
from scripts.evaluation_provenance import capture, assert_container


def gray_png(value):
    side = 2048
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = (b'\0' + bytes([value]) * side * 3) * side
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', side, side, 8, 2, 0, 0, 0)) + \
        chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--engine-log', type=Path, required=True)
    args = ap.parse_args()
    if args.out.exists():
        raise SystemExit('Output exists; use a fresh label')
    url = 'http://127.0.0.1:19623'
    runtime = capture(url)
    log = args.engine_log
    offset = log.stat().st_size
    report = {'scope': 'Maximum-budget resident-vision reliability, not vision quality or matched latency.',
              'runtime_image_id': runtime['identity']['image_id'], 'image_pixels': [2048, 2048], 'checks': []}
    for value, cached in [(191, False), (191, True), (192, False)]:
        data = gray_png(value)
        payload = {'model': 'ulmus', 'messages': [{'role': 'user', 'content': [
            {'type': 'text', 'text': 'Return exactly READY. Do not use tools.'},
            {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,' + base64.b64encode(data).decode()}}]}],
            'reasoning_effort': 'low', 'seed': 42, 'temperature': 1, 'top_p': .95, 'top_k': 20,
            'min_p': 0, 'presence_penalty': 0, 'repetition_penalty': 1,
            'max_tokens': 8192, 'stream': True, 'stream_options': {'include_usage': True}}
        assert_container(runtime)
        result = request(url, payload)
        assert_container(runtime)
        contents = log.read_bytes()
        section = contents[offset:].decode(errors='replace')
        offset = len(contents)
        lends = len(re.findall(r'strata serve: LEND done,', section))
        reclaims = len(re.findall(r'strata serve: RECLAIM done,', section))
        ok = result['finish_reason'] == 'stop' and result['content'].strip() == 'READY' and \
            result['usage']['prompt_tokens'] >= 4096 and lends == reclaims == 0 and \
            'FAILED' not in section and 'CUDA error' not in section
        report['checks'].append({'image_sha256': hashlib.sha256(data).hexdigest(),
            'input_sha256': hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest(),
            'cached': cached, 'cached_tokens': result['usage'].get('prompt_tokens_details', {}).get('cached_tokens'), 'lend_done': lends, 'reclaim_done': reclaims,
            'passed': ok, 'finish_reason': result['finish_reason'], 'content': result['content'],
            'usage': result['usage'], 'ttft_s': result['ttft_s'], 'total_s': result['total_s'],
            'gpu_peak_mib': result.get('gpu_peak_mib')})
        args.out.write_text(json.dumps(report, indent=2) + '\n')
        print(report['checks'][-1], flush=True)
        if not ok:
            raise SystemExit('Resident image verification failed; preserve the report')


if __name__ == '__main__':
    main()
