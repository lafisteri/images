#!/usr/bin/env bash
set -euo pipefail

ENABLE_VNC_VALUE="${ENABLE_VNC:-0}"
VERBOSE="${VERBOSE:-}"
DRIVER_ARGS="${DRIVER_ARGS:-}"
PULSE_COOKIE_B64="${PULSE_COOKIE_B64:-}"

pids=()

cleanup() {
  for pid in "${pids[@]}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  wait || true
}

start_background() {
  "$@" &
  pids+=("$!")
}

wait_for_display() {
  until wmctrl -m >/dev/null 2>&1; do
    sleep 0.1
  done
}

import_root_cas() {
  local nssdb="$HOME/.pki/nssdb"
  local cert_name
  local env_name
  local passphrase="${PRIVATE_KEY_PASS:-}"
  local tmp_dir
  local pem_file
  local p12_file

  if ! env | grep -q '^ROOT_CA_'; then
    return
  fi

  mkdir -p "$nssdb"
  if [ ! -f "$nssdb/cert9.db" ]; then
    certutil -N --empty-password -d "sql:$nssdb"
  fi

  tmp_dir="$(mktemp -d)"

  while IFS= read -r env_name; do
    cert_name="${env_name#ROOT_CA_}"
    pem_file="${tmp_dir}/${cert_name}.pem"
    p12_file="${tmp_dir}/${cert_name}.p12"

    printf '%s' "${!env_name}" | base64 -d >"${pem_file}"
    certutil -A -n "${cert_name}" -t "TC,C,T" -i "${pem_file}" -d "sql:$nssdb"

    if grep -q "PRIVATE KEY" "${pem_file}"; then
      openssl pkcs12 -export \
        -in "${pem_file}" \
        -clcerts \
        -nodes \
        -out "${p12_file}" \
        -passout "pass:${passphrase}" \
        -passin "pass:${passphrase}" >/dev/null 2>&1
      pk12util -d "sql:$nssdb" -i "${p12_file}" -W "${passphrase}"
    fi
  done < <(env | grep '^ROOT_CA_' | cut -d= -f1 | sort)

  rm -rf "${tmp_dir}"
}

apply_chrome_policies() {
  local policy_file="/etc/opt/chrome/policies/managed/policies.json"
  local env_name
  local policy_key
  local policy_value
  local updated

  if ! env | grep -q '^CH_POLICY_'; then
    return
  fi

  while IFS= read -r env_name; do
    policy_key="${env_name#CH_POLICY_}"
    policy_value="${!env_name}"

    if printf '%s' "${policy_value}" | jq -e . >/dev/null 2>&1; then
      updated="$(
        jq --arg key "${policy_key}" --argjson value "${policy_value}" \
          '.[$key] = $value' "${policy_file}"
      )"
    else
      updated="$(
        jq --arg key "${policy_key}" --arg value "${policy_value}" \
          '.[$key] = $value' "${policy_file}"
      )"
    fi

    printf '%s\n' "${updated}" >"${policy_file}"
  done < <(env | grep '^CH_POLICY_' | cut -d= -f1 | sort)
}

start_pulseaudio() {
  if ! command -v pulseaudio >/dev/null 2>&1; then
    return
  fi

  mkdir -p "$HOME/.config/pulse"
  if [ -n "$PULSE_COOKIE_B64" ]; then
    printf '%s' "$PULSE_COOKIE_B64" | base64 -d >"$HOME/.config/pulse/cookie"
  fi

  pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true
  if command -v pactl >/dev/null 2>&1; then
    pactl load-module module-native-protocol-tcp >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

import_root_cas
apply_chrome_policies
start_pulseaudio

if command -v xvfb-start >/dev/null 2>&1; then
  start_background /usr/local/bin/xvfb-start
fi

wait_for_display

if command -v fileserver >/dev/null 2>&1; then
  start_background /usr/local/bin/fileserver
fi

if command -v devtools >/dev/null 2>&1; then
  start_background /usr/local/bin/devtools -listen :7070
fi

if command -v xseld >/dev/null 2>&1; then
  start_background /usr/local/bin/xseld
fi

chromedriver_args=(
  --port=4444
  --url-base=/
  --allowed-ips=
  --log-path=/tmp/chromedriver.log
  --allowed-origins=*
  --append-log
)

if [[ -n "${VERBOSE}" ]]; then
  chromedriver_args+=(--verbose)
fi

if [[ -n "${DRIVER_ARGS}" ]]; then
  # shellcheck disable=SC2206
  extra_driver_args=(${DRIVER_ARGS})
  chromedriver_args+=("${extra_driver_args[@]}")
fi

if [[ "$ENABLE_VNC_VALUE" != "1" && "$ENABLE_VNC_VALUE" != "true" ]]; then
  export ENABLE_VNC=0
fi

start_background /usr/bin/chromedriver "${chromedriver_args[@]}"

wait -n
