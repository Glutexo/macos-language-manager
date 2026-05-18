#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-languages.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

symlink_dir="$tmp_dir/bin"
mkdir -p "$symlink_dir"
ln -s "$script" "$symlink_dir/manage-languages"
symlink_script="$symlink_dir/manage-languages"

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
assert_contains "$output" "Usage: ./manage-languages.sh <module> [<module> ...] [--dry-run|-n] [--force|-f] [language]" "global help should show unified usage"
assert_contains "$output" "./manage-languages.sh <module> [<module> ...] --inherit-macos [--dry-run|-n] [--force|-f]" "global help should show macOS inheritance usage"
assert_contains "$output" "./manage-languages.sh <module> [<module> ...] --restore [--dry-run|-n] [--force|-f]" "global help should show restore usage"
assert_contains "$output" "Available modules:" "global help should list modules"
assert_contains "$output" "  all" "global help should include the all pseudo-app"
assert_contains "$output" "  anki" "global help should include anki"
assert_contains "$output" "  factorio" "global help should include factorio"
assert_contains "$output" "  macos" "global help should include macos"
assert_contains "$output" "  steam" "global help should include steam"

output="$("$script" --list-apps)"
assert_contains "$output" "anki" "list-apps should print app ids"
assert_contains "$output" "factorio" "list-apps should print app ids"
assert_contains "$output" "macos" "list-apps should print module ids"
assert_contains "$output" "steam" "list-apps should print app ids"

output="$("$symlink_script" --list-apps)"
assert_contains "$output" "steam" "symlinked runner should discover modules from the repository"

output="$("$script" --self-test)"
assert_contains "$output" "OK: anki" "self-test should verify anki module contract"
assert_contains "$output" "OK: factorio" "self-test should verify factorio module contract"
assert_contains "$output" "OK: macos" "self-test should verify macos module contract"
assert_contains "$output" "OK: steam" "self-test should verify steam module contract"

output="$("$script" nope 2>&1 || true)"
assert_contains "$output" "Unknown module: nope" "unknown modules should fail clearly"

output="$("$script" steam anki --help)"
assert_contains "$output" "Usage: ./manage-languages.sh steam [--dry-run|-n] [--force|-f] [language]" "multi-module help should include steam usage"
assert_contains "$output" "Usage: ./manage-languages.sh anki [--dry-run|-n] [--force|-f] [language]" "multi-module help should include anki usage"

output="$("$script" steam macos ja 2>&1 || true)"
assert_contains "$output" "The macos module cannot be combined with other modules." "macos should stay exclusive"

output="$("$script" all steam ja 2>&1 || true)"
assert_contains "$output" "The all pseudo-module cannot be combined with other modules." "all should stay exclusive"

output="$("$script" macos --help)"
assert_contains "$output" "Usage: ./manage-languages.sh macos account [--dry-run|-n] [--restart|-r] [language ...]" "macos module help should be routed through the shared entry point"

output="$("$script" all --help)"
assert_contains "$output" "Usage: ./manage-languages.sh all [--dry-run|-n] [--force|-f] [language]" "all help should show bulk usage"
assert_contains "$output" "./manage-languages.sh all --inherit-macos [--dry-run|-n] [--force|-f]" "all help should show bulk inheritance usage"
assert_contains "$output" "./manage-languages.sh all --restore [--dry-run|-n] [--force|-f]" "all help should show bulk restore usage"

output="$(STEAM_DIR="$steam_dir" "$script" steam --help)"
assert_contains "$output" "Usage: ./manage-languages.sh steam [--dry-run|-n] [--force|-f] [language]" "app help should show steam usage"
assert_contains "$output" "./manage-languages.sh steam --inherit-macos [--dry-run|-n] [--force|-f]" "app help should show steam inheritance usage"
assert_contains "$output" "./manage-languages.sh steam --restore [--dry-run|-n] [--force|-f]" "app help should show steam restore usage"

output="$(STEAM_DIR="$steam_dir" "$script" steam)"
assert_contains "$output" "Current Steam interface language: english" "runner should read steam language"
output="$(STEAM_DIR="$steam_dir" "$script" steam --verbose)"
assert_contains "$output" "Supported Steam interface language values:" "steam verbose help should show supported languages"
assert_contains "$output" "Accepted aliases:" "steam verbose help should show alias section"
assert_contains "$output" "  ja -> japanese" "steam verbose help should list steam aliases"
assert_contains "$output" "  zh-CN -> schinese" "steam verbose help should list normalized Chinese aliases"

output="$(STEAM_DIR="$steam_dir" MACOS_APP_LANGUAGE_INHERIT=ja-CZ "$script" steam --dry-run --inherit-macos)"
assert_contains "$output" "Would change Steam interface language from english to japanese." "steam should inherit macOS locale tags by primary language"
output="$(STEAM_DIR="$steam_dir" "$script" steam ja)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "runner should accept ISO aliases for steam"
assert_contains "$output" "Backup saved to $steam_registry_file.bak" "runner should back up steam file"
assert_contains "$(cat "$steam_registry_file.bak")" '"language"    "english"' "steam backup should preserve original value"
output="$(STEAM_DIR="$steam_dir" "$script" steam --restore)"
assert_contains "$output" "Restored Steam interface language from japanese to english." "runner should restore steam language"
assert_contains "$(cat "$steam_registry_file")" '"language"    "english"' "steam restore should put original value back"

