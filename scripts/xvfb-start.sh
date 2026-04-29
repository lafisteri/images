#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${VNC_LOG_FILE:-/var/log/vnc-stack.log}"
SCREEN_RESOLUTION="${SCREEN_RESOLUTION:-1920x1080x24}"
ENABLE_VNC_VALUE="${ENABLE_VNC:-0}"
VNC_PASSWORD="${VNC_PASSWORD:-selenoid}"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

if [ "${DEBUG_VNC:-0}" = "1" ]; then
  set -x
  echo "[VNC] DEBUG_VNC=1" >>"$LOG_FILE"
fi

pids=()

cleanup() {
  echo "[VNC] cleanup" >>"$LOG_FILE"
  for pid in "${pids[@]}"; do
    if kill "$pid" >/dev/null 2>&1; then
      echo "[VNC] killed pid ${pid}" >>"$LOG_FILE"
    fi
  done
  wait || true
}

trap cleanup EXIT INT TERM

echo "[VNC] starting Xvfb" >>"$LOG_FILE"
Xvfb :99 -screen 0 "$SCREEN_RESOLUTION" -ac +extension RANDR +render -noreset >>"$LOG_FILE" 2>&1 &
pids+=("$!")

export HOME=/home/selenium
mkdir -p "$HOME/.fluxbox"

echo "[VNC] starting fluxbox (rc=$HOME/.fluxbox/init)" >>"$LOG_FILE"
fluxbox -rc "$HOME/.fluxbox/init" >>"$LOG_FILE" 2>&1 &
pids+=("$!")

until wmctrl -m >/dev/null 2>&1; do
  echo "[VNC] waiting for X server" >>"$LOG_FILE"
  sleep 0.1
done

if [[ "$ENABLE_VNC_VALUE" == "1" || "$ENABLE_VNC_VALUE" == "true" ]]; then
  echo "[VNC] starting x11vnc" >>"$LOG_FILE"
  x11vnc -display :99 -passwd "$VNC_PASSWORD" -shared -forever -loop500 -rfbport 5900 -rfbportv6 5900 >>"$LOG_FILE" 2>&1 &
  pids+=("$!")

  if [ -d /usr/share/novnc ]; then
    echo "[VNC] starting websockify/novnc" >>"$LOG_FILE"
    websockify --web=/usr/share/novnc/ 7900 localhost:5900 >>"$LOG_FILE" 2>&1 &
    pids+=("$!")
  fi
fi

echo "[VNC] stack started" >>"$LOG_FILE"

wait -n
