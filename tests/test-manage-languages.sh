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

epic_games_launcher_preferences_dir="$tmp_dir/EpicGamesLauncher"
epic_games_launcher_settings_dir="$epic_games_launcher_preferences_dir/Mac"
epic_games_launcher_settings_file="$epic_games_launcher_settings_dir/GameUserSettings.ini"
epic_games_launcher_process_match="$tmp_dir/EpicGamesLauncher-NotRunning"

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

google_helper_stub="$tmp_dir/google-helper.sh"
google_helper_log="$tmp_dir/google-helper.log"
google_helper_real="$repo_root/language-modules/google-safari-helper.sh"
cat > "$google_helper_stub" <<'EOS'
#!/bin/bash
set -euo pipefail

log_file="${GOOGLE_ACCOUNT_HELPER_LOG:?}"
scenario="${GOOGLE_ACCOUNT_HELPER_SCENARIO:-default}"
profile_name="${GOOGLE_ACCOUNT_BROWSER_PROFILE:-}"
command="${1:?}"
shift || true

case "$command" in
  list-profiles)
    printf 'default\nwork\npersonal\n'
    ;;
  refresh-profiles)
    printf 'default\nwork\npersonal\n'
    ;;
  read)
    printf 'English\nCzech\n'
    ;;
  read-json)
    if [ "$scenario" = "added-for-you" ]; then
      printf '%s\n' '{"status":"ok","auto_add_enabled":true,"languages":[{"id":"en","display":"English","added_for_you":false},{"id":"ja","display":"Japanese (Added for you)","added_for_you":true},{"id":"cs","display":"Czech","added_for_you":false}]}'
    elif [ "$scenario" = "inherit-variant-mismatch" ]; then
      printf '%s\n' '{"status":"ok","auto_add_enabled":false,"languages":[{"id":"de-CZ","display":"German","added_for_you":false},{"id":"sk","display":"Slovak","added_for_you":false}]}'
    else
      printf '%s\n' '{"status":"ok","auto_add_enabled":false,"languages":[{"id":"en","display":"English","added_for_you":false},{"id":"cs","display":"Czech","added_for_you":false}]}'
    fi
    ;;
  resolve-labels)
    for label in "$@"; do
      case "$label" in
        German) printf 'German\n' ;;
        Czech) printf 'Czech\n' ;;
        Slovak) printf 'Slovak\n' ;;
        *) printf '%s\n' "$label" ;;
      esac
    done
    ;;
  disable-auto-add)
    printf 'disable-auto-add\t%s\n' "${profile_name:-default}" >>"$log_file"
    ;;
  enable-auto-add)
    printf 'enable-auto-add\t%s\n' "${profile_name:-default}" >>"$log_file"
    ;;
  write)
    printf 'write\t%s\n' "${profile_name:-default}" >>"$log_file"
    printf '%s\n' "$@" >>"$log_file"
    ;;
  *)
    echo "Unknown helper command: $command" >&2
    exit 1
    ;;
esac
EOS
chmod +x "$google_helper_stub"

atlassian_helper_stub="$tmp_dir/atlassian-helper.sh"
atlassian_helper_log="$tmp_dir/atlassian-helper.log"
atlassian_helper_real="$repo_root/language-modules/atlassian-safari-helper.sh"
cat > "$atlassian_helper_stub" <<'EOS'
#!/bin/bash
set -euo pipefail

log_file="${ATLASSIAN_ACCOUNT_HELPER_LOG:?}"
profile_name="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE:-}"
command="${1:?}"
shift || true

case "$command" in
  list-profiles)
    printf 'default\nwork\npersonal\n'
    ;;
  refresh-profiles)
    printf 'default\nwork\npersonal\n'
    ;;
  read-json)
    printf '%s\n' '{"status":"ok","language":{"value":"en-US","label":"English (US)"}}'
    ;;
  write)
    printf 'write\t%s\t%s\n' "${profile_name:-default}" "$1" >>"$log_file"
    ;;
  *)
    echo "Unknown helper command: $command" >&2
    exit 1
    ;;
