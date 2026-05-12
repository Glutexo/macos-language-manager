#!/bin/bash
set -euo pipefail

display_command="./manage-factorio-language.sh"
factorio_dir="${FACTORIO_DIR:-$HOME/Library/Application Support/factorio}"
config_file="$factorio_dir/config/config.ini"
dry_run=false
force_write=false
verbose_help=false
show_help=false
supported_languages=(
  af
  ar
  be
  bg
  ca
  cs
  da
  de
  el
  en
  eo
  es-ES
  et
  eu
  fa
  fi
  fil
  fr
  fy-NL
  ga-IE
  he
  hr
  hu
  id
  is
  it
  ja
  ka
  kk
  ko
  lt
  lv
  nl
  no
  pl
  pt-BR
  pt-PT
  ro
  ru
  sk
  sl
  sq
  sr
  sv-SE
  th
  tr
  uk
  vi
  zh-CN
  zh-TW
)

show_usage() {
  echo "Read or change the Factorio interface language on macOS."
  echo
  echo "Usage: $display_command [--dry-run|-n] [--force|-f] [language]"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned change without writing it."
  echo "  --force, -f     Write even if Factorio appears to be running."
  echo "  --help, -h      Show this help message. Use --verbose or -v for the supported language list."
  echo "  --verbose, -v   Show help together with supported language values."
  echo
  echo "Examples:"
  echo "  $display_command"
  echo "  $display_command cs"
  echo "  $display_command --dry-run zh-CN"

  if $verbose_help; then
    echo
    echo "Supported Factorio interface language values:"
    printf '  %s\n' "${supported_languages[@]}"
    echo
    echo "Short aliases such as es, ga, fy, pt, sv, or zh are also accepted when they map to one supported value."
  fi
}

fail() {
  echo "$1" >&2
  exit 1
}

ensure_config_exists() {
  [ -f "$config_file" ] || fail "Factorio config file not found: $config_file"
}

canonicalize_language() {
  local language="$1"
  local normalized_language=""
  local supported_language=""

  case "$language" in
    [A-Za-z][A-Za-z_-]*)
      ;;
    *)
      fail "Invalid Factorio language value: $language"
      ;;
  esac

  normalized_language="${language//_/-}"
  normalized_language="$(printf '%s' "$normalized_language" | tr '[:upper:]' '[:lower:]')"

  case "$normalized_language" in
    es|es-es) normalized_language="es-ES" ;;
    fy|fy-nl) normalized_language="fy-NL" ;;
    ga|ga-ie) normalized_language="ga-IE" ;;
    pt|pt-pt) normalized_language="pt-PT" ;;
    pt-br) normalized_language="pt-BR" ;;
    sv|sv-se) normalized_language="sv-SE" ;;
    zh|zh-cn) normalized_language="zh-CN" ;;
    zh-tw) normalized_language="zh-TW" ;;
    *)
      if [[ "$normalized_language" == *-* ]]; then
        local language_part="${normalized_language%%-*}"
        local region_part="${normalized_language#*-}"
        normalized_language="${language_part}-$(printf '%s' "$region_part" | tr '[:lower:]' '[:upper:]')"
      fi
      ;;
  esac

  for supported_language in "${supported_languages[@]}"; do
    if [ "$normalized_language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Factorio interface language: $1"
}

is_factorio_running() {
  pgrep -x factorio >/dev/null 2>&1 || pgrep -x Factorio >/dev/null 2>&1
}

read_current_language() {
  awk '
    BEGIN { in_general = 0 }
    /^[[:space:]]*;/ { next }
    /^[[:space:]]*\[/ {
      in_general = ($0 ~ /^[[:space:]]*\[general\][[:space:]]*$/)
      next
    }
    in_general && /^[[:space:]]*locale[[:space:]]*=/ {
      sub(/^[[:space:]]*locale[[:space:]]*=[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$config_file"
}

write_language() {
  CONFIG_FILE="$config_file" REQUESTED_LANGUAGE="$1" python3 - <<'PY'
import os
import re
import sys

path = os.environ["CONFIG_FILE"]
language = os.environ["REQUESTED_LANGUAGE"]

with open(path, "r", encoding="utf-8") as handle:
    content = handle.read()

pattern = re.compile(r"(^\s*\[general\]\s*$)(.*?)(?=^\s*\[|\Z)", re.MULTILINE | re.DOTALL)
match = pattern.search(content)
if not match:
    print(f"Could not find the [general] section in {path}", file=sys.stderr)
    sys.exit(1)

section_body = match.group(2)
updated_body, replacements = re.subn(
    r"^(\s*locale\s*=\s*).*$",
    rf"\1{language}",
    section_body,
    count=1,
    flags=re.MULTILINE,
)

if replacements == 0:
    if updated_body and not updated_body.endswith("\n"):
        updated_body += "\n"
    updated_body = f"locale={language}\n" + updated_body

updated_content = content[: match.start(2)] + updated_body + content[match.end(2) :]

with open(path, "w", encoding="utf-8") as handle:
    handle.write(updated_content)
PY
}

requested_language=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-n)
      dry_run=true
      ;;
    --force|-f)
      force_write=true
      ;;
    --help|-h)
      show_help=true
      ;;
    --verbose|-v)
      verbose_help=true
      ;;
    -*)
      fail "Unknown option: $1"
      ;;
    *)
      if [ -n "$requested_language" ]; then
        fail "Only one language value can be provided."
      fi
      requested_language="$1"
      ;;
  esac
  shift
done

if $show_help || $verbose_help; then
  show_usage
  exit 0
fi

ensure_config_exists
current_language="$(read_current_language)"

if [ -z "$requested_language" ]; then
  [ -n "$current_language" ] || fail "Could not detect the current Factorio language in $config_file"
  echo "Current Factorio interface language: $current_language"
  exit 0
fi

requested_language="$(canonicalize_language "$requested_language")"
display_current_language="${current_language:-unset}"

if [ "$requested_language" = "$current_language" ]; then
  echo "Factorio interface language is already set to $requested_language."
  exit 0
fi

if ! $dry_run && ! $force_write && is_factorio_running; then
  fail "Factorio appears to be running. Quit Factorio first, or rerun with --force."
fi

if $dry_run; then
  echo "Would change Factorio interface language from $display_current_language to $requested_language."
  exit 0
fi

backup_file="$config_file.bak"
cp "$config_file" "$backup_file"
write_language "$requested_language"

echo "Changed Factorio interface language from $display_current_language to $requested_language."
echo "Backup saved to $backup_file"
echo "Restart Factorio to apply the new interface language."
