#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
DISPLAY_COMMAND="./manage-factorio-language.sh" DEFAULT_APP="factorio" exec "$script_dir/manage-app-language.sh" "$@"
