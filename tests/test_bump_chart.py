import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / '.github/scripts/bump_chart.py'


class BumpChartTest(unittest.TestCase):
    def bump(self, current, candidate):
        with tempfile.TemporaryDirectory() as directory:
            chart = pathlib.Path(directory) / 'Chart.yaml'
            before = f'version: 0.3.0\nappVersion: "{current}"\n'
            chart.write_text(before)
            result = subprocess.run([sys.executable, str(SCRIPT), str(chart), candidate], capture_output=True, text=True)
            return result.returncode, before, chart.read_text()

    def test_workflow_comparator_and_validation(self):
        for arguments, expected in [
            (["--is-newer", "1.6.0-rc.1", "1.6.0"], 0),
            (["--is-newer", "1.6.0", "1.6.0-rc.1"], 1),
            (["--validate", "1.6.0"], 0),
            (["--validate", "1.6.0\nact=yes"], 1),
        ]:
            with self.subTest(arguments=arguments):
                result = subprocess.run([sys.executable, str(SCRIPT), *arguments], capture_output=True)
                self.assertEqual(result.returncode, expected)

    def test_release_advances_prerelease(self):
        status, _, after = self.bump('1.6.0-rc.1', '1.6.0')
        self.assertEqual(status, 0)
        self.assertIn('appVersion: "1.6.0"', after)
        self.assertIn('version: 0.3.1', after)

    def test_prerelease_numbers_compare_numerically(self):
        status, _, after = self.bump('1.6.0-rc.9', '1.6.0-rc.10')
        self.assertEqual(status, 0)
        self.assertIn('appVersion: "1.6.0-rc.10"', after)

    def test_downgrades_and_metadata_are_noops(self):
        for current, candidate in [('1.6.0', '1.6.0-rc.1'), ('1.6.0+one', '1.6.0+two'), ('1.6.1', '1.6.0')]:
            with self.subTest(candidate=candidate):
                status, before, after = self.bump(current, candidate)
                self.assertEqual(status, 0)
                self.assertEqual(before, after)

    def test_rejects_malformed_versions_without_writing(self):
        for candidate in ['1.7.0garbage', '1.7.0\nmalicious: true', '01.7.0', '1.7.0-01']:
            with self.subTest(candidate=candidate):
                status, before, after = self.bump('1.6.0', candidate)
                self.assertNotEqual(status, 0)
                self.assertEqual(before, after)


if __name__ == '__main__':
    unittest.main()
