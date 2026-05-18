#!/bin/bash
set -euo pipefail

resolve_script_path() {
  local source_path="$1"
  local source_dir=""
  local target_path=""

  while [ -L "$source_path" ]; do
    source_dir="$(cd "$(dirname "$source_path")" && pwd)"
    target_path="$(readlink "$source_path")"
    if [[ "$target_path" != /* ]]; then
      source_path="$source_dir/$target_path"
    else
      source_path="$target_path"
    fi
  done

  source_dir="$(cd "$(dirname "$source_path")" && pwd)"
  printf '%s\n' "$source_dir/$(basename "$source_path")"
}

fail() {
  echo "$1" >&2
  exit 1
}

upsert_managed_block() {
  RC_FILE="$1" MANAGED_START="$2" MANAGED_END="$3" BLOCK_TEXT="$4" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["RC_FILE"])
start = os.environ["MANAGED_START"]
end = os.environ["MANAGED_END"]
block = os.environ["BLOCK_TEXT"]
text = path.read_text() if path.exists() else ""
start_index = text.find(start)
if start_index == -1:
    text = text.rstrip("\n") + ("\n\n" if text.strip() else "") + block + "\n"
else:
    end_index = text.find(end, start_index)
    if end_index == -1:
        raise SystemExit(f"Managed block start found without end marker in {path}")
    end_index += len(end)
    text = text[:start_index] + block + text[end_index:]
    if not text.endswith("\n"):
        text += "\n"
path.write_text(text)
PY
}

script_path="$(resolve_script_path "$0")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
selected_shell="auto"
rc_file_override=""
completion_dir_override=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --shell)
      shift
      [ "$#" -gt 0 ] || fail "The --shell option requires a value."
      selected_shell="$1"
      ;;
    --rc-file)
      shift
      [ "$#" -gt 0 ] || fail "The --rc-file option requires a value."
      rc_file_override="$1"
      ;;
    --completion-dir)
      shift
      [ "$#" -gt 0 ] || fail "The --completion-dir option requires a value."
      completion_dir_override="$1"
      ;;
    --help|-h)
      cat <<USAGE
Install manage-languages shell completion through a per-shell completion directory and one rc loader block.

Usage: ./install-manage-languages-completion.sh [--shell bash|zsh|auto] [--rc-file path] [--completion-dir path]

Options:
  --shell           Target shell. Default: auto, derived from \$SHELL.
  --rc-file         Override the rc file path. Intended for testing or custom setups.
  --completion-dir  Override the managed completion directory. Intended for testing or custom setups.
  --help, -h        Show this help message.
USAGE
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

case "$selected_shell" in
  auto)
    case "${SHELL:-}" in
      */zsh) selected_shell="zsh" ;;
      */bash) selected_shell="bash" ;;
      *) fail "Could not detect shell from SHELL=${SHELL:-}. Use --shell bash or --shell zsh." ;;
    esac
    ;;
  bash|zsh)
    ;;
  *)
    fail "Unsupported shell: $selected_shell"
    ;;
esac

case "$selected_shell" in
  bash)
    completion_source_file="$script_dir/completions/manage-languages.bash"
    default_rc_file="$HOME/.bashrc"
    default_completion_dir="$HOME/.config/bash/completions"
    installed_completion_file_name="manage-languages.bash"
    loader_glob='"$HOME/.config/bash/completions"/*.bash'
    ;;
  zsh)
    completion_source_file="$script_dir/completions/manage-languages.zsh"
    default_rc_file="$HOME/.zshrc"
    default_completion_dir="$HOME/.config/zsh/completions"
    installed_completion_file_name="manage-languages.zsh"
    loader_glob='"$HOME/.config/zsh/completions"/*.zsh'
    ;;
esac

[ -f "$completion_source_file" ] || fail "Completion file not found: $completion_source_file"

rc_file="$default_rc_file"
completion_dir="$default_completion_dir"

if [ -n "$rc_file_override" ]; then
  rc_file="$rc_file_override"
fi

if [ -n "$completion_dir_override" ]; then
  completion_dir="$completion_dir_override"
  loader_glob="\"$completion_dir\"/*.${selected_shell}"
fi

completion_target_file="$completion_dir/$installed_completion_file_name"
mkdir -p "$completion_dir" "$(dirname "$rc_file")"
touch "$rc_file"
ln -sfn "$completion_source_file" "$completion_target_file"

managed_start="# manage-languages completion loader start"
managed_end="# manage-languages completion loader end"
managed_block="$managed_start
for completion_file in $loader_glob; do
  [ -r \"\$completion_file\" ] || continue
  source \"\$completion_file\"
done
$managed_end"

if grep -F "$managed_start" "$rc_file" >/dev/null 2>&1; then
  upsert_managed_block "$rc_file" "$managed_start" "$managed_end" "$managed_block"
  echo "Updated completion loader block in $rc_file"
else
  upsert_managed_block "$rc_file" "$managed_start" "$managed_end" "$managed_block"
  echo "Installed completion loader block into $rc_file"
fi

echo "Linked completion file to $completion_target_file"
echo "Open a new $selected_shell session or source $rc_file to activate completion."
