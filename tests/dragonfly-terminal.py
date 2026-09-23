#!/usr/bin/env python3
"""Exercise the vendor patch and Go's file selection without network access."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TerminalPatch(unittest.TestCase):
    @unittest.skipUnless(shutil.which('go'), 'Go is required for build-constraint checks')
    def test_patch_selects_exactly_one_platform_implementation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            vendor = root / 'vendor/github.com/nsf/termbox-go'
            vendor.mkdir(parents=True)
            constraints = {
                'bsd': 'darwin || freebsd || openbsd || netbsd',
                'nonbsd': '!darwin && !freebsd && !netbsd && !openbsd && !windows',
            }
            for suffix, constraint in constraints.items():
                (vendor / ('syscalls_' + suffix + '.go')).write_text(
                    '//go:build ' + constraint + '\n\npackage termbox\n\nconst selected = 1\n')
            patch = str(ROOT / 'dist/vendor/dragonfly-terminal.patch')
            subprocess.run(['git', 'apply', '--check', patch], cwd=root, check=True)
            subprocess.run(['git', 'apply', patch], cwd=root, check=True)
            # Reject a stale/already-applied patch rather than silently skipping it.
            again = subprocess.run(['git', 'apply', '--check', patch], cwd=root, capture_output=True)
            self.assertNotEqual(again.returncode, 0)
            (vendor / 'go.mod').write_text('module terminalfixture\n\ngo 1.20\n')
            env = dict(os.environ, GOTELEMETRY='off', GOTOOLCHAIN='local', GOPROXY='off',
                       GOSUMDB='off', CGO_ENABLED='0', GOARCH='amd64', GOFLAGS='')
            for target in ['dragonfly', 'darwin', 'freebsd', 'openbsd', 'netbsd', 'linux']:
                with self.subTest(target=target):
                    env['GOOS'] = target
                    info = json.loads(subprocess.check_output(
                        ['go', 'list', '-json', '.'], cwd=vendor, env=env, text=True))
                    expected = 'nonbsd' if target == 'linux' else 'bsd'
                    self.assertEqual(info['GoFiles'], ['syscalls_' + expected + '.go'])
                    subprocess.run(['go', 'build', '.'], cwd=vendor, env=env, check=True)


if __name__ == '__main__':
    unittest.main()
