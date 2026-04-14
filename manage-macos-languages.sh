#!/bin/bash
set -eo pipefail

show_usage() {
  echo "Usage: $0 [--dry-run|-n] [--restart|-r] language [language...]"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the new language order without saving changes."
  echo "  --restart, -r   Restart the Mac after evaluating the command."
  echo "  --help, -h      Show this help message."
  echo
  echo "Notes:"
  echo "  Options can appear before or after the language arguments."
  echo "  A missing base language can inherit its region from the system locale."
  echo
  echo "Examples:"
  echo "  $0 cs en"
  echo "  $0 --dry-run ko ja"
  echo "  $0 -n ko ja"
  echo "  $0 --restart ja ko"
  echo "  $0 -r ja ko"
  echo "  $0 --help"
}

dry_run=false
restart_after_change=false
requested_languages=()
parse_options=true

while [ "$#" -gt 0 ]; do
  if [ "$parse_options" = true ]; then
    case "$1" in
      --dry-run|-n)
        dry_run=true
        shift
        continue
        ;;
      --restart|-r)
        restart_after_change=true
        shift
        continue
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      --)
        parse_options=false
        shift
        continue
        ;;
      -*)
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  fi

  requested_languages+=("$1")
  shift
done

if [ "${#requested_languages[@]}" -lt 1 ]; then
  show_usage
  exit 1
fi

tmp_languages_file="$(mktemp)"
trap 'rm -f "$tmp_languages_file"' EXIT

defaults read -g AppleLanguages 2>/dev/null \
  | tr -d '()",'\'' ' \
  | sed '/^$/d' > "$tmp_languages_file"

current_languages=()
while IFS= read -r language; do
  current_languages+=("$language")
done < "$tmp_languages_file"

if [ "${#current_languages[@]}" -eq 0 ]; then
  echo "Failed to read AppleLanguages."
  exit 1
fi

result=()

is_in_list() {
  local needle="$1"
  shift

  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done

  return 1
}

extract_locale_region() {
  local locale_value="$1"
  local normalized=""
  local region_part=""
  local first_subtag=""

  normalized="${locale_value%%.*}"
  normalized="${normalized%%@*}"
  normalized="${normalized//_/-}"
  region_part="${normalized#*-}"

  if [ "$region_part" = "$normalized" ] || [ -z "$region_part" ]; then
    return 1
  fi

  first_subtag="${region_part%%-*}"
  case "${#first_subtag}" in
    2|3)
      printf '%s\n' "$first_subtag" | tr '[:lower:]' '[:upper:]'
      return 0
      ;;
  esac

  return 1
}

get_system_locale_region() {
  local locale_value=""
  local region=""

  locale_value="$(defaults read -g AppleLocale 2>/dev/null || true)"
  if [ -n "$locale_value" ]; then
    region="$(extract_locale_region "$locale_value" || true)"
    if [ -n "$region" ]; then
      printf '%s\n' "$region"
      return 0
    fi
  fi

  for locale_value in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
    if [ -n "$locale_value" ]; then
      region="$(extract_locale_region "$locale_value" || true)"
      if [ -n "$region" ]; then
        printf '%s\n' "$region"
        return 0
      fi
    fi
  done

  return 1
}

build_missing_language_tag() {
  local requested="$1"
  local region=""

  case "$requested" in
    *-*)
      printf '%s\n' "$requested"
      return 0
      ;;
  esac

  region="$(get_system_locale_region || true)"
  if [ -n "$region" ]; then
    printf '%s-%s\n' "$requested" "$region"
  else
    printf '%s\n' "$requested"
  fi
}

matches_requested_language() {
  local requested="$1"
  local language="$2"
  local suffix=""
  local first_subtag=""

  if [ "$language" = "$requested" ]; then
    return 0
  fi

  case "$requested" in
    *-*)
      case "$language" in
        "$requested"-*) return 0 ;;
      esac
      ;;
    *)
      case "$language" in
        "$requested"-*)
          suffix="${language#"$requested"-}"
          first_subtag="${suffix%%-*}"
          case "${#first_subtag}" in
            2|3) return 0 ;;
          esac
          ;;
      esac
      ;;
  esac

  return 1
}

for requested in "${requested_languages[@]}"; do
  found_match=false

  for lang in "${current_languages[@]}"; do
    if matches_requested_language "$requested" "$lang"; then
      found_match=true
      if ! is_in_list "$lang" "${result[@]}"; then
        result+=("$lang")
      fi
      break
    fi
  done

  if [ "$found_match" = false ]; then
    missing_language="$(build_missing_language_tag "$requested")"
    if ! is_in_list "$missing_language" "${result[@]}"; then
      result+=("$missing_language")
    fi
  fi
done

for lang in "${current_languages[@]}"; do
  if ! is_in_list "$lang" "${result[@]}"; then
    result+=("$lang")
  fi
done

echo "New language order:"
printf '  %s\n' "${result[@]}"
echo

if [ "$dry_run" = true ]; then
  echo "Dry run: no changes were saved."
else
  defaults write -g AppleLanguages -array "${result[@]}"
fi

if [ "$restart_after_change" = true ]; then
  echo "Restarting the Mac."
  osascript -e 'tell application "System Events" to restart'
elif [ "$dry_run" != true ]; then
  echo "The change usually takes full effect after logging out and back in."
fi
