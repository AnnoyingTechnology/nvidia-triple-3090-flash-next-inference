"""Render a checkout-relative profile into the absolute runtime config the native server reads.

Public profiles stay free of host paths: relative paths are resolved against the checkout's
upstream/strata directory (the server's working directory). The rendered config goes to
results/runtime/, which is not published.
"""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'upstream' / 'strata'
PATH_OPTIONS = {'--pack', '--native', '--expert-profile', '--mtp'}


def absolute(value):
    path = Path(value)
    return str(path if path.is_absolute() else (SOURCE / path).resolve())


def render(name):
    cfg = json.loads((ROOT / 'profiles' / (name + '.json')).read_text())
    args = list(cfg['args'])
    for index, value in enumerate(args[:-1]):
        if value in PATH_OPTIONS:
            args[index + 1] = absolute(args[index + 1])
    cfg['args'] = args
    for key in ('exe', 'tokenizer', 'log', 'cwd'):
        if key in cfg:
            cfg[key] = absolute(cfg[key])
    if cfg.get('vision'):
        cfg['vision'] = dict(cfg['vision'])
        for key in ('exe', 'mmproj', 'model'):
            cfg['vision'][key] = absolute(cfg['vision'][key])
    if cfg.get('host') not in ('127.0.0.1', '::1'):
        raise SystemExit('profiles for the 3x3090 host must listen on loopback only')
    out = ROOT / 'results' / 'runtime' / (name + '.json')
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(cfg, indent=2) + '\n')
    shared = ROOT / 'profiles' / (name + '.shared-settings.json')
    if shared.exists():
        out.with_suffix('.shared-settings.json').write_text(shared.read_text())
    return out


if __name__ == '__main__':
    print(render(sys.argv[1]))