esac
EOS
chmod +x "$atlassian_helper_stub"

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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: $message"
    echo "Unexpected: $needle"
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
assert_contains "$output" "  epic-games-launcher" "global help should include epic-games-launcher"
assert_contains "$output" "  factorio" "global help should include factorio"
assert_contains "$output" "  atlassian" "global help should include atlassian"
assert_contains "$output" "  google" "global help should include google"
assert_contains "$output" "  safari-profiles" "global help should include safari-profiles"
assert_contains "$output" "  macos" "global help should include macos"
assert_contains "$output" "  steam" "global help should include steam"
assert_contains "$output" "  wingspan" "global help should include wingspan"
assert_contains "$output" "  terraforming-mars" "global help should include terraforming-mars"

output="$("$script" --list-apps)"
assert_contains "$output" "anki" "list-apps should print app ids"
assert_contains "$output" "epic-games-launcher" "list-apps should print app ids"
assert_contains "$output" "factorio" "list-apps should print app ids"
assert_contains "$output" "atlassian" "list-apps should print module ids"
assert_contains "$output" "google" "list-apps should print module ids"
assert_contains "$output" "safari-profiles" "list-apps should print module ids"
assert_contains "$output" "macos" "list-apps should print module ids"
assert_contains "$output" "steam" "list-apps should print app ids"
assert_contains "$output" "wingspan" "list-apps should print app ids"
assert_contains "$output" "terraforming-mars" "list-apps should print app ids"

output="$("$symlink_script" --list-apps)"
assert_contains "$output" "steam" "symlinked runner should discover modules from the repository"

output="$("$script" --self-test)"
assert_contains "$output" "OK: anki" "self-test should verify anki module contract"
assert_contains "$output" "OK: epic-games-launcher" "self-test should verify epic-games-launcher module contract"
assert_contains "$output" "OK: factorio" "self-test should verify factorio module contract"
assert_contains "$output" "OK: atlassian" "self-test should verify atlassian module contract"
assert_contains "$output" "OK: google" "self-test should verify google module contract"
assert_contains "$output" "OK: safari-profiles" "self-test should verify safari-profiles module contract"
assert_contains "$output" "OK: macos" "self-test should verify macos module contract"
assert_contains "$output" "OK: steam" "self-test should verify steam module contract"
assert_contains "$output" "OK: wingspan" "self-test should verify wingspan module contract"
assert_contains "$output" "OK: terraforming-mars" "self-test should verify terraforming-mars module contract"

output="$("$script" nope 2>&1 || true)"
assert_contains "$output" "Unknown module: nope" "unknown modules should fail clearly"

output="$("$script" steam anki --help)"
assert_contains "$output" "Usage: ./manage-languages.sh steam [--dry-run|-n] [--force|-f] [language]" "multi-module help should include steam usage"
assert_contains "$output" "Usage: ./manage-languages.sh anki [--dry-run|-n] [--force|-f] [language]" "multi-module help should include anki usage"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --help)"
assert_contains "$output" "Usage: ./manage-languages.sh google [--dry-run|-n] [language ...]" "google help should show module usage"
assert_contains "$output" 'xx:yy' "google help should show macOS-style token syntax"
assert_contains "$output" '--inherit-macos' "google help should show inheritance support"
assert_contains "$output" '--disable-auto-add' "google help should show auto-add cleanup support"
assert_contains "$output" '--enable-auto-add' "google help should show auto-add enable support"
assert_contains "$output" '--browser-profile NAME' "google help should show browser profile selection"
assert_contains "$output" '--all-browser-profiles' "google help should show all-browser-profiles support"

output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian --help)"
assert_contains "$output" "Usage: ./manage-languages.sh atlassian [--dry-run|-n] [language]" "atlassian help should show module usage"
assert_contains "$output" '--inherit-macos' "atlassian help should show inheritance support"
assert_contains "$output" '--browser-profile NAME' "atlassian help should show browser profile selection"
assert_contains "$output" '--all-browser-profiles' "atlassian help should show all-browser-profiles support"

