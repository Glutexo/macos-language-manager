#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-languages.sh"
completion_script="$repo_root/completions/manage-languages.bash"

source "$completion_script"

assert_contains_word() {
  local needle="$1"
  shift
  local word=""

  for word in "$@"; do
    if [ "$word" = "$needle" ]; then
      return 0
    fi
  done

  echo "FAIL: missing completion word: $needle"
  printf 'Words:\n'
  printf '  %s\n' "$@"
  exit 1
}

collect_completion_words() {
  COMPLETION_WORDS=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    COMPLETION_WORDS+=("$line")
  done
}

run_completion() {
  local words=("$@")
  COMPREPLY=()
  COMP_WORDS=("${words[@]}")
  COMP_CWORD=$((${#words[@]} - 1))
  _manage_languages
  printf '%s\n' "${COMPREPLY[@]}"
}

collect_completion_words < <(run_completion "$script" "")
assert_contains_word "steam" "${COMPLETION_WORDS[@]}"
assert_contains_word "macos" "${COMPLETION_WORDS[@]}"
assert_contains_word "atlassian-account" "${COMPLETION_WORDS[@]}"
assert_contains_word "all" "${COMPLETION_WORDS[@]}"
assert_contains_word "everything" "${COMPLETION_WORDS[@]}"
assert_contains_word "--help" "${COMPLETION_WORDS[@]}"

collect_completion_words < <(run_completion "$script" "steam" "")
assert_contains_word "anki" "${COMPLETION_WORDS[@]}"
assert_contains_word "terraforming-mars" "${COMPLETION_WORDS[@]}"
assert_contains_word "--restore" "${COMPLETION_WORDS[@]}"
assert_contains_word "english" "${COMPLETION_WORDS[@]}"
assert_contains_word "en" "${COMPLETION_WORDS[@]}"

collect_completion_words < <(run_completion "$script" "steam" "anki" "")
assert_contains_word "de" "${COMPLETION_WORDS[@]}"
assert_contains_word "ja" "${COMPLETION_WORDS[@]}"
assert_contains_word "--inherit-macos" "${COMPLETION_WORDS[@]}"

collect_completion_words < <(run_completion "$script" "macos" "")
assert_contains_word "account" "${COMPLETION_WORDS[@]}"
assert_contains_word "locale" "${COMPLETION_WORDS[@]}"
assert_contains_word "all" "${COMPLETION_WORDS[@]}"
assert_contains_word "--restart" "${COMPLETION_WORDS[@]}"

collect_completion_words < <(run_completion "$script" "all" "")
assert_contains_word "de" "${COMPLETION_WORDS[@]}"
assert_contains_word "en" "${COMPLETION_WORDS[@]}"
assert_contains_word "--inherit-macos" "${COMPLETION_WORDS[@]}"

printf 'All completion tests passed.\n'

zsh_output="$(zsh -lc 'source "'"$repo_root"'"/completions/manage-languages.zsh' 2>&1)"
if [ -n "$zsh_output" ]; then
  echo "FAIL: zsh wrapper should load cleanly"
  printf '%s\n' "$zsh_output"
  exit 1
fi
