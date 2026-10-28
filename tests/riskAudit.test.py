import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('risk',ROOT/'releases/risk-audit.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
class RiskAudit(unittest.TestCase):
    def setUp(self):
        (ROOT/'.tools/tmp').mkdir(parents=True,exist_ok=True)
        self.tmp=tempfile.TemporaryDirectory(dir=ROOT/'.tools/tmp')
        self.root=Path(self.tmp.name)
        self.file=self.root/'main.js'
        self.file.write_text('console.log("local diagnostics"); fetch("https://service.example/api");')
        self.policy={'roots':['.'],'initialized':True,'files':r.collect(self.root,{'roots':['.']})}
    def tearDown(self):self.tmp.cleanup()
    def test_reviewed_patch_reference_is_info_and_new_urls_still_fail(self):
        self.file.unlink()
        patch = self.root/'fix.patch'
        patch.write_text('+// Reference: https://github.com/example/project/issues/123\n')
        policy = {'roots':['.'], 'initialized':True, 'files':r.collect(self.root, {'roots':['.']})}
        policy['files']['fix.patch']['reason'] = 'Issue reference in a comment; no network call.'
        with contextlib.redirect_stdout(io.StringIO()) as output:
            r.inspect(self.root, policy)
        self.assertIn('known reference', output.getvalue())
        self.assertIn('Known baseline URL matches: 1', output.getvalue())
        patch.write_text(patch.read_text()+'+fetch("https://new.example/report");\n')
        with self.assertRaisesRegex(ValueError, 'new URL'): r.inspect(self.root, policy)

    def test_ordinary_hash_changes_and_local_logging_do_not_block(self):
        self.file.write_text('console.log("more local diagnostics"); fetch("https://service.example/api");')
        r.inspect(self.root,self.policy)
    def test_new_urls_and_keywords_stop_with_evidence(self):
        for text,expected in [('fetch("https://new.example/upload?secret=redacted")','new URL'),('new TelemetryClient()','suspicious keyword')]:
            self.file.write_text(text)
            with self.assertRaisesRegex(ValueError,expected) as result:r.inspect(self.root,self.policy)
            self.assertNotIn('secret=',str(result.exception))
    def test_version_url_allowance_is_limited_to_exact_file_and_host(self):
        self.policy['allowUrlPatternsByFile'] = {'main.js': [r'https://nodejs\.org/dist/v26\.\d+\.\d+/']}
        self.file.write_text('fetch("https://nodejs.org/dist/v26.100.0/")')
        r.inspect(self.root, self.policy)
        (self.root/'other.js').write_text(self.file.read_text())
        with self.assertRaisesRegex(ValueError, 'other.js'): r.inspect(self.root, self.policy)
        (self.root/'other.js').unlink()
        for url in ['https://evil.example/dist/v26.100.0/', 'https://nodejs.org/dist/v26.100.0/?report=1',
                    'https://nodejs.org/dist/v27.0.0/']:
            self.file.write_text('fetch("'+url+'")')
            with self.assertRaisesRegex(ValueError, 'new URL'): r.inspect(self.root, self.policy)

    def test_upstream_sbom_dependency_references_follow_version_bumps(self):
        # Upstream cyclonedx.sbom.json names each Go dependency version with a
        # deps.dev license-evidence URL and a pkg.go.dev page. They are metadata,
        # not requests the tools make, and change with every dependency bump
        # (mongo-driver/v2 2.8.2 -> 2.9.1 stopped a release).
        upstream = json.loads((ROOT/'releases/upstream-risk-baseline.json').read_text())
        self.policy['allowUrlPatternsByFile'] = upstream['allowUrlPatternsByFile']
        sbom = self.root/'cyclonedx.sbom.json'
        for url in ['https://api.deps.dev/v3/systems/go/packages/go.mongodb.org%2Fmongo-driver%2Fv2/versions/v2.9.1',
                    'https://pkg.go.dev/go.mongodb.org/mongo-driver/v2@v2.9.1',
                    'https://pkg.go.dev/None/std@go1.27.1',
                    # Upstream 3c3f94948f0f's SBOM cites licenses through the
                    # pkg.go.dev v1 package API for the modules it bumped.
                    'https://pkg.go.dev/v1/package/github.com/deckarep/golang-set/v3?licenses=true&version=v3.0.0',
                    'https://pkg.go.dev/v1/package/golang.org/x/net?licenses=true&version=v0.61.0']:
            sbom.write_text(json.dumps({'url': url}))
            r.inspect(self.root, self.policy)
        # The same reference anywhere else is still a new URL.
        sbom.unlink()
        self.file.write_text('fetch("https://api.deps.dev/v3/systems/go/packages/x/versions/v1.0.0")')
        with self.assertRaisesRegex(ValueError, 'main.js: new URL'): r.inspect(self.root, self.policy)
        self.file.write_text('console.log("local diagnostics");')
        # Other hosts, other deps.dev endpoints and query strings stay blocked in the SBOM.
        for url in ['https://evil.example/v3/systems/go/packages/x/versions/v1.0.0',
                    'https://api.deps.dev/v3/query?hash=abc',
                    'https://api.deps.dev/v3/systems/go/packages/x/versions/v1.0.0?report=1',
                    'https://pkg.go.dev/x@v1.0.0?report=1',
                    'https://pkg.go.dev/search?q=telemetry',
                    'https://pkg.go.dev/v1/package/x?licenses=true&version=v1.0.0&report=1',
                    'https://pkg.go.dev/v1/package/x?report=1&licenses=true&version=v1.0.0',
                    'https://pkg.go.dev/v1/search?licenses=true&version=v1.0.0',
                    'https://evil.example/v1/package/x?licenses=true&version=v1.0.0']:
            sbom.write_text(json.dumps({'url': url}))
            with self.assertRaisesRegex(ValueError, 'cyclonedx.sbom.json: new URL'): r.inspect(self.root, self.policy)

    def test_each_releases_ssdlc_sbom_is_allowed_by_its_glob(self):
        # Upstream adds ssdlc/<version>.bom.json with every release; 100.20.0
        # stopped a build on its pkg.go.dev license pages and component repos,
        # because the allowance was keyed by one exact file name.
        upstream = json.loads((ROOT/'releases/upstream-risk-baseline.json').read_text())
        self.policy['allowUrlPatternsByFile'] = upstream['allowUrlPatternsByFile']
        (self.root/'ssdlc').mkdir()
        bom = self.root/'ssdlc/100.21.0.bom.json'
        for url in ['https://pkg.go.dev/v1/package/golang.org/x/net?licenses=true&version=v0.62.0',
                    'https://github.com/Azure/azure-sdk-for-go/sdk/azcore',
                    'https://gopkg.in/yaml.v2']:
            bom.write_text(json.dumps({'url': url}))
            r.inspect(self.root, self.policy)
        # Negative: other hosts, and query strings on a repo URL, in the SBOM.
        for url in ['https://evil.example/v1/package/x?licenses=true&version=v1.0.0',
                    'https://github.com/x/y?report=1',
                    'https://pkg.go.dev/search?q=telemetry']:
            bom.write_text(json.dumps({'url': url}))
            with self.assertRaisesRegex(ValueError, 'ssdlc/100.21.0.bom.json: new URL'): r.inspect(self.root, self.policy)
        # Negative: the glob is for SBOMs only - a .sarif.json beside them, or
        # the same reference in source, is still a new URL.
        bom.unlink()
        (self.root/'ssdlc/100.21.0.sarif.json').write_text(json.dumps({'url': 'https://github.com/x/y'}))
        with self.assertRaisesRegex(ValueError, 'sarif.json: new URL'): r.inspect(self.root, self.policy)
        (self.root/'ssdlc/100.21.0.sarif.json').unlink()
        self.file.write_text('fetch("https://gopkg.in/yaml.v2")')
        with self.assertRaisesRegex(ValueError, 'main.js: new URL'): r.inspect(self.root, self.policy)

    def test_known_bad_hash_always_blocks_source_or_binary(self):
        self.policy['denyHashes']=[hashlib.sha256(self.file.read_bytes()).hexdigest()]
        with self.assertRaisesRegex(ValueError,'hash'):r.inspect(self.root,self.policy)
        with self.assertRaisesRegex(ValueError,'hash'):r.artifact(self.file,self.policy)
    def test_baselined_keyword_is_not_blanket_for_new_occurrences(self):
        self.file.write_text('/* TelemetryClient compatibility */')
        self.policy['files']=r.collect(self.root,self.policy)
        r.inspect(self.root,self.policy)
        self.file.write_text('/* TelemetryClient compatibility */ new TelemetryClient()')
        with self.assertRaisesRegex(ValueError,'keyword'):r.inspect(self.root,self.policy)
    def test_new_files_are_scanned_and_test_fixtures_are_not_runtime(self):
        (self.root/'tests').mkdir();(self.root/'tests/fixture.js').write_text('new TelemetryClient()')
        r.inspect(self.root,self.policy)
        (self.root/'new.js').write_text('new TelemetryClient()')
        with self.assertRaisesRegex(ValueError,'new.js'):r.inspect(self.root,self.policy)
    def test_artifact_urls_and_telemetry_signatures(self):
        r.artifact(self.file,{'artifactUrls':['https://service.example/api']})
        with self.assertRaisesRegex(ValueError,'New URL'):r.artifact(self.file,{'artifactUrls':[]})
        self.file.write_text('mongosh-telemetry.mongodb.com')
        with self.assertRaisesRegex(ValueError,'Telemetry indicator'):r.artifact(self.file,{})
    def test_cli_exit_code_blocks_findings_but_not_hash_drift(self):
        policy=self.root/'policy.json';policy.write_text(json.dumps(self.policy))
        self.policy['exclude']=['policy.json'];policy.write_text(json.dumps(self.policy))
        for text,code in [('console.log("local logging");',0),('fetch("https://new.example/report")',1)]:
            self.file.write_text(text)
            result=subprocess.run(['python3','-B',str(ROOT/'releases/risk-audit.py'),'--source',str(self.root),'--policy',str(policy)],capture_output=True,text=True)
            self.assertEqual(result.returncode,code,result.stdout+result.stderr)
if __name__=='__main__':unittest.main()