output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian --verbose)"
assert_contains "$output" "Supported Atlassian account language values:" "atlassian verbose help should list supported values"
assert_contains "$output" "  Czech → Čeština (cs,cs-CZ,cs_CZ,cestina,čeština,czech)" "atlassian verbose help should include the Atlassian Czech label and aliases"
assert_contains "$output" "  Croatian → Hrvatski (hr,hr-HR,hr_HR,croatian)" "atlassian verbose help should include Croatian"
assert_contains "$output" "  Thai → ภาษาไทย‎ (th,th-TH,th_TH,thai)" "atlassian verbose help should include Thai"

output="$("$script" safari-profiles --help)"
assert_contains "$output" "Usage: ./manage-languages.sh safari-profiles" "safari-profiles help should show module usage"
assert_contains "$output" '--refresh' "safari-profiles help should show refresh support"
assert_contains "$output" '--clear-cache' "safari-profiles help should show cache clearing support"
assert_contains "$output" '--list-cache' "safari-profiles help should show cache listing support"
assert_contains "$output" '--list-effective' "safari-profiles help should show effective listing support"
assert_contains "$output" '--show-cache-path' "safari-profiles help should show cache-path support"

safari_profiles_cache="$tmp_dir/safari-browser-profiles.txt"
output="$(SAFARI_BROWSER_PROFILE_CACHE="$safari_profiles_cache" "$script" safari-profiles --show-cache-path)"
assert_contains "$output" "$safari_profiles_cache" "safari-profiles should print the requested cache path"

output="$(SAFARI_BROWSER_PROFILE_CACHE="$safari_profiles_cache" SAFARI_BROWSER_PROFILE_MENU_DATA=$'NewGlutexoWindow?isDefaultProfile=true\t新規Glutexoウインドウ\nNewTwistoWindow?isDefaultProfile=false\t새로운 Twisto 윈도우\nNewPrivateWindow\t새로운 개인정보 보호 브라우징 윈도우\nNewTab\t새로운 탭' "$script" safari-profiles --refresh)"
assert_contains "$output" "Refreshed Safari browser profiles:" "safari-profiles refresh should print a heading"
assert_contains "$output" $'  Glutexo\n  Twisto' "safari-profiles refresh should print refreshed names"
assert_contains "$(cat "$safari_profiles_cache")" $'Glutexo\nTwisto' "safari-profiles refresh should store the refreshed cache"

output="$(SAFARI_BROWSER_PROFILE_CACHE="$safari_profiles_cache" "$script" safari-profiles --list-cache)"
assert_contains "$output" $'Glutexo\nTwisto' "safari-profiles should list cached names"

output="$(SAFARI_BROWSER_PROFILE_CACHE="$safari_profiles_cache" "$script" safari-profiles)"
assert_contains "$output" "Safari browser-profile cache path: $safari_profiles_cache" "safari-profiles default mode should print the cache path"
assert_contains "$output" "Cached Safari browser profiles:" "safari-profiles default mode should print cached names"
assert_contains "$output" "Effective Safari browser profiles:" "safari-profiles default mode should print effective names"

output="$(SAFARI_BROWSER_PROFILE_CACHE="$safari_profiles_cache" "$script" safari-profiles --clear-cache)"
assert_contains "$output" "Removed Safari browser-profile cache: $safari_profiles_cache" "safari-profiles should clear the cache"

atlassian_helper_test_home="$tmp_dir/atlassian-helper-home"
atlassian_helper_test_db_dir="$atlassian_helper_test_home/Library/Containers/com.apple.Safari/Data/Library/Safari"
mkdir -p "$atlassian_helper_test_db_dir"
atlassian_helper_test_db="$atlassian_helper_test_db_dir/SafariTabs.db"
ATLASSIAN_HELPER_TEST_DB="$atlassian_helper_test_db" python3 - <<'PY'
import os
import sqlite3

