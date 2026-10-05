#!/bin/sh
# PC titles play in Moonlight, which lives on the host, not in this sandbox.
# Prefer the host's Moonlight flatpak; fall back to a moonlight on its PATH.
# Override entirely in Extensions -> PC connection (moonlight_command).
if command -v flatpak-spawn >/dev/null 2>&1; then
    if flatpak-spawn --host flatpak info com.moonlight_stream.Moonlight >/dev/null 2>&1; then
        exec flatpak-spawn --host flatpak run com.moonlight_stream.Moonlight "$@"
    fi
    exec flatpak-spawn --host moonlight "$@"
fi
exec moonlight "$@"
