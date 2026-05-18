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

wingspan_prefs_file="$tmp_dir/com.Monster-Couch.Wingspan.plist"
WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" python3 - <<'PY'
import os
import plistlib

path = os.environ["WINGSPAN_PREFERENCES_FILE"]
data = {
    "I2 Language": "English",
    "Screenmanager Fullscreen mode": 1,
}

with open(path, "wb") as handle:
    plistlib.dump(data, handle, sort_keys=False)
PY

terraforming_mars_prefs_file="$tmp_dir/Terraforming Mars.plist"
TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" python3 - <<'PY'
import os
import plistlib

path = os.environ["TERRAFORMING_MARS_PREFERENCES_FILE"]
data = {
    "I2 Language": "English",
    "OSXPlayerCurrentLanguage": "en_US",
    "Screenmanager Fullscreen mode": 1,
}

with open(path, "wb") as handle:
    plistlib.dump(data, handle, sort_keys=False)
PY

google_helper_stub="$tmp_dir/google-account-helper.sh"
google_helper_log="$tmp_dir/google-account-helper.log"
cat > "$google_helper_stub" <<'EOS'
#!/bin/bash
set -euo pipefail

log_file="${GOOGLE_ACCOUNT_HELPER_LOG:?}"
command="${1:?}"
shift || true

case "$command" in
  read)
    printf 'English\nCzech\n'
    ;;
  write)
    printf 'write\n' >>"$log_file"
    printf '%s\n' "$@" >>"$log_file"
    ;;
  *)
    echo "Unknown helper command: $command" >&2
    exit 1
    ;;
esac
EOS
chmod +x "$google_helper_stub"

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
assert_contains "$output" "  everything" "global help should include the everything pseudo-app"
assert_contains "$output" "  anki" "global help should include anki"
assert_contains "$output" "  factorio" "global help should include factorio"
assert_contains "$output" "  google-account" "global help should include google-account"
assert_contains "$output" "  macos" "global help should include macos"
assert_contains "$output" "  steam" "global help should include steam"
assert_contains "$output" "  wingspan" "global help should include wingspan"
assert_contains "$output" "  terraforming-mars" "global help should include terraforming-mars"

output="$("$script" --list-apps)"
assert_contains "$output" "anki" "list-apps should print app ids"
assert_contains "$output" "factorio" "list-apps should print app ids"
assert_contains "$output" "google-account" "list-apps should print module ids"
assert_contains "$output" "macos" "list-apps should print module ids"
assert_contains "$output" "steam" "list-apps should print app ids"
assert_contains "$output" "wingspan" "list-apps should print app ids"
assert_contains "$output" "terraforming-mars" "list-apps should print app ids"

output="$("$symlink_script" --list-apps)"
assert_contains "$output" "steam" "symlinked runner should discover modules from the repository"

output="$("$script" --self-test)"
assert_contains "$output" "OK: anki" "self-test should verify anki module contract"
assert_contains "$output" "OK: factorio" "self-test should verify factorio module contract"
assert_contains "$output" "OK: google-account" "self-test should verify google-account module contract"
assert_contains "$output" "OK: macos" "self-test should verify macos module contract"
assert_contains "$output" "OK: steam" "self-test should verify steam module contract"
assert_contains "$output" "OK: wingspan" "self-test should verify wingspan module contract"
assert_contains "$output" "OK: terraforming-mars" "self-test should verify terraforming-mars module contract"

output="$("$script" nope 2>&1 || true)"
assert_contains "$output" "Unknown module: nope" "unknown modules should fail clearly"