path = os.environ["ATLASSIAN_HELPER_TEST_DB"]
conn = sqlite3.connect(path)
conn.execute(
    "create table bookmarks (id integer primary key, title text, external_uuid text, type integer, subtype integer, order_index integer)"
)
conn.executemany(
    "insert into bookmarks (id, title, external_uuid, type, subtype, order_index) values (?, ?, ?, ?, ?, ?)",
    [
        (1, "Ignored Folder", "folder-1", 2, 0, 0),
        (2, "", "DefaultProfile", 1, 2, 0),
        (3, "Work", "uuid-work", 1, 2, 1),
        (4, "Personal", "uuid-personal", 1, 2, 2),
    ],
)
conn.commit()
conn.close()
PY

output="$(HOME="$atlassian_helper_test_home" "$atlassian_helper_real" list-profiles)"
assert_contains "$output" $'default\nWork\nPersonal' "atlassian helper should read Safari profile names from SafariTabs.db"

atlassian_helper_source="$(sed -n '/if (control.tagName === "SELECT") {/,/window.__codexAtlassianLanguageDidChange = true;/p' "$atlassian_helper_real")"
assert_not_contains "$atlassian_helper_source" "requestedSlug" "atlassian helper select fallback should not reference an undefined requestedSlug variable"
assert_contains "$atlassian_helper_source" "searchCandidates.some((candidate)" "atlassian helper select fallback should match supported search candidates"

atlassian_candidate_builder="$(sed -n '/const buildSearchCandidates = (label, tag) => {/,/return \[...values, ...fallbackValues\];/p' "$atlassian_helper_real")"
assert_contains "$atlassian_candidate_builder" "pushFallback(label);" "atlassian helper should keep the English label only as a fallback search candidate"
assert_contains "$atlassian_candidate_builder" "return [...values, ...fallbackValues];" "atlassian helper should prefer localized search candidates before English fallbacks"

shared_profile_helper_source="$(sed -n '/safari_open_profile_page() {/,/safari_open_page() {/p' "$repo_root/language-modules/safari-browser-profile-helper.sh")"
assert_contains "$shared_profile_helper_source" "set windowCountBeforeActivate to count of windows" "shared Safari profile helper should detect whether Safari had any windows before activation"
assert_contains "$shared_profile_helper_source" "if windowCountBeforeActivate is 0 then" "shared Safari profile helper should close Safari's auto-opened empty window after opening a dedicated profile window"

atlassian_helper_menu_cache="$tmp_dir/atlassian-helper-menu-cache.txt"
output="$(ATLASSIAN_ACCOUNT_BROWSER_PROFILE_CACHE="$atlassian_helper_menu_cache" ATLASSIAN_ACCOUNT_BROWSER_PROFILE_MENU_DATA=$'NewGlutexoWindow?isDefaultProfile=true\t新規Glutexoウインドウ\nNewTwistoWindow?isDefaultProfile=false\t새로운 Twisto 윈도우\nNewPrivateWindow\t새로운 개인정보 보호 브라우징 윈도우\nNewTab\t새로운 탭' "$atlassian_helper_real" refresh-profiles)"
assert_contains "$output" $'Glutexo\nTwisto' "atlassian helper should parse quoted Safari profile names independently of the menu language"
assert_contains "$(cat "$atlassian_helper_menu_cache")" $'Glutexo\nTwisto' "atlassian helper should store refreshed browser profile names in cache"

output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian)"
assert_contains "$output" "Current Atlassian account language: English (US)" "atlassian read mode should print the current language"

output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian --dry-run Czech)"
assert_contains "$output" "Current Atlassian account language: English (US)" "atlassian dry-run should print the current language"
assert_contains "$output" "New Atlassian account language: Čeština" "atlassian dry-run should print the Atlassian target language label"
assert_contains "$output" "Would change the Atlassian account language in Safari." "atlassian dry-run should describe the planned write"

output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" MACOS_APP_LANGUAGE_INHERIT=cs-CZ "$script" atlassian --dry-run --inherit-macos)"
assert_contains "$output" "New Atlassian account language: Čeština" "atlassian inheritance should map the first macOS language to the Atlassian target label"

