import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'scripts/ci/bump_chart.py'


def run(*arguments):
    return subprocess.run([sys.executable, str(SCRIPT), *arguments], capture_output=True, text=True)


class BumpChartErrorTest(unittest.TestCase):
    def bump_file(self, content, candidate='1.7.0'):
        with tempfile.TemporaryDirectory() as directory:
            chart = pathlib.Path(directory) / 'Chart.yaml'
            chart.write_text(content)
            result = run(str(chart), candidate)
            return result, chart.read_text()

    def test_wrong_argument_count_prints_usage(self):
        for arguments in [(), ('a', 'b', 'c', 'd'), ('--is-newer', '1.0.0')]:
            with self.subTest(arguments=arguments):
                result = run(*arguments)
                # 2, not 1: for --is-newer, 1 means "not newer".
                self.assertEqual(result.returncode, 2)
                self.assertIn('usage: bump_chart.py', result.stderr)

    def test_oversized_numeric_component_is_malformed_not_a_crash(self):
        huge = '1.6.' + '9' * 5000
        for arguments in [('--is-newer', '1.6.0', huge), ('--validate', huge), ('--validate', '1.6.0-' + '9' * 5000)]:
            with self.subTest(arguments=arguments[0]):
                result = run(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('Traceback', result.stderr)

    def test_multi_digit_components_compare_numerically(self):
        for current, candidate, expected in [('1.9.0', '1.10.0', 0), ('1.10.0', '1.9.0', 1), ('9.0.0', '10.0.0', 0), ('1.6.0-rc.9', '1.6.0-rc.10', 0)]:
            with self.subTest(current=current, candidate=candidate):
                self.assertEqual(run('--is-newer', current, candidate).returncode, expected)

    def test_missing_version_line_is_refused_without_writing(self):
        before = 'appVersion: "1.6.0"\n'
        result, after = self.bump_file(before)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not find a semver 'version:' line", result.stderr)
        self.assertEqual(after, before)

    def test_unquoted_app_version_is_refused_without_writing(self):
        before = 'version: 0.3.0\nappVersion: 1.6.0\n'
        result, after = self.bump_file(before)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not find an 'appVersion:' line", result.stderr)
        self.assertEqual(after, before)

    def test_only_top_level_version_is_bumped(self):
        before = 'apiVersion: v2\nversion: 1.2.9\nappVersion: "1.6.0"\ndependencies:\n  - name: x\n    version: 9.9.9\n'
        result, after = self.bump_file(before)
        self.assertEqual(result.returncode, 0)
        self.assertIn('\nversion: 1.2.10\n', after)
        self.assertIn('    version: 9.9.9\n', after)
        self.assertIn('apiVersion: v2\n', after)


if __name__ == '__main__':
    unittest.main()