output="$("$script" steam anki --help)"
assert_contains "$output" "Usage: ./manage-languages.sh steam [--dry-run|-n] [--force|-f] [language]" "multi-module help should include steam usage"
assert_contains "$output" "Usage: ./manage-languages.sh anki [--dry-run|-n] [--force|-f] [language]" "multi-module help should include anki usage"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google-account --help)"
assert_contains "$output" "Usage: ./manage-languages.sh google-account [--dry-run|-n] [language ...]" "google-account help should show module usage"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google-account)"
assert_contains "$output" "Current Google Account preferred languages:" "google-account read mode should print a heading"
assert_contains "$output" "  English" "google-account read mode should include the first preferred language"
assert_contains "$output" "  Czech" "google-account read mode should include the second preferred language"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google-account --dry-run "Czech" "English")"
assert_contains "$output" "Requested Google Account preferred languages:" "google-account dry-run should print the requested order"
assert_contains "$output" "Would reorder the Google Account preferred-language list in Safari." "google-account dry-run should describe the planned write"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google-account "Czech" "English")"
assert_contains "$output" "Applied Google Account preferred languages:" "google-account write should print the applied order"
assert_contains "$(cat "$google_helper_log")" $'write\nCzech\nEnglish' "google-account write should pass the requested order to the helper"

output="$("$script" steam macos ja 2>&1 || true)"
assert_contains "$output" "The macos module cannot be combined with other modules." "macos should stay exclusive"

output="$("$script" all steam ja 2>&1 || true)"
assert_contains "$output" "The all pseudo-module cannot be combined with other modules." "all should stay exclusive"

output="$("$script" everything steam ja 2>&1 || true)"
assert_contains "$output" "The everything pseudo-module cannot be combined with other modules." "everything should stay exclusive"

output="$("$script" macos --help)"
assert_contains "$output" "Usage: ./manage-languages.sh macos account [--dry-run|-n] [--restart|-r] [language ...]" "macos module help should be routed through the shared entry point"

output="$("$script" all --help)"
assert_contains "$output" "Usage: ./manage-languages.sh all [--dry-run|-n] [--force|-f] [language]" "all help should show bulk usage"
assert_contains "$output" "./manage-languages.sh all --inherit-macos [--dry-run|-n] [--force|-f]" "all help should show bulk inheritance usage"
assert_contains "$output" "./manage-languages.sh all --restore [--dry-run|-n] [--force|-f]" "all help should show bulk restore usage"

output="$("$script" everything --help)"
assert_contains "$output" "Usage: ./manage-languages.sh everything [--dry-run|-n] [language ...]" "everything help should show combined usage"

output="$(STEAM_DIR="$steam_dir" "$script" steam --help)"
assert_contains "$output" "Usage: ./manage-languages.sh steam [--dry-run|-n] [--force|-f] [language]" "app help should show steam usage"
assert_contains "$output" "./manage-languages.sh steam --inherit-macos [--dry-run|-n] [--force|-f]" "app help should show steam inheritance usage"
assert_contains "$output" "./manage-languages.sh steam --restore [--dry-run|-n] [--force|-f]" "app help should show steam restore usage"

output="$(STEAM_DIR="$steam_dir" "$script" steam)"
assert_contains "$output" "Current Steam interface language: english" "runner should read steam language"
output="$(STEAM_DIR="$steam_dir" "$script" steam --verbose)"
assert_contains "$output" "Supported Steam interface language values:" "steam verbose help should show unified language lines"
assert_contains "$output" "  english (en)" "steam verbose help should show canonical values with aliases inline"
assert_contains "$output" "  schinese (zh, zh-CN, zh-Hans)" "steam verbose help should list normalized Chinese aliases inline"

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

output="$(WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" "$script" wingspan --help)"
assert_contains "$output" "Usage: ./manage-languages.sh wingspan [--dry-run|-n] [--force|-f] [language]" "app help should show wingspan usage"
assert_contains "$output" "./manage-languages.sh wingspan --inherit-macos [--dry-run|-n] [--force|-f]" "app help should show wingspan inheritance usage"
assert_contains "$output" "./manage-languages.sh wingspan --restore [--dry-run|-n] [--force|-f]" "app help should show wingspan restore usage"

