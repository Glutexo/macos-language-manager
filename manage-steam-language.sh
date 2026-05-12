#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
DISPLAY_COMMAND="./manage-steam-language.sh" DEFAULT_APP="steam" exec "$script_dir/manage-app-language.sh" "$@"
