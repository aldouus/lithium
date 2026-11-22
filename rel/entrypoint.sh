#!/bin/sh
set -eu
mkdir -p "${LITHIUM_DATA_ROOT:-/data}"
exec /app/bin/lithium start
