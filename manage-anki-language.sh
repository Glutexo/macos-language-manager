#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
DISPLAY_COMMAND="./manage-anki-language.sh" DEFAULT_APP="anki" exec "$script_dir/manage-app-language.sh" "$@"
