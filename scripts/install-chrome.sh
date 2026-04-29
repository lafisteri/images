#!/usr/bin/env bash
set -euo pipefail

CHROME_VERSION="${CHROME_VERSION:?CHROME_VERSION is required}"
CHROME_APT_PATTERN="${CHROME_APT_PATTERN:-}"

configure_chrome_install() {
  local launcher
  local sandbox

  for launcher in \
    /opt/google/chrome/google-chrome \
    /opt/google/chrome/google-chrome-stable \
    /opt/google/chrome-beta/google-chrome-beta \
    /opt/google/chrome-unstable/google-chrome-unstable; do
    [[ -f "${launcher}" ]] || continue

    if ! grep -q -- '--no-sandbox' "${launcher}"; then
      # shellcheck disable=SC2016
      sed -i 's@exec -a "$0" "$HERE/chrome"@& --no-sandbox --disable-gpu --disable-dev-shm-usage@' "${launcher}"
    fi
  done

  for sandbox in /opt/google/*/chrome-sandbox; do
    [[ -e "${sandbox}" ]] || continue
    chown root:root "${sandbox}"
    chmod 4755 "${sandbox}"
  done
}

curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /usr/share/keyrings/google-linux.gpg

echo "deb [signed-by=/usr/share/keyrings/google-linux.gpg arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" \
  > /etc/apt/sources.list.d/google-chrome.list

apt-get update

RESOLVED=""
if [[ -n "${CHROME_APT_PATTERN}" ]]; then
  RESOLVED="$(apt-cache madison google-chrome-stable \
    | awk '{print $3}' \
    | grep -E "^${CHROME_APT_PATTERN}$" \
    | head -n1 || true)"
fi

if [[ -n "${RESOLVED}" ]]; then
  echo "Using APT version google-chrome-stable=${RESOLVED}"
  apt-get install -y --no-install-recommends "google-chrome-stable=${RESOLVED}"
  configure_chrome_install
  google-chrome --version
  exit 0
fi

echo "No APT match for pattern '${CHROME_APT_PATTERN}', trying .deb for ${CHROME_VERSION}"

DEB_PATH="/tmp/google-chrome-stable_${CHROME_VERSION}_amd64.deb"

if ! curl -fSL "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${CHROME_VERSION}_amd64.deb" \
  -o "${DEB_PATH}"; then
  echo "Failed to download Chrome deb for version ${CHROME_VERSION}"
  exit 1
fi

if ! apt-get install -y --no-install-recommends "${DEB_PATH}"; then
  echo "Failed to install Chrome from ${DEB_PATH}"
  exit 1
fi

configure_chrome_install
google-chrome --version

rm -f "${DEB_PATH}"
