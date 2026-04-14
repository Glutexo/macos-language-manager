#!/bin/bash
set -eo pipefail

show_usage() {
  echo "Použití: $0 [--dry-run] jazyk [jazyk...]"
  echo "Příklad: $0 cs en"
  echo "Příklad: $0 --dry-run ko ja"
}

dry_run=false

if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi

if [ "$#" -lt 1 ]; then
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
  echo "Nepodařilo se načíst AppleLanguages."
  exit 1
fi

requested_languages=("$@")
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

  if [ "$found_match" = false ] && ! is_in_list "$requested" "${result[@]}"; then
    result+=("$requested")
  fi
done

for lang in "${current_languages[@]}"; do
  if ! is_in_list "$lang" "${result[@]}"; then
    result+=("$lang")
  fi
done

echo "Nové pořadí jazyků:"
printf '  %s\n' "${result[@]}"
echo

if [ "$dry_run" = true ]; then
  echo "Dry run: změna nebyla zapsána."
else
  defaults write -g AppleLanguages -array "${result[@]}"
  echo "Změna se obvykle plně projeví po odhlášení a novém přihlášení."
fi
