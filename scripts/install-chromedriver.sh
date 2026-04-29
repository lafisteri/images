#!/usr/bin/env bash
set -euxo pipefail

REQUESTED_VERSION="${1:-}"
TMP="$(mktemp -d)"
cd "$TMP"

CHROME_VERSION="$(google-chrome --version | awk '{print $3}')"
CHROME_MAJOR="${CHROME_VERSION%%.*}"
CHROME_BUILD="$(echo "${CHROME_VERSION}" | cut -d. -f1-3)"

curl -fsSL https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json -o versions.json
curl -fsSL https://googlechromelabs.github.io/chrome-for-testing/latest-patch-versions-per-build-with-downloads.json -o builds.json
curl -fsSL https://googlechromelabs.github.io/chrome-for-testing/latest-versions-per-milestone-with-downloads.json -o milestones.json

lookup_exact_version() {
  local version="${1}"
  local resolved_version
  local resolved_url

  resolved_version="$(
    jq -r --arg v "${version}" '
      .versions[] | select(.version==$v) | .version
    ' versions.json
  )"
  resolved_url="$(
    jq -r --arg v "${version}" '
      .versions[] | select(.version==$v) | .downloads.chromedriver[]? | select(.platform=="linux64") | .url
    ' versions.json
  )"

  if [ -n "${resolved_version}" ] && [ -n "${resolved_url}" ]; then
    printf '%s\n%s\n' "${resolved_version}" "${resolved_url}"
    return 0
  fi

  return 1
}

lookup_build_version() {
  local build="${1}"
  local resolved_version
  local resolved_url

  resolved_version="$(jq -r --arg b "${build}" '.builds[$b].version // empty' builds.json)"
  resolved_url="$(
    jq -r --arg b "${build}" '
      .builds[$b].downloads.chromedriver[]? | select(.platform=="linux64") | .url
    ' builds.json
  )"

  if [ -n "${resolved_version}" ] && [ -n "${resolved_url}" ]; then
    printf '%s\n%s\n' "${resolved_version}" "${resolved_url}"
    return 0
  fi

  return 1
}

lookup_milestone_version() {
  local milestone="${1}"
  local resolved_version
  local resolved_url

  resolved_version="$(jq -r --arg m "${milestone}" '.milestones[$m].version // empty' milestones.json)"
  resolved_url="$(
    jq -r --arg m "${milestone}" '
      .milestones[$m].downloads.chromedriver[]? | select(.platform=="linux64") | .url
    ' milestones.json
  )"

  if [ -n "${resolved_version}" ] && [ -n "${resolved_url}" ]; then
    printf '%s\n%s\n' "${resolved_version}" "${resolved_url}"
    return 0
  fi

  return 1
}

resolve_driver() {
  local target_version="${1}"
  local target_build
  local target_major
  local result

  if result="$(lookup_exact_version "${target_version}")"; then
    printf '%s\n' "${result}"
    return 0
  fi

  target_build="$(echo "${target_version}" | cut -d. -f1-3)"
  if result="$(lookup_build_version "${target_build}")"; then
    echo "No exact Chromedriver for ${target_version}; falling back to build-compatible ${target_build}" >&2
    printf '%s\n' "${result}"
    return 0
  fi

  target_major="${target_version%%.*}"
  if result="$(lookup_milestone_version "${target_major}")"; then
    echo "No build-compatible Chromedriver for ${target_version}; falling back to milestone ${target_major}" >&2
    printf '%s\n' "${result}"
    return 0
  fi

  return 1
}

parse_resolution() {
  local resolution="${1}"
  DRIVER_VERSION="$(printf '%s\n' "${resolution}" | sed -n '1p')"
  DRIVER_URL="$(printf '%s\n' "${resolution}" | sed -n '2p')"
}

if [ -n "${REQUESTED_VERSION}" ]; then
  driver_resolution="$(resolve_driver "${REQUESTED_VERSION}")" || {
    echo "Could not resolve requested Chromedriver ${REQUESTED_VERSION}" >&2
    exit 1
  }
else
  if driver_resolution="$(lookup_build_version "${CHROME_BUILD}")"; then
    true
  elif driver_resolution="$(lookup_milestone_version "${CHROME_MAJOR}")"; then
    echo "No exact build match for installed Chrome ${CHROME_VERSION}; using milestone ${CHROME_MAJOR}" >&2
  else
    echo "Could not resolve Chromedriver for Chrome ${CHROME_VERSION}" >&2
    exit 1
  fi
fi

parse_resolution "${driver_resolution}"

test -n "${DRIVER_VERSION}"
test -n "${DRIVER_URL}"

curl -fsSLO "${DRIVER_URL}"
unzip -q chromedriver-linux64.zip
install -m 0755 chromedriver-linux64/chromedriver /usr/bin/chromedriver

cd /
rm -rf "${TMP}"
