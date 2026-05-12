#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-app-language.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

steam_dir="$tmp_dir/Steam"
mkdir -p "$steam_dir"
cat > "$steam_dir/registry.vdf" <<'EOS'
"Steam"
{
  "steamglobal"
  {
    "language"    "english"
  }
  "language"    "english"
}
EOS

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $message"
    echo "Missing: $needle"
    echo "Output:"
    printf '%s\n' "$haystack"
    exit 1
  fi
}

output="$("$script" --help)"
assert_contains "$output" "Usage: ./manage-app-language.sh <app> [--dry-run|-n] [--force|-f] [language]" "global help should show unified usage"
assert_contains "$output" "Available apps:" "global help should list apps"
assert_contains "$output" "  anki" "global help should include anki"
assert_contains "$output" "  factorio" "global help should include factorio"
assert_contains "$output" "  steam" "global help should include steam"

output="$("$script" --list-apps)"
assert_contains "$output" "anki" "list-apps should print app ids"
assert_contains "$output" "factorio" "list-apps should print app ids"
assert_contains "$output" "steam" "list-apps should print app ids"

output="$("$script" nope 2>&1 || true)"
assert_contains "$output" "Unknown application: nope" "unknown apps should fail clearly"

output="$(STEAM_DIR="$steam_dir" "$script" steam --help)"
assert_contains "$output" "Usage: ./manage-app-language.sh steam [--dry-run|-n] [--force|-f] [language]" "app help should show app-specific usage"

output="$(STEAM_DIR="$steam_dir" "$script" steam)"
assert_contains "$output" "Current Steam interface language: english" "unified runner should execute steam module"

echo "All tests passed."
