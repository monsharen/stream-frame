#!/bin/bash
# Stands in for Moonlight in tests: records its arguments, then "the user
# closes the stream window" after a few seconds.
echo "$@" >> "${FAKE_MOONLIGHT_LOG:-/dev/null}"
sleep "${FAKE_MOONLIGHT_SECONDS:-3}"
