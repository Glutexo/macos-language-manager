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

script_path="$(resolve_script_path "$0")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
selected_shell="auto"
rc_file_override=""

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
    --help|-h)
      cat <<USAGE
Install manage-languages shell completion into a shell rc file.

Usage: ./install-manage-languages-completion.sh [--shell bash|zsh|auto] [--rc-file path]

Options:
  --shell     Target shell. Default: auto, derived from \$SHELL.
  --rc-file   Override the rc file path. Intended for testing or custom setups.
  --help, -h  Show this help message.
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
    completion_file="$script_dir/completions/manage-languages.bash"
    default_rc_file="$HOME/.bashrc"
    ;;
  zsh)
    completion_file="$script_dir/completions/manage-languages.zsh"
    default_rc_file="$HOME/.zshrc"
    ;;
esac

[ -f "$completion_file" ] || fail "Completion file not found: $completion_file"

rc_file="$default_rc_file"
if [ -n "$rc_file_override" ]; then
  rc_file="$rc_file_override"
fi

mkdir -p "$(dirname "$rc_file")"
touch "$rc_file"

managed_start="# manage-languages completion start"
managed_end="# manage-languages completion end"
source_line="source \"$completion_file\""

if grep -F "$managed_start" "$rc_file" >/dev/null 2>&1; then
  RC_FILE="$rc_file" MANAGED_START="$managed_start" MANAGED_END="$managed_end" SOURCE_LINE="$source_line" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["RC_FILE"])
start = os.environ["MANAGED_START"]
end = os.environ["MANAGED_END"]
source_line = os.environ["SOURCE_LINE"]
block = f"{start}\n{source_line}\n{end}"
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
  echo "Updated completion block in $rc_file"
else
  {
    if [ -s "$rc_file" ]; then
      printf '\n'
    fi
    printf '%s\n' "$managed_start"
    printf '%s\n' "$source_line"
    printf '%s\n' "$managed_end"
  } >> "$rc_file"
  echo "Installed completion block into $rc_file"
fi

echo "Open a new $selected_shell session or source $rc_file to activate completion."
