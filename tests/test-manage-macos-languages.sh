#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/manage-macos-languages.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

stub_dir="$tmp_dir/stubs"
mkdir -p "$stub_dir"

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
  PATH="$stub_dir:$PATH" "$script" "$@"
}

run_and_capture_order() {
  run_case account --dry-run "$@" | extract_languages | paste -sd',' -
}

output="$(run_case --help)"
assert_contains "$output" "Use --verbose or -v for detected language tags." "help should mention verbose help"
if [[ "$output" == *"Detected macOS language tags:"* ]]; then
  echo "FAIL: plain help should stay concise"
  exit 1
fi

output="$(run_case --verbose)"
assert_contains "$output" "Detected macOS language tags:" "verbose help should show detected language tags"
assert_contains "$output" "  en-US" "verbose help should include detected tags"
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
assert_eq "en-US,fr-FR,ja-CZ,cs-CZ" "$order" "ja:ko -ko should keep Japanese in Korean's former position"

order="$(run_and_capture_order -ko ja:ko)"
assert_eq "en-US,fr-FR,ja-CZ,cs-CZ" "$order" "-ko ja:ko should match ja:ko -ko"

order="$(run_and_capture_order ja: ko: cs)"
assert_eq "ja-CZ,en-US,fr-FR,cs-CZ,ko-KR" "$order" "ja ko: cs should keep Korean at the end"

order="$(run_and_capture_order ja: ko:)"
assert_eq "en-US,fr-FR,cs-CZ,ja-CZ,ko-KR" "$order" "multiple end placements should preserve their argument order"

output="$(run_case locale --dry-run -ko 2>&1 || true)"
assert_contains "$output" "requires at least one added language argument" "locale target should reject remove-only commands"

output="$(run_case account --dry-run -ja:ko 2>&1 || true)"
assert_contains "$output" "Removal syntax does not support anchors" "removal syntax should reject anchors"

echo "All tests passed."
