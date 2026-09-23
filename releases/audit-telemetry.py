#!/usr/bin/env python3
"""Fail closed when the reviewed source or regenerated vendor tree changes."""
import hashlib
import json
from pathlib import Path
import sys

IGNORED = {'.git', '.tools', '_patches', 'out', '__pycache__'}


def snapshot(root):
    root = Path(root)
    for required in ('go.mod', 'go.sum', 'vendor/modules.txt'):
        if not (root / required).is_file():
            raise ValueError('Incomplete source tree: missing ' + required)
    groups = {'source': [], 'vendor': []}

    def walk(directory):
        for item in sorted(directory.iterdir()):
            if directory == root and item.name in IGNORED:
                continue
            relative = item.relative_to(root).as_posix()
            if item.is_symlink():
                raise ValueError('Unreviewed source symlink: ' + relative)
            if item.is_dir():
                walk(item)
            elif item.is_file():
                group = 'vendor' if relative.startswith('vendor/') else 'source'
                groups[group].append((relative, hashlib.sha256(item.read_bytes()).hexdigest()))

    walk(root)
    result = {}
    for group, entries in groups.items():
        entries.sort()
        inventory = ''.join(path + '\0' + digest + '\n' for path, digest in entries)
        result[group] = {'files': len(entries), 'sha256': hashlib.sha256(inventory.encode()).hexdigest()}
    return result


def audit(root, manifest):
    actual = snapshot(root)
    changed = [group for group in actual if actual[group] != manifest['trees'][group]]
    if changed:
        raise ValueError('Telemetry audit required for changed ' + ', '.join(changed) +
                         ' tree. Review code and dependency changes before refreshing the manifest.')
    return actual


if __name__ == '__main__':
    try:
        manifest = json.loads(Path(__file__).with_name('telemetry-audit.json').read_text())
        result = audit(Path(sys.argv[1] if len(sys.argv) > 1 else '.'), manifest)
        print('Telemetry audit passed: ' + ', '.join('%s=%s files' % (k, v['files']) for k, v in result.items()))
    except (ValueError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
