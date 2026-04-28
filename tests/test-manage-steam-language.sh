#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-steam-language.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

steam_dir="$tmp_dir/Steam"
mkdir -p "$steam_dir"
registry_file="$steam_dir/registry.vdf"

write_registry() {
  cat > "$registry_file" <<'EOS'
"Steam"
{
  "steamglobal"
  {
    "language"    "english"
  }
  "language"    "english"
}
EOS
}

stub_dir="$tmp_dir/stubs"
mkdir -p "$stub_dir"

cat > "$stub_dir/pgrep" <<'EOS'
#!/bin/bash
set -euo pipefail

if [ "${STEAM_TEST_PGREP_MODE:-stopped}" = "running" ]; then
  exit 0
fi

exit 1
EOS
chmod +x "$stub_dir/pgrep"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $message"
    echo "Expected: $expected"
    echo "Actual:   $actual"
    exit 1
  fi
}

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

run_case() {
  PATH="$stub_dir:$PATH" STEAM_DIR="$steam_dir" "$script" "$@"
}

write_registry
output="$(run_case)"
assert_eq "Current Steam interface language: english" "$output" "script should print current Steam language"

write_registry
output="$(run_case --dry-run japanese)"
assert_eq "Would change Steam interface language from english to japanese." "$output" "dry-run should report planned language change"
assert_contains "$(cat "$registry_file")" '"language"    "english"' "dry-run must not modify registry"

write_registry
output="$(run_case english)"
assert_eq "Steam interface language is already set to english." "$output" "script should no-op when language already matches"

write_registry
output="$(run_case klingon 2>&1 || true)"
assert_contains "$output" "Unsupported Steam interface language: klingon" "unsupported language should fail clearly"

write_registry
output="$(STEAM_TEST_PGREP_MODE=running run_case japanese 2>&1 || true)"
assert_contains "$output" "Steam appears to be running" "write without force should fail when Steam is running"
assert_contains "$(cat "$registry_file")" '"language"    "english"' "blocked write must not modify registry"

write_registry
output="$(STEAM_TEST_PGREP_MODE=running run_case --force japanese)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "force mode should write even when Steam is running"
assert_contains "$output" "Backup saved to $registry_file.bak" "force mode should report backup file"
assert_contains "$(cat "$registry_file")" '"language"    "japanese"' "force mode should update registry language"
assert_contains "$(cat "$registry_file.bak")" '"language"    "english"' "force mode should preserve backup"

write_registry
output="$(run_case english japanese 2>&1 || true)"
assert_contains "$output" "Only one language value can be provided." "script should reject multiple language arguments"

echo "All tests passed."
