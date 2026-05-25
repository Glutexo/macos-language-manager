#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-languages.sh"

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

epic_games_launcher_preferences_dir="$tmp_dir/EpicGamesLauncher"
epic_games_launcher_process_match="$tmp_dir/EpicGamesLauncher-NotRunning"

stub_dir="$tmp_dir/stubs"
mkdir -p "$stub_dir"
renderable_languages_file="$tmp_dir/RenderableUILanguages.plist"
cat > "$renderable_languages_file" <<'EOS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <string>en</string>
  <string>az</string>
  <string>az-Cyrl</string>
  <string>az-Latn</string>
  <string>pt_BR</string>
  <string>tlh</string>
</array>
</plist>
EOS

cat > "$stub_dir/defaults" <<'EOS'
#!/bin/bash
set -euo pipefail

if [ "$#" -ge 3 ] && [ "$1" = "read" ] && [ "$2" = "-g" ] && [ "$3" = "AppleLanguages" ]; then
  cat <<'EOOUT'
(
    "en-US",
    "ko-KR",
    "fr-FR",
    "cs-CZ"
)
EOOUT
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "read" ] && [ "$2" = "-g" ] && [ "$3" = "AppleLocale" ]; then
  echo "cs_CZ"
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "read" ] && [ "$2" = "/Library/Preferences/.GlobalPreferences" ] && [ "$3" = "AppleLanguages" ]; then
  cat <<'EOOUT'
(
    "en-US",
    "ko-KR",
    "fr-FR",
    "cs-CZ"
)
EOOUT
  exit 0
fi

if [ "$#" -ge 3 ] && [ "$1" = "read" ] && [ "$2" = "/Library/Preferences/.GlobalPreferences" ] && [ "$3" = "AppleLocale" ]; then
  echo "cs_CZ"
  exit 0
fi

if [ "$#" -ge 2 ] && [ "$1" = "read" ] && [ "$2" = "com.apple.HIToolbox" ]; then
  cat <<'EOOUT'
(
    {
        "KeyboardLayout ID" = 252;
    }
)
EOOUT
  exit 0
fi

exit 1
EOS
chmod +x "$stub_dir/defaults"

cat > "$stub_dir/nvram" <<'EOS'
#!/bin/bash
set -euo pipefail

if [ "$#" -eq 1 ] && [ "$1" = "prev-lang:kbd" ]; then
  printf 'prev-lang:kbd\tko:252\n'
  exit 0
fi

exit 1
EOS
chmod +x "$stub_dir/nvram"

cat > "$stub_dir/plutil" <<'EOS'
#!/bin/bash
set -euo pipefail

if [ "$#" -eq 5 ] && [ "$1" = "-convert" ] && [ "$2" = "json" ] && [ "$3" = "-o" ] && [ "$4" = "-" ]; then
  cat <<'EOOUT'
["en","az","az-Cyrl","az-Latn","pt_BR","tlh"]
EOOUT
  exit 0
fi

if [ "$#" -eq 2 ] && [ "$1" = "-p" ]; then
  echo "nonstandard plutil output"
  exit 0
fi

exit 1
EOS
chmod +x "$stub_dir/plutil"

extract_languages() {
  awk '
    /^New language order:/ {capture=1; next}
    capture && /^  / {sub(/^  /, ""); print; next}
    capture && !/^  / {exit}
  '
}

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
  PATH="$stub_dir:$PATH" \
    STEAM_DIR="$steam_dir" \
    ANKI_BASE_DIR="$anki_dir" \
    EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" \
    EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" \
    FACTORIO_DIR="$factorio_dir" \
    MACOS_LANGUAGE_RENDERABLE_UI_LANGUAGES_PATH="$renderable_languages_file" \
    "$script" macos "$@"
}

run_everything_case() {
  PATH="$stub_dir:$PATH" \
    STEAM_DIR="$steam_dir" \
    ANKI_BASE_DIR="$anki_dir" \
    EPIC_GAMES_LAUNCHER_PREFERENCES_DIR="$epic_games_launcher_preferences_dir" \
    EPIC_GAMES_LAUNCHER_PROCESS_MATCH="$epic_games_launcher_process_match" \
    FACTORIO_DIR="$factorio_dir" \
    MACOS_LANGUAGE_RENDERABLE_UI_LANGUAGES_PATH="$renderable_languages_file" \
    "$script" everything "$@"
}

run_and_capture_order() {
  run_case account --dry-run "$@" | extract_languages | paste -sd',' -
}

output="$(run_case --help)"
assert_contains "$output" "Use --verbose or -v for supported language tags." "help should mention verbose help"
if [[ "$output" == *"Supported macOS language tags:"* ]]; then
  echo "FAIL: plain help should stay concise"
  exit 1
fi

