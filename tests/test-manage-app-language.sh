#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-app-language.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

steam_dir="$tmp_dir/Steam"
mkdir -p "$steam_dir"
steam_registry_file="$steam_dir/registry.vdf"
cat > "$steam_registry_file" <<'EOS'
"Steam"
{
  "steamglobal"
  {
    "language"    "english"
  }
  "language"    "english"
}
EOS

anki_dir="$tmp_dir/Anki2"
mkdir -p "$anki_dir"
anki_prefs_file="$anki_dir/prefs21.db"
PREFS_FILE="$anki_prefs_file" python3 - <<'PY'
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

factorio_dir="$tmp_dir/factorio"
mkdir -p "$factorio_dir/config"
factorio_config_file="$factorio_dir/config/config.ini"
cat > "$factorio_config_file" <<'EOS'
; version=13
[path]
read-data=__PATH__system-read-data__
write-data=__PATH__system-write-data__

[general]
locale=en

[other]
; verbose-logging=false
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

read_anki_default_lang() {
  PREFS_FILE="$anki_prefs_file" python3 - <<'PY'
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

output="$("$script" --help)"
assert_contains "$output" "Usage: ./manage-app-language.sh <app> [--dry-run|-n] [--force|-f] [language]" "global help should show unified usage"
assert_contains "$output" "./manage-app-language.sh <app> --restore [--dry-run|-n] [--force|-f]" "global help should show restore usage"
assert_contains "$output" "Available apps:" "global help should list apps"
assert_contains "$output" "  anki" "global help should include anki"
assert_contains "$output" "  factorio" "global help should include factorio"
assert_contains "$output" "  steam" "global help should include steam"

output="$("$script" --list-apps)"
assert_contains "$output" "anki" "list-apps should print app ids"
assert_contains "$output" "factorio" "list-apps should print app ids"
assert_contains "$output" "steam" "list-apps should print app ids"

output="$("$script" --self-test)"
assert_contains "$output" "OK: anki" "self-test should verify anki module contract"
assert_contains "$output" "OK: factorio" "self-test should verify factorio module contract"
assert_contains "$output" "OK: steam" "self-test should verify steam module contract"

output="$("$script" nope 2>&1 || true)"
assert_contains "$output" "Unknown application: nope" "unknown apps should fail clearly"

output="$(STEAM_DIR="$steam_dir" "$script" steam --help)"
assert_contains "$output" "Usage: ./manage-app-language.sh steam [--dry-run|-n] [--force|-f] [language]" "app help should show steam usage"
assert_contains "$output" "./manage-app-language.sh steam --restore [--dry-run|-n] [--force|-f]" "app help should show steam restore usage"

output="$(STEAM_DIR="$steam_dir" "$script" steam)"
assert_contains "$output" "Current Steam interface language: english" "runner should read steam language"
output="$(STEAM_DIR="$steam_dir" "$script" steam --verbose)"
assert_contains "$output" "Supported Steam interface language values:" "steam verbose help should show supported languages"
assert_contains "$output" "Accepted aliases:" "steam verbose help should show alias section"
assert_contains "$output" "  ja -> japanese" "steam verbose help should list steam aliases"
assert_contains "$output" "  zh-CN -> schinese" "steam verbose help should list normalized Chinese aliases"

output="$(STEAM_DIR="$steam_dir" "$script" steam ja)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "runner should accept ISO aliases for steam"
assert_contains "$output" "Backup saved to $steam_registry_file.bak" "runner should back up steam file"
assert_contains "$(cat "$steam_registry_file.bak")" '"language"    "english"' "steam backup should preserve original value"
output="$(STEAM_DIR="$steam_dir" "$script" steam --restore)"
assert_contains "$output" "Restored Steam interface language from japanese to english." "runner should restore steam language"
assert_contains "$(cat "$steam_registry_file")" '"language"    "english"' "steam restore should put original value back"

output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki --help)"
assert_contains "$output" "Usage: ./manage-app-language.sh anki [--dry-run|-n] [--force|-f] [language]" "app help should show anki usage"
assert_contains "$output" "./manage-app-language.sh anki --restore [--dry-run|-n] [--force|-f]" "app help should show anki restore usage"

output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki)"
assert_contains "$output" "Current Anki interface language: en_US" "runner should read anki language"
output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki ja)"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "runner should change anki language"
assert_contains "$output" "Backup saved to $anki_prefs_file.bak" "runner should back up anki file"
assert_contains "$(read_anki_default_lang)" "ja_JP" "anki change should persist canonical value"
output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki --restore)"
assert_contains "$output" "Restored Anki interface language from ja_JP to en_US." "runner should restore anki language"
assert_contains "$(read_anki_default_lang)" "en_US" "anki restore should put original value back"

output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio --help)"
assert_contains "$output" "Usage: ./manage-app-language.sh factorio [--dry-run|-n] [--force|-f] [language]" "app help should show factorio usage"
assert_contains "$output" "./manage-app-language.sh factorio --restore [--dry-run|-n] [--force|-f]" "app help should show factorio restore usage"

output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio)"
assert_contains "$output" "Current Factorio interface language: en" "runner should read factorio language"
output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio zh-cn)"
assert_contains "$output" "Changed Factorio interface language from en to zh-CN." "runner should change factorio language"
assert_contains "$output" "Backup saved to $factorio_config_file.bak" "runner should back up factorio file"
assert_contains "$(cat "$factorio_config_file")" "locale=zh-CN" "factorio change should persist canonical value"
output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio --restore)"
assert_contains "$output" "Restored Factorio interface language from zh-CN to en." "runner should restore factorio language"
assert_contains "$(cat "$factorio_config_file")" "locale=en" "factorio restore should put original value back"

echo "All tests passed."
