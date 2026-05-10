#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-anki-language.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

anki_dir="$tmp_dir/Anki2"
mkdir -p "$anki_dir"
prefs_file="$anki_dir/prefs21.db"

write_prefs() {
  PREFS_FILE="$prefs_file" python3 - <<'PY'
import os
import pickle
import sqlite3

path = os.environ["PREFS_FILE"]
meta = {
    "defaultLang": "en_US",
    "ver": 0,
    "updates": True,
    "created": 0,
    "id": 1,
    "lastMsg": 0,
    "suppressUpdate": False,
    "firstRun": False,
}

conn = sqlite3.connect(path)
conn.execute(
    "create table if not exists profiles (name text primary key collate nocase, data blob not null)"
)
conn.execute("delete from profiles")
conn.execute(
    "insert into profiles values ('_global', ?)",
    (sqlite3.Binary(pickle.dumps(meta, protocol=4)),),
)
conn.commit()
conn.close()
PY
}

read_default_lang() {
  PREFS_FILE="$prefs_file" python3 - <<'PY'
import os
import pickle
import sqlite3

path = os.environ["PREFS_FILE"]
conn = sqlite3.connect(path)
row = conn.execute(
    "select cast(data as blob) from profiles where name = '_global'"
).fetchone()
conn.close()
print(pickle.loads(row[0])["defaultLang"])
PY
}

stub_dir="$tmp_dir/stubs"
mkdir -p "$stub_dir"

cat > "$stub_dir/pgrep" <<'EOF2'
#!/bin/bash
set -euo pipefail

if [ "${ANKI_TEST_PGREP_MODE:-stopped}" = "running" ]; then
  exit 0
fi

exit 1
EOF2
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
  PATH="$stub_dir:$PATH" ANKI_BASE_DIR="$anki_dir" "$script" "$@"
}

write_prefs
output="$(run_case)"
assert_eq "Current Anki interface language: en_US" "$output" "script should print current Anki language"

output="$(run_case --help)"
assert_contains "$output" "Usage: ./manage-anki-language.sh [--dry-run|-n] [--force|-f] [language]" "help should show usage"
assert_contains "$output" "Use --verbose or -v for the supported language list." "help should mention verbose help"
if [[ "$output" == *"Supported Anki interface language values:"* ]]; then
  echo "FAIL: plain help should stay concise"
  exit 1
fi

output="$(run_case --verbose)"
assert_contains "$output" "Supported Anki interface language values:" "verbose help should show supported languages"
assert_contains "$output" "  ja_JP" "verbose help should include language list entries"
assert_contains "$output" "Short aliases such as en, cs, ja, pt, or zh" "verbose help should mention aliases"

write_prefs
output="$(run_case --dry-run ja)"
assert_eq "Would change Anki interface language from en_US to ja_JP." "$output" "dry-run should report planned language change"
assert_eq "en_US" "$(read_default_lang)" "dry-run must not modify prefs db"

write_prefs
output="$(run_case en_US)"
assert_eq "Anki interface language is already set to en_US." "$output" "script should no-op when language already matches"

write_prefs
output="$(run_case klingon 2>&1 || true)"
assert_contains "$output" "Unsupported Anki interface language: klingon" "unsupported language should fail clearly"

write_prefs
output="$(ANKI_TEST_PGREP_MODE=running run_case ja_JP 2>&1 || true)"
assert_contains "$output" "Anki appears to be running" "write without force should fail when Anki is running"
assert_eq "en_US" "$(read_default_lang)" "blocked write must not modify prefs db"

write_prefs
output="$(ANKI_TEST_PGREP_MODE=running run_case --force ja)"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "force mode should write even when Anki is running"
assert_contains "$output" "Backup saved to $prefs_file.bak" "force mode should report backup file"
assert_eq "ja_JP" "$(read_default_lang)" "force mode should update stored language"
backup_lang="$(PREFS_FILE="$prefs_file.bak" python3 - <<'PY'
import os
import pickle
import sqlite3

path = os.environ["PREFS_FILE"]
conn = sqlite3.connect(path)
row = conn.execute(
    "select cast(data as blob) from profiles where name = '_global'"
).fetchone()
conn.close()
print(pickle.loads(row[0])["defaultLang"])
PY
)"
assert_eq "en_US" "$backup_lang" "force mode should preserve backup"

write_prefs
output="$(run_case zh 2>&1)"
assert_contains "$output" "Changed Anki interface language from en_US to zh_CN." "short zh alias should map to supported language"
assert_eq "zh_CN" "$(read_default_lang)" "zh alias should persist canonical value"

write_prefs
output="$(run_case en_US ja_JP 2>&1 || true)"
assert_contains "$output" "Only one language value can be provided." "script should reject multiple language arguments"

echo "All tests passed."
