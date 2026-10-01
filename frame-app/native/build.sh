#!/bin/bash
# Builds the libmpv extension into addons/mpv/bin. Needs CMake, a C++17
# compiler and libmpv development files (e.g. Arch: mpv; Debian/Ubuntu:
# libmpv-dev). GODOTCPP_DIR reuses an existing godot-cpp checkout.
set -euo pipefail
cd "$(dirname "$0")/mpv"
BUILD=${BUILD_DIR:-build}
cmake -S . -B "$BUILD" -DCMAKE_BUILD_TYPE=Release -DGODOTCPP_TARGET=${TARGET:-template_debug} \
  ${GODOTCPP_DIR:+-DGODOTCPP_DIR="$GODOTCPP_DIR"}
cmake --build "$BUILD" -j "${JOBS:-6}"
ls -l ../../addons/mpv/bin/
