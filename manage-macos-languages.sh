#!/bin/bash
set -eo pipefail

display_command="./manage-macos-languages.sh"
target_mode=""

show_usage() {
  echo "Manage the macOS preferred language list."
  echo "Move selected languages to the front and add missing ones when needed."
  echo
  echo "Usage: $display_command account [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command login-window [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command both [--dry-run|-n] [--restart|-r] [language ...]"
  echo
  echo "Targets:"
  echo "  account        Read or write the current account language order."
  echo "  login-window   Read or write the login window language order."
  echo "  both           Read or write both account and login window language order."
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the new language order without saving changes."
  echo "  --restart, -r   Restart the Mac after evaluating the command."
  echo "  --help, -h      Show this help message."
  echo
  echo "Notes:"
  echo "  If you request a language that is not in the list yet, the script adds it."
  echo "  For short tags like 'ja', it also adds the system locale region when available."
  echo "  Example: with locale cs_CZ, 'ja' is added as 'ja-CZ'."
  echo "  Writing to the login window may prompt for administrator privileges."
  echo
  echo "Examples:"
  echo "  $display_command account"
  echo "  $display_command login-window"
  echo "  $display_command both"
  echo "  $display_command account cs en"
  echo "  $display_command account --dry-run ko ja"
  echo "  $display_command account -n ko ja"
  echo "  $display_command account --restart ja ko"
  echo "  $display_command login-window de ko"
  echo "  $display_command both de ko"
  echo "  $display_command account -r ja ko"
  echo "  $display_command --help"
}

dry_run=false
restart_after_change=false
requested_languages=()
parse_options=true
target_set=false

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_preboot_refresh() {
  local temp_output=""

  temp_output="$(mktemp)"
  if run_privileged diskutil apfs updatePreboot / >"$temp_output" 2>&1; then
    rm -f "$temp_output"
    return 0
  fi

  echo "Failed to refresh APFS preboot data."
  cat "$temp_output"
  rm -f "$temp_output"
  return 1
}

is_valid_configured_language() {
  local language="$1"

  case "$language" in
    [A-Za-z]*)
      return 0
      ;;
  esac

  return 1
}

read_languages() {
  local output=""
  local language=""

  output="$("$@" 2>/dev/null || true)"
  if [ -z "$output" ]; then
    return 1
  fi

  while IFS= read -r language; do
    language="${language//[()\", ]/}"
    if [ -n "$language" ] && is_valid_configured_language "$language"; then
      printf '%s\n' "$language"
    fi
  done <<EOF
$output
EOF
}

set_target_mode() {
  case "$1" in
    account|login-window|both)
      target_mode="$1"
      return 0
      ;;
  esac

  echo "Unknown target: $1"
  show_usage
  exit 1
}

should_use_account_target() {
  [ "$target_mode" = "account" ] || [ "$target_mode" = "both" ]
}

should_use_login_window_target() {
  [ "$target_mode" = "login-window" ] || [ "$target_mode" = "both" ]
}

read_account_languages() {
  read_languages defaults read -g AppleLanguages
}

read_login_window_languages() {
  read_languages defaults read /Library/Preferences/.GlobalPreferences AppleLanguages
}

load_primary_languages() {
  if should_use_login_window_target && ! should_use_account_target; then
    read_login_window_languages
  else
    read_account_languages
  fi
}

while [ "$#" -gt 0 ]; do
  if [ "$target_set" = false ]; then
    case "$1" in
      --help|-h)
        show_usage
        exit 0
        ;;
      --*)
        echo "The first argument must be a target: account, login-window, or both."
        show_usage
        exit 1
        ;;
      -*)
        echo "The first argument must be a target: account, login-window, or both."
        show_usage
        exit 1
        ;;
      *)
        set_target_mode "$1"
        target_set=true
        shift
        continue
        ;;
    esac
  fi

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

current_languages=()
while IFS= read -r language; do
  current_languages+=("$language")
done <<EOF
$(load_primary_languages)
EOF

if [ "${#current_languages[@]}" -eq 0 ]; then
  echo "Failed to read language settings."
  exit 1
fi

if [ "${#requested_languages[@]}" -lt 1 ]; then
  if [ "$dry_run" = true ] || [ "$restart_after_change" = true ]; then
    show_usage
    exit 1
  fi

  if [ "$target_mode" = "login-window" ]; then
    echo "Current login window language order:"
  elif [ "$target_mode" = "both" ]; then
    echo "Current account language order:"
  else
    echo "Current account language order:"
  fi
  printf '  %s\n' "${current_languages[@]}"

  if [ "$target_mode" = "both" ]; then
    login_window_languages=()
    while IFS= read -r language; do
      login_window_languages+=("$language")
    done <<EOF
$(read_login_window_languages)
EOF

    echo
    echo "Current login window language order:"
    if [ "${#login_window_languages[@]}" -gt 0 ]; then
      printf '  %s\n' "${login_window_languages[@]}"
    else
      echo "  unavailable"
    fi
  fi

  exit 0
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
  if should_use_account_target; then
    echo "Applying language order to the current account."
    defaults write -g AppleLanguages -array "${result[@]}"
  fi

  if should_use_login_window_target; then
    echo "Applying language order to the login window."
    run_privileged defaults write /Library/Preferences/.GlobalPreferences AppleLanguages -array "${result[@]}"
    echo "Refreshing APFS preboot data."
    run_preboot_refresh
  fi
fi

if [ "$restart_after_change" = true ]; then
  echo "Restarting the Mac."
  osascript -e 'tell application "System Events" to restart'
elif [ "$dry_run" != true ]; then
  echo "The change usually takes full effect after logging out and back in."
fi
