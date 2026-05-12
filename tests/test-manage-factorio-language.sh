#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-factorio-language.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

factorio_dir="$tmp_dir/factorio"
mkdir -p "$factorio_dir/config"
config_file="$factorio_dir/config/config.ini"

write_config() {
  cat > "$config_file" <<'EOS'
; version=13
[path]
read-data=__PATH__system-read-data__
write-data=__PATH__system-write-data__

[general]
locale=en

[other]
; verbose-logging=false
EOS
}

write_config_without_locale() {
  cat > "$config_file" <<'EOS'
; version=13
[path]
read-data=__PATH__system-read-data__
write-data=__PATH__system-write-data__

[general]

[other]
; verbose-logging=false
EOS
}

stub_dir="$tmp_dir/stubs"
mkdir -p "$stub_dir"

cat > "$stub_dir/pgrep" <<'EOS'
#!/bin/bash
set -euo pipefail

if [ "${FACTORIO_TEST_PGREP_MODE:-stopped}" = "running" ]; then
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
  PATH="$stub_dir:$PATH" FACTORIO_DIR="$factorio_dir" "$script" "$@"
}

write_config
output="$(run_case)"
assert_eq "Current Factorio interface language: en" "$output" "script should print current Factorio language"

output="$(run_case --help)"
assert_contains "$output" "Usage: ./manage-factorio-language.sh [--dry-run|-n] [--force|-f] [language]" "help should show usage"
assert_contains "$output" "./manage-factorio-language.sh --restore [--dry-run|-n] [--force|-f]" "help should show restore usage"
assert_contains "$output" "Use --verbose or -v for the supported language list." "help should mention verbose help"
if [[ "$output" == *"Supported Factorio interface language values:"* ]]; then
  echo "FAIL: plain help should stay concise"
  exit 1
fi

output="$(run_case --verbose)"
assert_contains "$output" "Supported Factorio interface language values:" "verbose help should show supported languages"
assert_contains "$output" "  zh-CN" "verbose help should include language list entries"

write_config
output="$(run_case --dry-run ja)"
assert_eq "Would change Factorio interface language from en to ja." "$output" "dry-run should report planned language change"
assert_contains "$(cat "$config_file")" "locale=en" "dry-run must not modify config"

write_config
output="$(run_case en)"
assert_eq "Factorio interface language is already set to en." "$output" "script should no-op when language already matches"

write_config
output="$(run_case klingon 2>&1 || true)"
assert_contains "$output" "Unsupported Factorio interface language: klingon" "unsupported language should fail clearly"

write_config
output="$(FACTORIO_TEST_PGREP_MODE=running run_case ja 2>&1 || true)"
assert_contains "$output" "Factorio appears to be running" "write without force should fail when Factorio is running"
assert_contains "$(cat "$config_file")" "locale=en" "blocked write must not modify config"

write_config
output="$(FACTORIO_TEST_PGREP_MODE=running run_case --force zh-cn)"
assert_contains "$output" "Changed Factorio interface language from en to zh-CN." "force mode should write even when Factorio is running"
assert_contains "$output" "Backup saved to $config_file.bak" "force mode should report backup file"
assert_contains "$(cat "$config_file")" "locale=zh-CN" "force mode should update config language"
assert_contains "$(cat "$config_file.bak")" "locale=en" "force mode should preserve backup"

output="$(run_case --restore)"
assert_contains "$output" "Restored Factorio interface language from zh-CN to en." "restore should revert the language from backup"
assert_contains "$(cat "$config_file")" "locale=en" "restore should put the original value back"

write_config
output="$(run_case pt 2>&1)"
assert_contains "$output" "Changed Factorio interface language from en to pt-PT." "short pt alias should map to supported language"
assert_contains "$(cat "$config_file")" "locale=pt-PT" "pt alias should write canonical locale"

write_config_without_locale
output="$(run_case 2>&1 || true)"
assert_contains "$output" "Could not detect the current Factorio language" "read-only mode should fail when locale is missing"

write_config_without_locale
output="$(run_case --force ga)"
assert_contains "$output" "Changed Factorio interface language from unset to ga-IE." "missing locale should still be writable"
assert_contains "$(cat "$config_file")" "locale=ga-IE" "missing locale should be inserted into general section"

output="$(run_case english japanese 2>&1 || true)"
assert_contains "$output" "Only one language value can be provided." "script should reject multiple language arguments"

echo "All tests passed."
