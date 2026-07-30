#!/usr/bin/env python3
"""bump_chart.py <Chart.yaml> <candidate-app-version>

Sets `appVersion` to <candidate-app-version> and bumps the chart's own semver
`version` (Helm requires a chart version bump whenever chart content
changes - here, the rendered appVersion changed) - but ONLY moves appVersion
FORWARD. GetBusbar/busbar's latest tagged GitHub Release can legitimately
trail the chart's appVersion (e.g. a maintainer deliberately bumped ahead of
an in-progress release, as with the 1.5.0 config-redesign chart update that
shipped before busbar 1.5.0 itself tagged); a lower-or-equal candidate is a
no-op here rather than a downgrade, so the daily poll can never silently
revert an intentional look-ahead bump. Patch+1 on `version` so a routine
upstream release doesn't force a manual choice between major/minor/patch; a
maintainer doing a deliberate breaking chart change still bumps `version` by
hand in that same PR/commit and this script just no-ops on version (it only
advances the patch component of whatever is on disk).
"""
import re
import sys


def parse_semver(s):
    m = re.match(r"^([0-9]+)\.([0-9]+)\.([0-9]+)", s)
    if not m:
        sys.exit(f"not a semver-ish version: {s!r}")
    return tuple(int(x) for x in m.groups())


path, candidate_app_version = sys.argv[1], sys.argv[2]
with open(path) as f:
    text = f.read()

m = re.search(r'^version:\s*"?([0-9]+)\.([0-9]+)\.([0-9]+)"?\s*$', text, re.MULTILINE)
if not m:
    sys.exit(f"could not find a semver 'version:' line in {path}")
major, minor, patch = (int(x) for x in m.groups())

am = re.search(r'^appVersion:\s*"([^"]*)"\s*$', text, re.MULTILINE)
if not am:
    sys.exit(f"could not find an 'appVersion:' line in {path}")
current_app_version = am.group(1)

if parse_semver(candidate_app_version) <= parse_semver(current_app_version):
    print(
        f"appVersion {current_app_version} already >= candidate {candidate_app_version} "
        "(chart is ahead of the latest tagged release) - no-op"
    )
    sys.exit(0)

new_version = f"{major}.{minor}.{patch + 1}"
text = text[: m.start()] + f"version: {new_version}" + text[m.end() :]
text = re.sub(
    r'^appVersion:\s*"[^"]*"\s*$',
    f'appVersion: "{candidate_app_version}"',
    text,
    count=1,
    flags=re.MULTILINE,
)
text = re.sub(
    r"(artifacthub\.io/images: \|\n\s*- name: busbar\n\s*image: getbusbar/busbar:)[^\n\"]+",
    rf"\g<1>{candidate_app_version}",
    text,
)

with open(path, "w") as f:
    f.write(text)
print(
    f"chart version {major}.{minor}.{patch} -> {new_version}, "
    f"appVersion {current_app_version} -> {candidate_app_version}"
)