output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" MACOS_APP_LANGUAGE_INHERIT=de-CZ "$script" atlassian --dry-run --inherit-macos)"
assert_contains "$output" "New Atlassian account language: Deutsch" "atlassian inheritance should fall back from unsupported region variants to the base language"

output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian 'English (US)')"
assert_contains "$output" "Atlassian account language is already set to English (US)." "atlassian should detect no-op writes"

rm -f "$atlassian_helper_log"
output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian Czech)"
assert_contains "$output" "Changed Atlassian account language from English (US) to Čeština." "atlassian write should print the Atlassian target language label"
assert_contains "$(cat "$atlassian_helper_log")" $'write\tdefault\tČeština' "atlassian write should pass the Atlassian language label to the helper"

rm -f "$atlassian_helper_log"
output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian --browser-profile work Czech)"
assert_contains "$(cat "$atlassian_helper_log")" $'write\twork\tČeština' "atlassian should target the requested browser profile with the Atlassian language label"

rm -f "$atlassian_helper_log"
output="$(ATLASSIAN_ACCOUNT_LANGUAGE_HELPER="$atlassian_helper_stub" ATLASSIAN_ACCOUNT_HELPER_LOG="$atlassian_helper_log" "$script" atlassian --all-browser-profiles --dry-run Czech)"
assert_contains "$output" "Browser profile: default" "atlassian all-browser-profiles should print the first profile heading"
assert_contains "$output" "Browser profile: work" "atlassian all-browser-profiles should print the second profile heading"
assert_contains "$output" "Browser profile: personal" "atlassian all-browser-profiles should print the third profile heading"

google_helper_test_home="$tmp_dir/google-helper-home"
google_helper_test_db_dir="$google_helper_test_home/Library/Containers/com.apple.Safari/Data/Library/Safari"
mkdir -p "$google_helper_test_db_dir"
google_helper_test_db="$google_helper_test_db_dir/SafariTabs.db"
GOOGLE_HELPER_TEST_DB="$google_helper_test_db" python3 - <<'PY'
import os
import sqlite3

path = os.environ["GOOGLE_HELPER_TEST_DB"]
conn = sqlite3.connect(path)
conn.execute(
    "create table bookmarks (id integer primary key, title text, external_uuid text, type integer, subtype integer, order_index integer)"
)
conn.executemany(
    "insert into bookmarks (id, title, external_uuid, type, subtype, order_index) values (?, ?, ?, ?, ?, ?)",
    [
        (1, "Ignored Folder", "folder-1", 2, 0, 0),
        (2, "", "DefaultProfile", 1, 2, 0),
        (3, "Work", "uuid-work", 1, 2, 1),
        (4, "Personal", "uuid-personal", 1, 2, 2),
    ],
)
conn.commit()
conn.close()
PY

output="$(HOME="$google_helper_test_home" "$google_helper_real" list-profiles)"
assert_contains "$output" $'default\nWork\nPersonal' "google helper should read Safari profile names from SafariTabs.db"

