import os
import pathlib
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleaseWorkflowTest(unittest.TestCase):
    def run_schedule(self, tag=None):
        workflow = (ROOT / '.github/workflows/release-on-upstream.yml').read_text()
        blocks = re.findall(r'        run: \|\n((?:          [^\n]*\n|\n)+)', workflow)
        script = next(block for block in blocks if 'CHART=charts/busbar/Chart.yaml' in block)
        script = '\n'.join(line[10:] for line in script.splitlines())
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            (work / 'charts/busbar').mkdir(parents=True)
            (work / '.github/scripts').mkdir(parents=True)
            shutil.copy2(ROOT / 'charts/busbar/Chart.yaml', work / 'charts/busbar/Chart.yaml')
            shutil.copy2(ROOT / '.github/scripts/bump_chart.py', work / '.github/scripts/bump_chart.py')
            gh_body = 'exit 23' if tag is None else "printf '%s\\n' " + shlex.quote(tag)
            (work / 'gh').write_text('#!/bin/sh\n' + gh_body + '\n')
            (work / 'gh').chmod(0o755)
            output = work / 'output'
            env = dict(os.environ, EVENT_NAME='schedule', DISPATCH_VERSION='', GITHUB_OUTPUT=str(output), PATH=f'{work}:{os.environ["PATH"]}')
            result = subprocess.run(['bash', '-c', script], cwd=work, env=env, capture_output=True, text=True)
            return result, output.read_text() if output.exists() else None

    def test_schedule_surfaces_upstream_api_failure(self):
        result, output = self.run_schedule()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIsNone(output, 'API failure must not emit a successful no-op decision')

    def test_schedule_rejects_malformed_upstream_version(self):
        result, output = self.run_schedule('v1.7.0garbage')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIsNone(output)

    def test_schedule_accepts_older_version_as_noop(self):
        result, output = self.run_schedule('v1.5.5')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('act=no', output)


if __name__ == '__main__':
    unittest.main()
