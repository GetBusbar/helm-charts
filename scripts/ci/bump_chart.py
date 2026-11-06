#!/usr/bin/env python3
"""bump_chart.py <Chart.yaml> <candidate-app-version>
   bump_chart.py --validate <version>             exit 0 if SemVer, 2 if not
   bump_chart.py --is-newer <current> <candidate>  exit 0 if newer, 1 if not, 2 if malformed

Sets `appVersion` to <candidate-app-version> and bumps the chart's own semver
`version` (Helm requires a chart version bump whenever chart content
changes - here, the rendered appVersion changed) - but ONLY moves appVersion
FORWARD. GetBusbar/busbar's latest tagged GitHub Release can legitimately
trail the chart's appVersion (e.g. a maintainer deliberately bumped ahead of
an in-progress release, as with the 1.5.0 config-redesign chart update that
shipped before busbar 1.5.0 itself tagged); a lower-or-equal candidate is a
no-op here rather than a downgrade, so release automation can never silently
revert an intentional look-ahead bump. Patch+1 on `version` so a routine
upstream release doesn't force a manual choice between major/minor/patch; a
maintainer doing a deliberate breaking chart change still bumps `version` by
hand; this script always advances the patch component of whatever version
is on disk when appVersion moves forward.
"""
import re
import sys

MALFORMED = 2  # distinct from --is-newer's "not newer" (1)


def die(message):
    print(message, file=sys.stderr)
    sys.exit(MALFORMED)


def number(digits, s):
    try:
        return int(digits)
    except ValueError:  # beyond Python's int-from-string digit limit
        die(f"not a semantic version (numeric part too long): {s[:40]!r}...")


def parse_semver(s):
    m = re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
        r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
        r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?",
        s,
    )
    if not m:
        die(f"not a semantic version: {s!r}")
    core = tuple(number(x, s) for x in m.groups()[:3])
    prerelease = m.group(4)
    if prerelease is None:
        return core + (1, ())
    identifiers = []
    for identifier in prerelease.split("."):
        if identifier.isdigit():
            if len(identifier) > 1 and identifier.startswith("0"):
                die(f"numeric prerelease identifier has a leading zero: {s!r}")
            identifiers.append((0, number(identifier, s)))
        else:
            identifiers.append((1, identifier))
    return core + (0, tuple(identifiers))


if len(sys.argv) == 3 and sys.argv[1] == "--validate":
    parse_semver(sys.argv[2])
    sys.exit(0)
if len(sys.argv) == 4 and sys.argv[1] == "--is-newer":
    sys.exit(0 if parse_semver(sys.argv[3]) > parse_semver(sys.argv[2]) else 1)
if len(sys.argv) != 3 or sys.argv[1].startswith("--"):
    die("usage: bump_chart.py <Chart.yaml> <version> | --validate <version> | --is-newer <current> <candidate>")

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
text, image_rewrites = re.subn(
    r"(artifacthub\.io/images: \|\n\s*- name: busbar\n\s*image: getbusbar/busbar:)[^\n\"]+",
    rf"\g<1>{candidate_app_version}",
    text,
)

if image_rewrites != 1:
    print(
        f"warning: artifacthub.io/images busbar image not found in {path}; "
        "it still names the previous image",
        file=sys.stderr,
    )

with open(path, "w") as f:
    f.write(text)
print(
    f"chart version {major}.{minor}.{patch} -> {new_version}, "
    f"appVersion {current_app_version} -> {candidate_app_version}"
)