google_helper_menu_cache="$tmp_dir/google-helper-menu-cache.txt"
output="$(GOOGLE_ACCOUNT_BROWSER_PROFILE_CACHE="$google_helper_menu_cache" GOOGLE_ACCOUNT_BROWSER_PROFILE_MENU_DATA=$'NewGlutexoWindow?isDefaultProfile=true\t新規Glutexoウインドウ\nNewTwistoWindow?isDefaultProfile=false\t새로운 Twisto 윈도우\nNewPrivateWindow\t새로운 개인정보 보호 브라우징 윈도우\nNewTab\t새로운 탭' "$google_helper_real" refresh-profiles)"
assert_contains "$output" $'Glutexo\nTwisto' "google helper should parse quoted Safari profile names independently of the menu language"
assert_contains "$(cat "$google_helper_menu_cache")" $'Glutexo\nTwisto' "google helper should store refreshed browser profile names in cache"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google)"
assert_contains "$output" "Current Google Account preferred languages:" "google read mode should print a heading"
assert_contains "$output" "  English" "google read mode should include the first preferred language"
assert_contains "$output" "  Czech" "google read mode should include the second preferred language"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" GOOGLE_ACCOUNT_HELPER_SCENARIO=added-for-you "$script" google)"
assert_contains "$output" "Japanese (Added for you)" "google read mode should surface Added for you entries"
assert_contains "$output" "Warning: Google still marks these languages as Added for you:" "google should warn about Added for you entries"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --dry-run "Czech")"
assert_contains "$output" "New Google Account preferred languages:" "google dry-run should print the new order"
assert_contains "$output" $'  Czech\n  English' "google dry-run should move a language to the front"
assert_contains "$output" "Would change the Google Account preferred-language list in Safari." "google dry-run should describe the planned write"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --dry-run --disable-auto-add)"
assert_contains "$output" "Would disable automatic Google language additions in Safari." "google dry-run should describe auto-add cleanup without language arguments"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --dry-run --enable-auto-add)"
assert_contains "$output" "Would enable automatic Google language additions in Safari." "google dry-run should describe auto-add enabling without language arguments"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --dry-run "English:" "-Czech")"
assert_contains "$output" $'New Google Account preferred languages:\n  English' "google dry-run should support end placement plus removal"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --dry-run "English:Czech")"
assert_contains "$output" "Google Account preferred languages are already in the requested order." "google should treat an anchored no-op as already ordered"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" MACOS_APP_LANGUAGE_INHERIT=$'de-CZ\ncs-CZ' "$script" google --dry-run --inherit-macos)"
assert_contains "$output" $'New Google Account preferred languages:\n  German\n  Czech' "google inheritance should sync the full macOS language list order"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google "Czech")"
assert_contains "$output" "Applied Google Account preferred languages:" "google write should print the applied order"
assert_contains "$(cat "$google_helper_log")" $'write\tdefault\nCzech\nEnglish' "google write should pass the computed order to the helper"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --browser-profile work "Czech")"
assert_contains "$(cat "$google_helper_log")" $'write\twork\nCzech\nEnglish' "google should target the requested browser profile"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --all-browser-profiles "Czech")"
assert_contains "$output" "Browser profile: default" "google all-browser-profiles should print the first profile heading"
assert_contains "$output" "Browser profile: work" "google all-browser-profiles should print the second profile heading"
assert_contains "$output" "Browser profile: personal" "google all-browser-profiles should print the third profile heading"
assert_contains "$(cat "$google_helper_log")" $'write\tdefault\nCzech\nEnglish\nwrite\twork\nCzech\nEnglish\nwrite\tpersonal\nCzech\nEnglish' "google all-browser-profiles should write to every profile"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" GOOGLE_ACCOUNT_HELPER_SCENARIO=inherit-variant-mismatch MACOS_APP_LANGUAGE_INHERIT=$'de-CZ\nsk-CZ' "$script" google --inherit-macos)"
assert_contains "$output" "Google Account preferred languages are already in the requested order." "google inherit should still recognize label-level no-op states"
assert_contains "$output" "Warning: Google kept different language variants than macOS requested:" "google inherit should warn when Google keeps a different concrete variant"
assert_contains "$output" "sk-CZ → sk (Slovak)" "google inherit should report the exact macOS and Google variant mismatch"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --disable-auto-add)"
assert_contains "$output" "Disabled automatic Google language additions in Safari." "google should support disabling auto-add without language arguments"
assert_contains "$(cat "$google_helper_log")" $'disable-auto-add\tdefault' "google should call the helper cleanup mode"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --enable-auto-add)"
assert_contains "$output" "Enabled automatic Google language additions in Safari." "google should support enabling auto-add without language arguments"
assert_contains "$(cat "$google_helper_log")" $'enable-auto-add\tdefault' "google should call the helper enable mode"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --disable-auto-add "Czech")"
assert_contains "$(cat "$google_helper_log")" $'disable-auto-add\tdefault\nwrite\tdefault\nCzech\nEnglish' "google should disable auto-add before writing the new list"

