#!/usr/bin/env bash
# Verify that a container image tag is actually PULLABLE before this repo publishes a chart that
# points at it.
#
# WHY THIS EXISTS. release-on-upstream.yml self-heals off GetBusbar/busbar's `releases/latest` on a
# daily cron. It used to bump `charts/busbar/Chart.yaml`'s appVersion the moment a newer release
# object appeared, and never checked that the matching container image had been pushed. Those are
# published by two DIFFERENT workflows (release.yml and docker.yml) that run in PARALLEL off the same
# tag push, so there is a real window in which the release object exists and the image does not. If
# the cron fires inside that window the chart publishes with `tag: ""` in values.yaml, which falls
# back to appVersion, and every user who installs it gets ImagePullBackOff. During the 1.5.3 release
# that window was open and the only reason it did not detonate was timing.
#
# The pattern being copied here is GetBusbar/homebrew-busbar's, which is safe BY CONSTRUCTION rather
# than by check: it downloads every tarball under `set -euo pipefail`, so it dies before re-pinning
# and stays fail-closed at the previous version. This script makes the chart fail-closed the same
# way: no image, no bump, chart stays where it was, and the next cron retries.
#
# Reads the OCI Distribution API directly (the same bytes `docker pull` reads), never Docker Hub's
# tags/search index, which can lag hours behind a real push.
#
# Usage:   verify-image.sh <repository> <tag> [attempts] [sleep-seconds]
# Example: verify-image.sh getbusbar/busbar 1.5.3
#
# Self-test (proves this script goes RED as well as GREEN, before its verdict is trusted anywhere):
#          verify-image.sh --selftest
set -euo pipefail

ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'

# Prints the HTTP status of a HEAD-equivalent manifest fetch. Anonymous pull token, because that is
# exactly the credential a chart user has.
manifest_status() {
  local repo="$1" tag="$2" token
  token="$(curl -fsS --max-time 30 \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')" || return 1
  curl -sS --max-time 30 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" -H "Accept: ${ACCEPT}" \
    "https://registry-1.docker.io/v2/${repo}/manifests/${tag}"
}

verify() {
  local repo="$1" tag="$2" attempts="${3:-10}" nap="${4:-30}" i status
  for (( i = 1; i <= attempts; i++ )); do
    status="$(manifest_status "$repo" "$tag" || echo 000)"
    if [ "$status" = "200" ]; then
      echo "OK: ${repo}:${tag} is pullable from registry-1.docker.io (HTTP 200, attempt ${i}/${attempts})"
      return 0
    fi
    echo "not yet: ${repo}:${tag} -> HTTP ${status} (attempt ${i}/${attempts})"
    [ "$i" -lt "$attempts" ] && sleep "$nap"
  done
  echo "FAIL: ${repo}:${tag} is NOT pullable after ${attempts} attempt(s); last status HTTP ${status}." >&2
  echo "Refusing to publish a chart whose appVersion points at an image that does not exist:" >&2
  echo "every user who installed it would get ImagePullBackOff. The chart stays at its current" >&2
  echo "version and the next scheduled run will retry, so this heals itself once the image lands." >&2
  return 1
}

if [ "${1:-}" = "--selftest" ]; then
  # A verifier nobody has watched go RED is not a verifier. Both directions, against the real
  # registry, before any caller trusts a verdict from this file.
  echo "== selftest: a tag that really exists must be accepted =="
  verify getbusbar/busbar latest 3 2 || { echo "SELFTEST FAILED: known-good tag was rejected" >&2; exit 1; }
  echo "== selftest: a tag that cannot exist must be refused (expect FAIL below) =="
  if verify getbusbar/busbar 0.0.0-does-not-exist 2 1; then
    echo "SELFTEST FAILED: a nonexistent tag was accepted. This script would wave through exactly" >&2
    echo "the broken-chart publish it exists to prevent." >&2
    exit 1
  fi
  echo "== selftest: an unknown repository must be refused (expect FAIL below) =="
  if verify getbusbar/no-such-image-at-all 1.0.0 1 1; then
    echo "SELFTEST FAILED: an unknown repository was accepted." >&2
    exit 1
  fi
  echo
  echo "SELFTEST PASSED: accepts a real tag, refuses a missing tag, refuses a missing repository."
  exit 0
fi

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <repository> <tag> [attempts] [sleep-seconds]  |  $0 --selftest" >&2
  exit 2
fi
verify "$@"
