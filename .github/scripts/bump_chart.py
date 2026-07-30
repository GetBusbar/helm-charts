#!/usr/bin/env python3
"""bump_chart.py <Chart.yaml> <new-app-version>

Sets `appVersion` to <new-app-version> and bumps the chart's own semver
`version` (Helm requires a chart version bump whenever chart content
changes - here, the rendered appVersion changed). Bump policy: patch+1,
so a routine upstream release doesn't force a manual choice between
major/minor/patch; a maintainer doing a deliberate breaking chart change
still bumps `version` by hand in that same PR/commit and this script just
no-ops (it never lowers or otherwise second-guesses an already-bumped
version - it only advances the patch component of whatever is on disk).
"""
import re
import sys

path, new_app_version = sys.argv[1], sys.argv[2]
with open(path) as f:
    text = f.read()

m = re.search(r'^version:\s*"?([0-9]+)\.([0-9]+)\.([0-9]+)"?\s*$', text, re.MULTILINE)
if not m:
    sys.exit(f"could not find a semver 'version:' line in {path}")
major, minor, patch = (int(x) for x in m.groups())
new_version = f"{major}.{minor}.{patch + 1}"

text = text[: m.start()] + f"version: {new_version}" + text[m.end() :]
text = re.sub(
    r'^appVersion:\s*"[^"]*"\s*$',
    f'appVersion: "{new_app_version}"',
    text,
    count=1,
    flags=re.MULTILINE,
)
text = re.sub(
    r"(artifacthub\.io/images: \|\n\s*- name: busbar\n\s*image: getbusbar/busbar:)[^\n\"]+",
    rf"\g<1>{new_app_version}",
    text,
)

with open(path, "w") as f:
    f.write(text)
print(f"chart version {major}.{minor}.{patch} -> {new_version}, appVersion -> {new_app_version}")