rm -f "$google_helper_log"
output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --enable-auto-add "Czech")"
assert_contains "$(cat "$google_helper_log")" $'enable-auto-add\tdefault\nwrite\tdefault\nCzech\nEnglish' "google should enable auto-add before writing the new list"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --enable-auto-add --disable-auto-add 2>&1 || true)"
assert_contains "$output" "Use either --disable-auto-add or --enable-auto-add, not both." "google should reject conflicting auto-add flags"

output="$(GOOGLE_ACCOUNT_LANGUAGE_HELPER="$google_helper_stub" GOOGLE_ACCOUNT_HELPER_LOG="$google_helper_log" "$script" google --browser-profile nope 2>&1 || true)"
assert_contains "$output" "Unknown browser profile: nope" "google should reject an unknown browser profile"

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

output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" "$script" epic-games-launcher --help)"
assert_contains "$output" "Usage: ./manage-languages.sh epic-games-launcher [--dry-run|-n] [--force|-f] [language]" "app help should show epic-games-launcher usage"
assert_contains "$output" "./manage-languages.sh epic-games-launcher --inherit-macos [--dry-run|-n] [--force|-f]" "app help should show epic-games-launcher inheritance usage"
assert_contains "$output" "./manage-languages.sh epic-games-launcher --restore [--dry-run|-n] [--force|-f]" "app help should show epic-games-launcher restore usage"

