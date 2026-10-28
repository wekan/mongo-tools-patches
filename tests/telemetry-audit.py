#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import re
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audit', ROOT / 'releases/audit-telemetry.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class TelemetryAudit(unittest.TestCase):
    def test_source_and_vendor_changes_require_review(self):
        with tempfile.TemporaryDirectory(prefix='mongo-tools-audit-') as tmp:
            root = Path(tmp)
            (root / 'vendor/example').mkdir(parents=True)
            for name in ('go.mod', 'go.sum', 'vendor/modules.txt'):
                (root / name).write_text('fixture\n')
            original = root / 'main.go'
            original.write_text('package main\n')
            manifest = {'trees': audit.snapshot(root)}
            audit.audit(root, manifest)
            for name in ('other.go', 'vendor/example/new.go', 'new-embedded-data'):
                added = root / name
                added.write_text('new code without a telemetry keyword')
                with self.assertRaisesRegex(ValueError, 'fingerprints changed'):
                    audit.audit(root, manifest)
                added.unlink()
            for name in ('main.go', 'go.sum', 'vendor/modules.txt'):
                file = root / name
                content = file.read_bytes()
                file.write_bytes(content + b'changed')
                with self.assertRaises(ValueError):
                    audit.audit(root, manifest)
                file.unlink()
                with self.assertRaises(ValueError):
                    audit.audit(root, manifest)
                file.write_bytes(content)
            (root / 'alias.go').symlink_to(original)
            with self.assertRaisesRegex(ValueError, 'symlink'):
                audit.audit(root, manifest)

    def test_checksum_application_and_removal(self):
        patch = ROOT / 'dist/vendor/remove-sdk-telemetry.patch'
        expected = patch.with_suffix('.sha256sum').read_text().split()[0]
        self.assertEqual(hashlib.sha256(patch.read_bytes()).hexdigest(), expected)
        with tempfile.TemporaryDirectory(prefix='mongo-tools-patch-') as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / 'tests/fixtures/vendor-telemetry', root, dirs_exist_ok=True)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            subprocess.run(['git', 'apply', '--check', str(patch)], cwd=root, check=True)
            subprocess.run(['git', 'apply', str(patch)], cwd=root, check=True)
            azure = (root / 'vendor/github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime/policy_telemetry.go').read_text()
            self.assertNotIn('HeaderUserAgent', azure)
            self.assertNotIn('platformInfo', azure)
            self.assertIn('return req.Next()', azure)
            aws = (root / 'vendor/github.com/aws/aws-sdk-go-v2/aws/middleware/user_agent.go').read_text()
            self.assertNotIn('os.Getenv(', aws)
            self.assertNotIn('runtime.Version()', aws)
            self.assertNotIn('u.features[', aws)
            self.assertNotIn('Header[', aws)
            self.assertIn('return next.HandleBuild(ctx, in)', aws)
            for file in (root / 'vendor/github.com/AzureAD').rglob('*.go'):
                self.assertNotRegex(file.read_text(), r'Header[s]?\.Set\("x-client-')

    def test_incompatible_dependency_fails_without_partial_changes(self):
        with tempfile.TemporaryDirectory(prefix='mongo-tools-drift-') as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / 'tests/fixtures/vendor-telemetry', root, dirs_exist_ok=True)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            file = root / 'vendor/github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime/policy_telemetry.go'
            file.write_text(file.read_text().replace('runtime.Version()', 'newFingerprint()'))
            before = {p: p.read_bytes() for p in root.rglob('*.go')}
            result = subprocess.run(['git', 'apply', str(ROOT / 'dist/vendor/remove-sdk-telemetry.patch')], cwd=root, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(before, {p: p.read_bytes() for p in root.rglob('*.go')})

    def test_build_and_dependency_refresh_enforce_audit(self):
        update = (ROOT / 'releases/update-dependencies.sh').read_text()
        self.assertLess(update.index('go mod vendor'), update.index('apply-vendor-patches.sh'))
        build = (ROOT / '.github/scripts/build-tools.sh').read_text()
        self.assertIn('audit-telemetry.py" . || exit 1', build)
        self.assertLess(build.index('audit-telemetry.py'), build.index('while read -r name'))
        self.assertIn('go telemetry off', update)
        self.assertIn('go telemetry off', build)

    def test_every_go_command_runs_with_go_telemetry_off(self):
        # GOTELEMETRY=off in the environment does not turn off the Go
        # toolchain's own telemetry (`go env GOTELEMETRY` still says local);
        # only the mode file `go telemetry off` writes does. So every script
        # and workflow that runs go also runs that.
        files = [f for f in ROOT.rglob('*') if f.is_file() and f.suffix in ('.sh', '.py', '.yml')
                 and not {'.git', 'vendor', 'fixtures'} & set(f.relative_to(ROOT).parts)
                 and f != Path(__file__).resolve()]
        runs = [f for f in files if runs_go(f.read_text(errors='replace'))]
        self.assertIn(ROOT / '.github/scripts/build-tools.sh', runs)
        self.assertEqual([str(f.relative_to(ROOT)) for f in runs if not turns_off(f.read_text())], [])

    def test_the_environment_variable_alone_is_refused(self):
        # Negative: the no-op this replaced.
        self.assertTrue(runs_go('export GOTELEMETRY=off\ngo build ./x\n'))
        self.assertFalse(turns_off('export GOTELEMETRY=off\ngo build ./x\n'))
        self.assertTrue(turns_off("subprocess.run(['go', 'telemetry', 'off'])"))
        self.assertFalse(runs_go('# `go build ./mongodump/main` works\n'))


GO_COMMAND = re.compile(r"^[^#\n]*(?:(?:^|[ ;&(|])go (?:build|test|run|install|mod|vet|generate|get|list)\b"
                        r"|\['go', '(?:build|test|run|install|mod|vet|generate|get|list)'|actions/setup-go)", re.M)


def runs_go(text):
    return bool(GO_COMMAND.search(text))


def turns_off(text):
    return 'go telemetry off' in text or "['go', 'telemetry', 'off']" in text


if __name__ == '__main__':
    unittest.main()
