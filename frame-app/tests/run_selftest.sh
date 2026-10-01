#!/bin/bash
# Starts a host agent (headless Chromium, Demo service) and runs the app's
# self-test against it. Usage: GODOT=/path/to/godot tests/run_selftest.sh
# SCENE=res://tests/screenshots.tscn renders screenshots instead (needs a display).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
WORK=$(mktemp -d)
AGENT_DIR=../host-agent

PORT=8798 CDP_PORT=9334 DATA_DIR="$WORK/agent" CHROME_PATH=${CHROME_PATH:-chromium} KIOSK=0 \
  CHROME_ARGS="--headless=new --mute-audio" AGENT_TOKEN=selftest \
  node "$AGENT_DIR/src/main.ts" > "$WORK/agent.log" 2>&1 &
AGENT_PID=$!
cleanup() {
  kill "$AGENT_PID" 2>/dev/null || true
  pkill -f "user-data-dir=$WORK/agent" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
for _ in $(seq 40); do curl -sf -H 'authorization: Bearer selftest' localhost:8798/api/services >/dev/null && break; sleep 0.25; done

export STREAM_FRAME_SETTINGS_PATH="$WORK/settings.cfg"
export STREAM_FRAME_AGENT_URL=http://127.0.0.1:8798 STREAM_FRAME_TOKEN=selftest STREAM_FRAME_LAST_SERVICE=demo
export STREAM_FRAME_MOONLIGHT_COMMAND="bash $PWD/tests/fake_moonlight.sh"
export FAKE_MOONLIGHT_LOG="$WORK/moonlight.log" FAKE_MOONLIGHT_SECONDS=4

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
status=0
SCENE=${SCENE:-res://tests/selftest.tscn}
if [[ $SCENE == *selftest* ]]; then HEADLESS=--headless; else HEADLESS=; fi
"$GODOT" $HEADLESS --path . "$SCENE" || status=$?
echo "--- moonlight invocations:"; cat "$FAKE_MOONLIGHT_LOG" 2>/dev/null || echo "(none)"
exit $status