output="$(WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" "$script" wingspan)"
assert_contains "$output" "Current Wingspan interface language: English" "runner should read Wingspan language"
output="$(WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" "$script" wingspan --verbose)"
assert_contains "$output" "Supported Wingspan interface language values:" "wingspan verbose help should show unified language lines"
assert_contains "$output" "  English (en)" "wingspan verbose help should show canonical values with aliases inline"
assert_contains "$output" "  Deutsch (de)" "wingspan verbose help should list aliases inline"
output="$(WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" MACOS_APP_LANGUAGE_INHERIT=de-DE "$script" wingspan --dry-run --inherit-macos)"
assert_contains "$output" "Would change Wingspan interface language from English to Deutsch." "wingspan should inherit macOS locale tags"
output="$(WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" "$script" wingspan de)"
assert_contains "$output" "Changed Wingspan interface language from English to Deutsch." "runner should change wingspan language"
assert_contains "$output" "Backup saved to $wingspan_prefs_file.bak" "runner should back up wingspan file"
assert_contains "$(plutil -p "$wingspan_prefs_file")" '"I2 Language" => "Deutsch"' "wingspan change should persist canonical value"
output="$(WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" "$script" wingspan --restore)"
assert_contains "$output" "Restored Wingspan interface language from Deutsch to English." "runner should restore wingspan language"
assert_contains "$(plutil -p "$wingspan_prefs_file")" '"I2 Language" => "English"' "wingspan restore should put original value back"


output="$(TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" terraforming-mars --help)"
assert_contains "$output" "Usage: ./manage-languages.sh terraforming-mars [--dry-run|-n] [--force|-f] [language]" "app help should show terraforming-mars usage"
assert_contains "$output" "./manage-languages.sh terraforming-mars --inherit-macos [--dry-run|-n] [--force|-f]" "app help should show terraforming-mars inheritance usage"
assert_contains "$output" "./manage-languages.sh terraforming-mars --restore [--dry-run|-n] [--force|-f]" "app help should show terraforming-mars restore usage"

