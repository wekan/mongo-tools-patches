#!/usr/bin/env python3
"""The tools are built with no MPTCP listener by default.

CVE-2026-98432 is a Linux kernel use-after-free in IPv4 TCP connection
handling, shown to give remote code execution through an MPTCP listener
(golang-announce, 2026-10), and since Go 1.24 every Linux listen socket of a
Go program is MPTCP unless the program says otherwise. The tools are clients
and listen on nothing today; `godebug multipathtcp=0` in the reviewed go.mod -
which update-dependencies.sh copies over upstream's - keeps any listener
upstream adds off by default, and update-dependencies.sh refuses to build
without it. Run: python3 -B tests/mptcpOff.test.py
"""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / 'releases/update-dependencies.sh'


class MptcpOff(unittest.TestCase):
    def test_reviewed_go_mod_turns_it_off(self):
        go_mod = (ROOT / 'releases/reviewed-go/go.mod').read_text(encoding='utf-8')
        self.assertRegex(go_mod, r'(?m)^module github\.com/mongodb/mongo-tools$')
        self.assertRegex(go_mod, r'(?m)^godebug multipathtcp=0$')

    def test_the_build_uses_that_go_mod_and_checks_it(self):
        text = SCRIPT.read_text(encoding='utf-8')
        copy = text.index('cp "$root/releases/reviewed-go/go.mod" go.mod')
        check = text.index("grep -qx 'godebug multipathtcp=0' go.mod")
        vendor = text.index('go mod vendor')
        self.assertLess(copy, check)
        self.assertLess(check, vendor, 'checked before anything is built from it')
        self.assertIn('keeping the reviewed go and godebug directives', text)

    def _run_until_vendor(self, go_mod_text):
        # The script up to its vendor step, against a go.mod of our own, with
        # a go command that only records that it was reached.
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as tmp:
            tmp = Path(tmp)
            (tmp / 'releases/reviewed-go').mkdir(parents=True)
            (tmp / 'releases/reviewed-go/go.mod').write_text(go_mod_text, encoding='utf-8')
            (tmp / 'releases/reviewed-go/go.sum').write_text('', encoding='utf-8')
            script = SCRIPT.read_text(encoding='utf-8')
            head = script[:script.index('if ! GOFLAGS=-mod=readonly go mod vendor')] + 'echo REACHED-VENDOR\n'
            (tmp / 'releases/update-dependencies.sh').write_text(head, encoding='utf-8')
            work = tmp / 'work'
            work.mkdir()
            env = {**os.environ, 'PATH': '/usr/bin:/bin'}
            return subprocess.run(['bash', str(tmp / 'releases/update-dependencies.sh')], cwd=work, env=env,
                                  capture_output=True, text=True, check=False)

    def test_build_goes_on_with_the_setting(self):
        result = self._run_until_vendor('module github.com/mongodb/mongo-tools\n\ngo 1.27.2\n\ngodebug multipathtcp=0\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('REACHED-VENDOR', result.stdout)

    def test_negative_build_stops_without_it(self):
        result = self._run_until_vendor('module github.com/mongodb/mongo-tools\n\ngo 1.27.2\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('REACHED-VENDOR', result.stdout)
        self.assertIn("lost 'godebug multipathtcp=0'", result.stderr)
        # A comment that mentions it is not the setting.
        result = self._run_until_vendor('module m\n\ngo 1.27.2\n\n// godebug multipathtcp=0\n')
        self.assertNotEqual(result.returncode, 0)

    def test_negative_nothing_turns_it_back_on(self):
        found = []
        for path in ROOT.rglob('*'):
            if '.git' in path.parts or not path.is_file() or path.suffix not in {'.sh', '.yml', '.yaml', '.mod', '.patch', '.go', '.py'}:
                continue
            if path == Path(__file__).resolve():
                continue
            for n, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
                if re.search(r'multipathtcp=1|SetMultipathTCP\(\s*true', line) and not re.match(r'\s*(#|//)', line):
                    found.append(f'{path.relative_to(ROOT)}:{n}')
        self.assertEqual(found, [])


if __name__ == '__main__':
    unittest.main()