output="$(run_case --verbose)"
assert_contains "$output" "Supported macOS language tags:" "verbose help should show supported language tags"
assert_contains "$output" "  en" "verbose help should include supported tags"
assert_contains "$output" "  az" "verbose help should include base Azerbaijani"
assert_contains "$output" "  az-Cyrl" "verbose help should include script variants from the renderable UI list"
assert_contains "$output" "  az-Latn" "verbose help should include additional script variants from the renderable UI list"
assert_contains "$output" "  pt-BR" "verbose help should normalize underscore tags"
assert_contains "$output" "  tlh" "verbose help should include renderable UI-only language tags"
assert_contains "$output" "Source: $renderable_languages_file" "verbose help should show the renderable UI source"
if [[ "$output" == *$'  Base
'* ]]; then
  echo "FAIL: verbose help should skip Base localization directories"
  exit 1
fi
if [[ "$output" == *"accepts missing tags such as ja or en-US"* ]]; then
  echo "FAIL: verbose help should not repeat notes about inserting missing tags"
  exit 1
fi

output="$(run_case all --dry-run -en ko:cs)"
assert_contains "$output" $'New language order:
  fr-FR
  ko-KR' "all target should move Korean behind French before locale derivation"
assert_contains "$output" $'New locale value:
  fr_FR' "all target should derive locale from the first resulting language"
assert_contains "$output" $'New startup language setting:
  fr:252' "all target should derive startup language from the first resulting language"

output="$(run_everything_case --dry-run de)"
assert_contains "$output" "Would change Steam interface language from english to german." "everything should include Steam app planning"
assert_contains "$output" "Would change Anki interface language from en_US to de_DE." "everything should include Anki app planning"
assert_contains "$output" "Would change Epic Games Launcher interface language from system to de." "everything should include Epic Games Launcher app planning"
assert_contains "$output" "Would change Factorio interface language from en to de." "everything should include Factorio app planning"
assert_contains "$output" $'New language order:
  de-CZ' "everything should include macOS all planning"
assert_contains "$output" "Dry run: no changes were saved." "everything should include macOS dry-run confirmation"

order="$(run_and_capture_order ja:cs)"
assert_eq "en-US,ko-KR,fr-FR,ja-CZ,cs-CZ" "$order" "ja:cs should place Japanese immediately before Czech"

order="$(run_and_capture_order +ja:cs)"
assert_eq "en-US,ko-KR,fr-FR,ja-CZ,cs-CZ" "$order" "+ja:cs should behave like ja:cs after leading plus normalization"

order="$(run_and_capture_order ja:pl)"
assert_eq "ja-CZ,pl-CZ,en-US,ko-KR,fr-FR,cs-CZ" "$order" "ja:pl should behave like explicit ja pl when the anchor is missing"

order="$(run_and_capture_order +ja:)"
assert_eq "en-US,ko-KR,fr-FR,cs-CZ,ja-CZ" "$order" "+ja: should behave like ja: after leading plus normalization"

order="$(run_and_capture_order ja:ko -ko)"
assert_eq "en-US,ja-CZ,fr-FR,cs-CZ" "$order" "ja:ko -ko should keep Japanese in Korean's former position"

order="$(run_and_capture_order -ko ja:ko)"
assert_eq "en-US,ja-CZ,fr-FR,cs-CZ" "$order" "-ko ja:ko should match ja:ko -ko"

order="$(run_and_capture_order ja ko: cs)"
assert_eq "ja-CZ,cs-CZ,en-US,fr-FR,ko-KR" "$order" "ja ko: cs should keep Korean at the end after Czech moves to the front section"

order="$(run_and_capture_order ja: ko:)"
assert_eq "en-US,fr-FR,cs-CZ,ja-CZ,ko-KR" "$order" "multiple end placements should preserve their argument order"

output="$(run_case locale --dry-run -ko 2>&1 || true)"
assert_contains "$output" "requires at least one added language argument" "locale target should reject remove-only commands"

output="$(run_case account --dry-run -ja:ko 2>&1 || true)"
assert_contains "$output" "Removal syntax does not support anchors" "removal syntax should reject anchors"

output="$(run_case account --dry-run '+-xx' 2>&1 || true)"
assert_contains "$output" "Invalid language value: +-xx" "+-xx should not be accepted as a valid language request"

output="$(run_case account --dry-run 'ja:-ko' 2>&1 || true)"
assert_contains "$output" "Invalid language value: ja:-ko" "anchored syntax should reject removal-style anchors"

output="$(run_case account --dry-run 'ja:+ko' 2>&1 || true)"
assert_contains "$output" "Invalid language value: ja:+ko" "anchored syntax should reject plus-prefixed anchors"

output="$(run_case account --dry-run '+ja:-ko' 2>&1 || true)"
assert_contains "$output" "Invalid language value: +ja:-ko" "plus-normalized anchored syntax should still reject removal-style anchors"

output="$(run_case account --dry-run '+ja:+ko' 2>&1 || true)"
assert_contains "$output" "Invalid language value: +ja:+ko" "plus-normalized anchored syntax should still reject plus-prefixed anchors"

echo "All tests passed."