output="$(TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" terraforming-mars)"
assert_contains "$output" "Current Terraforming Mars interface language: English" "runner should read Terraforming Mars language"
output="$(TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" terraforming-mars --verbose)"
assert_contains "$output" "Supported Terraforming Mars interface language values:" "terraforming-mars verbose help should show unified language lines"
assert_contains "$output" "  English (en)" "terraforming-mars verbose help should show canonical values with aliases inline"
assert_contains "$output" "  Swedish (sv)" "terraforming-mars verbose help should list aliases inline"
output="$(TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" MACOS_APP_LANGUAGE_INHERIT=de-DE "$script" terraforming-mars --dry-run --inherit-macos)"
assert_contains "$output" "Would change Terraforming Mars interface language from English to German." "terraforming-mars should inherit macOS locale tags"
output="$(TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" terraforming-mars de)"
assert_contains "$output" "Changed Terraforming Mars interface language from English to German." "runner should change terraforming-mars language"
assert_contains "$output" "Backup saved to $terraforming_mars_prefs_file.bak" "runner should back up terraforming-mars file"
assert_contains "$(plutil -p "$terraforming_mars_prefs_file")" '"I2 Language" => "German"' "terraforming-mars change should persist canonical value"
assert_contains "$(plutil -p "$terraforming_mars_prefs_file")" '"OSXPlayerCurrentLanguage" => "de_DE"' "terraforming-mars change should persist locale companion value"
output="$(TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" terraforming-mars --restore)"
assert_contains "$output" "Restored Terraforming Mars interface language from German to English." "runner should restore terraforming-mars language"
assert_contains "$(plutil -p "$terraforming_mars_prefs_file")" '"I2 Language" => "English"' "terraforming-mars restore should put original value back"
assert_contains "$(plutil -p "$terraforming_mars_prefs_file")" '"OSXPlayerCurrentLanguage" => "en_US"' "terraforming-mars restore should put original locale companion value back"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all)"
assert_contains "$output" "Current Steam interface language: english" "all mode should read steam"
assert_contains "$output" "Current Anki interface language: en_US" "all mode should read anki"
assert_contains "$output" "Current Factorio interface language: en" "all mode should read factorio"
assert_contains "$output" "Current Wingspan interface language: English" "all mode should read wingspan"
assert_contains "$output" "Current Terraforming Mars interface language: English" "all mode should read terraforming-mars"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" "$script" steam anki)"
assert_contains "$output" "Current Steam interface language: english" "multi-module mode should read steam"
assert_contains "$output" "Current Anki interface language: en_US" "multi-module mode should read anki"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" "$script" steam anki ja)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "multi-module mode should change steam"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "multi-module mode should change anki"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" "$script" steam anki --restore)"
assert_contains "$output" "Restored Steam interface language from japanese to english." "multi-module restore should revert steam"
assert_contains "$output" "Restored Anki interface language from ja_JP to en_US." "multi-module restore should revert anki"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" MACOS_APP_LANGUAGE_INHERIT=de-DE "$script" all --dry-run --inherit-macos)"
assert_contains "$output" "Would change Steam interface language from english to german." "all inherit should plan steam change"
assert_contains "$output" "Would change Anki interface language from en_US to de_DE." "all inherit should plan anki change"
assert_contains "$output" "Would change Factorio interface language from en to de." "all inherit should plan factorio change"
assert_contains "$output" "Would change Wingspan interface language from English to Deutsch." "all inherit should plan wingspan change"
assert_contains "$output" "Would change Terraforming Mars interface language from English to German." "all inherit should plan terraforming-mars change"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all de)"
assert_contains "$output" "Changed Steam interface language from english to german." "all mode should change steam"
assert_contains "$output" "Changed Anki interface language from en_US to de_DE." "all mode should change anki"
assert_contains "$output" "Changed Factorio interface language from en to de." "all mode should change factorio"
assert_contains "$output" "Changed Wingspan interface language from English to Deutsch." "all mode should change wingspan"
assert_contains "$output" "Changed Terraforming Mars interface language from English to German." "all mode should change terraforming-mars"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all --restore)"
assert_contains "$output" "Restored Steam interface language from german to english." "all restore should revert steam"
assert_contains "$output" "Restored Anki interface language from de_DE to en_US." "all restore should revert anki"
assert_contains "$output" "Restored Factorio interface language from de to en." "all restore should revert factorio"
assert_contains "$output" "Restored Wingspan interface language from Deutsch to English." "all restore should revert wingspan"
assert_contains "$output" "Restored Terraforming Mars interface language from German to English." "all restore should revert terraforming-mars"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all ja)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "all mode should change steam for partially supported languages"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "all mode should change anki for partially supported languages"
assert_contains "$output" "Changed Factorio interface language from en to ja." "all mode should change factorio for partially supported languages"
assert_contains "$output" "Changed Wingspan interface language from English to 日本語." "all mode should change wingspan for partially supported languages"
assert_contains "$output" "Skipping Terraforming Mars: interface language ja is not supported." "all mode should skip unsupported modules"
assert_contains "$(plutil -p "$terraforming_mars_prefs_file")" '"I2 Language" => "English"' "unsupported modules should remain unchanged"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all --restore)"
assert_contains "$output" "Restored Steam interface language from japanese to english." "all restore should revert steam after partial bulk change"
assert_contains "$output" "Restored Anki interface language from ja_JP to en_US." "all restore should revert anki after partial bulk change"
assert_contains "$output" "Restored Factorio interface language from ja to en." "all restore should revert factorio after partial bulk change"
assert_contains "$output" "Restored Wingspan interface language from 日本語 to English." "all restore should revert wingspan after partial bulk change"
assert_contains "$output" "Restored Terraforming Mars interface language from English to English." "all restore should keep terraforming-mars unchanged after partial bulk change"

echo "All tests passed."
