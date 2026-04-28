#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-macos-languages.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

stub_dir="$tmp_dir/stubs"
mkdir -p "$stub_dir"
lproj_root_one="$tmp_dir/SystemFolderLocalizations"
lproj_root_two="$tmp_dir/LanguageChooserResources"
mkdir -p "$lproj_root_one" "$lproj_root_two"
mkdir -p "$lproj_root_one/en.lproj" "$lproj_root_one/cs.lproj" "$lproj_root_one/zh_TW.lproj" "$lproj_root_one/Base.lproj"
mkdir -p "$lproj_root_two/pt_BR.lproj" "$lproj_root_two/ja.lproj" "$lproj_root_two/az.lproj"

catalog_file="$tmp_dir/DateTime-Locale-Catalog.pm"
cat > "$catalog_file" <<'EOS'
  az-Cyrl          Azerbaijani Cyrillic
  az-Latn          Azerbaijani Latin
  sr-Cyrl          Serbian Cyrillic
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
    MACOS_LANGUAGE_LPROJ_DIRS="$lproj_root_one:$lproj_root_two" \
    MACOS_LANGUAGE_CATALOG_PATH="$catalog_file" \
    "$script" "$@"
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
assert_contains "$output" "  az-Cyrl" "verbose help should include script variants from the locale catalog"
assert_contains "$output" "  az-Latn" "verbose help should include additional script variants from the locale catalog"
assert_contains "$output" "  pt-BR" "verbose help should normalize underscore tags"
if [[ "$output" == *$'  Base
'* ]]; then
  echo "FAIL: verbose help should skip Base localization directories"
  exit 1
fi
assert_contains "$output" "accepts missing tags such as ja or en-US" "verbose help should explain non-whitelist behavior"

output="$(run_case all --dry-run -en ko:cs)"
assert_contains "$output" $'New language order:
  fr-FR
  ko-KR' "all target should move Korean behind French before locale derivation"
assert_contains "$output" $'New locale value:
  fr_FR' "all target should derive locale from the first resulting language"
assert_contains "$output" $'New startup language setting:
  fr:252' "all target should derive startup language from the first resulting language"

order="$(run_and_capture_order ja:cs)"
assert_eq "en-US,ko-KR,fr-FR,ja-CZ,cs-CZ" "$order" "ja:cs should place Japanese immediately before Czech"

order="$(run_and_capture_order ja:pl)"
assert_eq "ja-CZ,pl-CZ,en-US,ko-KR,fr-FR,cs-CZ" "$order" "ja:pl should behave like explicit ja pl when the anchor is missing"

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

echo "All tests passed."
