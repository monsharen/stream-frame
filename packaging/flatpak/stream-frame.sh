#!/bin/sh
# mpv parses options with the C locale.
export LC_NUMERIC=C
exec /app/stream-frame/stream-frame "$@"