output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki --help)"
assert_contains "$output" "Usage: ./manage-languages.sh anki [--dry-run|-n] [--force|-f] [language]" "app help should show anki usage"
assert_contains "$output" "./manage-languages.sh anki --inherit-macos [--dry-run|-n] [--force|-f]" "app help should show anki inheritance usage"
assert_contains "$output" "./manage-languages.sh anki --restore [--dry-run|-n] [--force|-f]" "app help should show anki restore usage"

output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki)"
assert_contains "$output" "Current Anki interface language: en_US" "runner should read anki language"
output="$(ANKI_BASE_DIR="$anki_dir" MACOS_APP_LANGUAGE_INHERIT=en-GB "$script" anki --dry-run --inherit-macos)"
assert_contains "$output" "Would change Anki interface language from en_US to en_GB." "anki should inherit exact macOS locale tags"
output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki ja)"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "runner should change anki language"
assert_contains "$output" "Backup saved to $anki_prefs_file.bak" "runner should back up anki file"
assert_contains "$(read_anki_default_lang)" "ja_JP" "anki change should persist canonical value"
output="$(ANKI_BASE_DIR="$anki_dir" "$script" anki --restore)"
assert_contains "$output" "Restored Anki interface language from ja_JP to en_US." "runner should restore anki language"
assert_contains "$(read_anki_default_lang)" "en_US" "anki restore should put original value back"

output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio --help)"
assert_contains "$output" "Usage: ./manage-languages.sh factorio [--dry-run|-n] [--force|-f] [language]" "app help should show factorio usage"
assert_contains "$output" "./manage-languages.sh factorio --inherit-macos [--dry-run|-n] [--force|-f]" "app help should show factorio inheritance usage"
assert_contains "$output" "./manage-languages.sh factorio --restore [--dry-run|-n] [--force|-f]" "app help should show factorio restore usage"

output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio)"
assert_contains "$output" "Current Factorio interface language: en" "runner should read factorio language"
output="$(FACTORIO_DIR="$factorio_dir" MACOS_APP_LANGUAGE_INHERIT=zh-Hant "$script" factorio --dry-run --inherit-macos)"
assert_contains "$output" "Would change Factorio interface language from en to zh-TW." "factorio should inherit macOS script tags"
output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio zh-cn)"
assert_contains "$output" "Changed Factorio interface language from en to zh-CN." "runner should change factorio language"
assert_contains "$output" "Backup saved to $factorio_config_file.bak" "runner should back up factorio file"
assert_contains "$(cat "$factorio_config_file")" "locale=zh-CN" "factorio change should persist canonical value"
output="$(FACTORIO_DIR="$factorio_dir" "$script" factorio --restore)"
assert_contains "$output" "Restored Factorio interface language from zh-CN to en." "runner should restore factorio language"
assert_contains "$(cat "$factorio_config_file")" "locale=en" "factorio restore should put original value back"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" "$script" all)"
assert_contains "$output" "Current Steam interface language: english" "all mode should read steam"
assert_contains "$output" "Current Anki interface language: en_US" "all mode should read anki"
assert_contains "$output" "Current Factorio interface language: en" "all mode should read factorio"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" "$script" steam anki)"
assert_contains "$output" "Current Steam interface language: english" "multi-module mode should read steam"
assert_contains "$output" "Current Anki interface language: en_US" "multi-module mode should read anki"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" "$script" steam anki ja)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "multi-module mode should change steam"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "multi-module mode should change anki"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" "$script" steam anki --restore)"
assert_contains "$output" "Restored Steam interface language from japanese to english." "multi-module restore should revert steam"
assert_contains "$output" "Restored Anki interface language from ja_JP to en_US." "multi-module restore should revert anki"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" MACOS_APP_LANGUAGE_INHERIT=ja-CZ "$script" all --dry-run --inherit-macos)"
assert_contains "$output" "Would change Steam interface language from english to japanese." "all inherit should plan steam change"
assert_contains "$output" "Would change Anki interface language from en_US to ja_JP." "all inherit should plan anki change"
assert_contains "$output" "Would change Factorio interface language from en to ja." "all inherit should plan factorio change"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" "$script" all ja)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "all mode should change steam"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "all mode should change anki"
assert_contains "$output" "Changed Factorio interface language from en to ja." "all mode should change factorio"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" "$script" all --restore)"
assert_contains "$output" "Restored Steam interface language from japanese to english." "all restore should revert steam"
assert_contains "$output" "Restored Anki interface language from ja_JP to en_US." "all restore should revert anki"
assert_contains "$output" "Restored Factorio interface language from ja to en." "all restore should revert factorio"

echo "All tests passed."