output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" "$script" epic-games-launcher)"
assert_contains "$output" "Current Epic Games Launcher interface language: system" "runner should treat a missing Epic Games Launcher override as system mode"
output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" "$script" epic-games-launcher --verbose)"
assert_contains "$output" "Supported Epic Games Launcher interface language values:" "epic-games-launcher verbose help should show unified language lines"
assert_contains "$output" "  system (default, os, use-system)" "epic-games-launcher verbose help should show the system-mode aliases"
assert_contains "$output" "  zh-Hans (zh, zh-SG)" "epic-games-launcher verbose help should show normalized Chinese aliases inline"
output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" MACOS_APP_LANGUAGE_INHERIT=ja-CZ "$script" epic-games-launcher --dry-run --inherit-macos)"
assert_contains "$output" "Would change Epic Games Launcher interface language from system to ja." "epic-games-launcher should inherit macOS locale tags without requiring a preexisting settings file"
output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" "$script" epic-games-launcher cs)"
assert_contains "$output" "Changed Epic Games Launcher interface language from system to cs." "runner should change epic-games-launcher language from system mode"
assert_contains "$output" "Backup saved to $epic_games_launcher_settings_file.bak" "runner should back up epic-games-launcher settings"
assert_contains "$(cat "$epic_games_launcher_settings_file")" "Culture=cs" "epic-games-launcher change should persist canonical value"
assert_not_contains "$(cat "$epic_games_launcher_settings_file.bak")" "Culture=" "epic-games-launcher backup should preserve the original system-mode state"
output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" "$script" epic-games-launcher system)"
assert_contains "$output" "Changed Epic Games Launcher interface language from cs to system." "epic-games-launcher should switch back to the native system-mode setting"
assert_not_contains "$(cat "$epic_games_launcher_settings_file")" "Culture=" "epic-games-launcher system mode should remove the explicit culture override"
output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" "$script" epic-games-launcher cs)"
assert_contains "$output" "Changed Epic Games Launcher interface language from system to cs." "epic-games-launcher should allow reapplying an explicit language after system mode"
output="$(EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" "$script" epic-games-launcher --restore)"
assert_contains "$output" "Restored Epic Games Launcher interface language from cs to system." "runner should restore epic-games-launcher back to system mode"
assert_not_contains "$(cat "$epic_games_launcher_settings_file")" "Culture=" "epic-games-launcher restore should put the system-mode file back"

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

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all)"
assert_contains "$output" "Current Steam interface language: english" "all mode should read steam"
assert_contains "$output" "Current Anki interface language: en_US" "all mode should read anki"
assert_contains "$output" "Current Epic Games Launcher interface language: system" "all mode should read epic-games-launcher"
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

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" MACOS_APP_LANGUAGE_INHERIT=de-DE "$script" all --dry-run --inherit-macos)"
assert_contains "$output" "Would change Steam interface language from english to german." "all inherit should plan steam change"
assert_contains "$output" "Would change Anki interface language from en_US to de_DE." "all inherit should plan anki change"
assert_contains "$output" "Would change Epic Games Launcher interface language from system to de." "all inherit should plan epic-games-launcher change"
assert_contains "$output" "Would change Factorio interface language from en to de." "all inherit should plan factorio change"
assert_contains "$output" "Would change Wingspan interface language from English to Deutsch." "all inherit should plan wingspan change"
assert_contains "$output" "Would change Terraforming Mars interface language from English to German." "all inherit should plan terraforming-mars change"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all de)"
assert_contains "$output" "Changed Steam interface language from english to german." "all mode should change steam"
assert_contains "$output" "Changed Anki interface language from en_US to de_DE." "all mode should change anki"
assert_contains "$output" "Changed Epic Games Launcher interface language from system to de." "all mode should change epic-games-launcher"
assert_contains "$output" "Changed Factorio interface language from en to de." "all mode should change factorio"
assert_contains "$output" "Changed Wingspan interface language from English to Deutsch." "all mode should change wingspan"
assert_contains "$output" "Changed Terraforming Mars interface language from English to German." "all mode should change terraforming-mars"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all --restore)"
assert_contains "$output" "Restored Steam interface language from german to english." "all restore should revert steam"
assert_contains "$output" "Restored Anki interface language from de_DE to en_US." "all restore should revert anki"
assert_contains "$output" "Restored Epic Games Launcher interface language from de to system." "all restore should revert epic-games-launcher"
assert_contains "$output" "Restored Factorio interface language from de to en." "all restore should revert factorio"
assert_contains "$output" "Restored Wingspan interface language from Deutsch to English." "all restore should revert wingspan"
assert_contains "$output" "Restored Terraforming Mars interface language from German to English." "all restore should revert terraforming-mars"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all ja)"
assert_contains "$output" "Changed Steam interface language from english to japanese." "all mode should change steam for partially supported languages"
assert_contains "$output" "Changed Anki interface language from en_US to ja_JP." "all mode should change anki for partially supported languages"
assert_contains "$output" "Changed Epic Games Launcher interface language from system to ja." "all mode should change epic-games-launcher for partially supported languages"
assert_contains "$output" "Changed Factorio interface language from en to ja." "all mode should change factorio for partially supported languages"
assert_contains "$output" "Changed Wingspan interface language from English to 日本語." "all mode should change wingspan for partially supported languages"
assert_contains "$output" "Skipping Terraforming Mars: interface language ja is not supported." "all mode should skip unsupported modules"
assert_contains "$(plutil -p "$terraforming_mars_prefs_file")" '"I2 Language" => "English"' "unsupported modules should remain unchanged"

output="$(STEAM_DIR="$steam_dir" ANKI_BASE_DIR="$anki_dir" EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" FACTORIO_DIR="$factorio_dir" WINGSPAN_PREFERENCES_FILE="$wingspan_prefs_file" TERRAFORMING_MARS_PREFERENCES_FILE="$terraforming_mars_prefs_file" "$script" all --restore)"
assert_contains "$output" "Restored Steam interface language from japanese to english." "all restore should revert steam after partial bulk change"
assert_contains "$output" "Restored Anki interface language from ja_JP to en_US." "all restore should revert anki after partial bulk change"
assert_contains "$output" "Restored Epic Games Launcher interface language from ja to system." "all restore should revert epic-games-launcher after partial bulk change"
assert_contains "$output" "Restored Factorio interface language from ja to en." "all restore should revert factorio after partial bulk change"
assert_contains "$output" "Restored Wingspan interface language from 日本語 to English." "all restore should revert wingspan after partial bulk change"
assert_contains "$output" "Restored Terraforming Mars interface language from English to English." "all restore should keep terraforming-mars unchanged after partial bulk change"

echo "All tests passed."
