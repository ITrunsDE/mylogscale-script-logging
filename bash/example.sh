#!/usr/bin/env bash
set -u

SCRIPT_DIR=$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_PATH=${1:-"${SCRIPT_DIR}/logscale.json"}
SCRIPT_NAME=$(basename -- "$0")
SCRIPT_NAME=${SCRIPT_NAME%.sh}

# shellcheck source=logging.sh
. "${SCRIPT_DIR}/logging.sh"
initialize_logscale "$CONFIG_PATH" "$SCRIPT_NAME"

write_logscale INFO 'Script started' '{"job":"demo"}'
# Replace this harmless operation with your existing work. Keep its error handling unchanged.
result=$((6 * 7))
write_logscale INFO 'Calculation completed' "{\"result\":${result}}"
write_logscale WARN 'Demonstration warning'
write_logscale ERROR 'Demonstration error event; no operation failed'
write_logscale INFO 'Script completed'
printf 'Main script result: %s\n' "$result"
