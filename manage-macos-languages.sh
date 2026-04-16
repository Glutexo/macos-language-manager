#!/bin/bash
set -eo pipefail

display_command="./manage-macos-languages.sh"
target_mode=""

display_target_list() {
  echo "  account        Read or write the current account language order."
  echo "  login-window   Read or write the login window language order."
  echo "  locale         Read or write locale settings derived from the first language."
  echo "  all            Read or write account, login window, locale, and startup NVRAM settings."
}

show_usage() {
  echo "Manage the macOS preferred language list."
  echo "Move selected languages to the front and add missing ones when needed."
  echo
  echo "Usage: $display_command account [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command login-window [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command locale [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command all [--dry-run|-n] [--restart|-r] [language ...]"
  echo
  echo "Targets:"
  display_target_list
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the new values without saving changes."
  echo "  --restart, -r   Restart the Mac after evaluating the command."
  echo "  --help, -h      Show this help message."
  echo
  echo "Notes:"
  echo "  If you request a language that is not in the list yet, the script adds it."
  echo "  For short tags like 'ja', it also adds the system locale region when available."
  echo "  Example: with locale cs_CZ, 'ja' is added as 'ja-CZ'."
  echo "  The locale target derives AppleLocale from the first language, for example 'ja-CZ' -> 'ja_CZ'."
  echo "  The all target also updates NVRAM prev-lang:kbd for the startup screen."
  echo "  Writing login-window or system locale settings may prompt for administrator privileges."
  echo
  echo "Examples:"
  echo "  $display_command account"
  echo "  $display_command login-window"
  echo "  $display_command locale"
  echo "  $display_command all"
  echo "  $display_command account cs en"
  echo "  $display_command account --dry-run ko ja"
  echo "  $display_command login-window de ko"
  echo "  $display_command locale ja"
  echo "  $display_command all ja ko"
  echo "  $display_command account --restart ja ko"
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
  done <<EOREAD
$output
EOREAD
}

read_locale_value() {
  "$@" 2>/dev/null || true
}

set_target_mode() {
  case "$1" in
    account|login-window|locale|all)
      target_mode="$1"
      return 0
      ;;
  esac

  echo "Unknown target: $1"
  echo "Available targets:"
  display_target_list
  exit 1
}

should_use_account_languages() {
  [ "$target_mode" = "account" ] || [ "$target_mode" = "all" ]
}

should_use_login_window_languages() {
  [ "$target_mode" = "login-window" ] || [ "$target_mode" = "all" ]
}

should_use_locale_target() {
  [ "$target_mode" = "locale" ] || [ "$target_mode" = "all" ]
}

read_account_languages() {
  read_languages defaults read -g AppleLanguages
}

read_login_window_languages() {
  read_languages defaults read /Library/Preferences/.GlobalPreferences AppleLanguages
}

read_account_locale() {
  read_locale_value defaults read -g AppleLocale
}

read_system_locale() {
  read_locale_value defaults read /Library/Preferences/.GlobalPreferences AppleLocale
}

read_startup_language_value() {
  nvram prev-lang:kbd 2>/dev/null | awk -F'\t' 'NF {print $NF}'
}

read_selected_keyboard_layout_id() {
  defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null \
    | awk -F'= ' '/KeyboardLayout ID/ {gsub(/[^0-9-]/, "", $2); print $2; exit}'
}

startup_value_to_language_tag() {
  local startup_value="$1"
  local language_part=""

  [ -z "$startup_value" ] && return 1

  language_part="${startup_value%%:*}"
  [ -z "$language_part" ] && return 1

  printf '%s\n' "$language_part"
}

get_startup_keyboard_layout_id() {
  local startup_value=""
  local layout_id=""

  startup_value="$(read_startup_language_value)"
  if [ -n "$startup_value" ] && [ "$startup_value" != "${startup_value#*:}" ]; then
    layout_id="${startup_value#*:}"
    if [ -n "$layout_id" ]; then
      printf '%s\n' "$layout_id"
      return 0
    fi
  fi

  layout_id="$(read_selected_keyboard_layout_id)"
  if [ -n "$layout_id" ]; then
    printf '%s\n' "$layout_id"
    return 0
  fi

  return 1
}

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

locale_to_language_tag() {
  local locale_value="$1"
  local normalized=""

  [ -z "$locale_value" ] && return 1

  normalized="${locale_value%%.*}"
  normalized="${normalized%%@*}"
  normalized="${normalized//_/-}"

  if is_valid_configured_language "$normalized"; then
    printf '%s\n' "$normalized"
    return 0
  fi

  return 1
}

read_all_languages() {
  local merged_languages=()
  local language=""
  local locale_language=""

  while IFS= read -r language; do
    if [ -n "$language" ] && ! is_in_list "$language" "${merged_languages[@]}"; then
      merged_languages+=("$language")
    fi
  done <<EOACCOUNT
$(read_account_languages)
EOACCOUNT

  while IFS= read -r language; do
    if [ -n "$language" ] && ! is_in_list "$language" "${merged_languages[@]}"; then
      merged_languages+=("$language")
    fi
  done <<EOLOGIN
$(read_login_window_languages)
EOLOGIN

  locale_language="$(locale_to_language_tag "$(read_account_locale)" || true)"
  if [ -n "$locale_language" ] && ! is_in_list "$locale_language" "${merged_languages[@]}"; then
    merged_languages+=("$locale_language")
  fi

  locale_language="$(locale_to_language_tag "$(read_system_locale)" || true)"
  if [ -n "$locale_language" ] && ! is_in_list "$locale_language" "${merged_languages[@]}"; then
    merged_languages+=("$locale_language")
  fi

  locale_language="$(startup_value_to_language_tag "$(read_startup_language_value)" || true)"
  if [ -n "$locale_language" ]; then
    locale_language="$(build_missing_language_tag "$locale_language")"
  fi
  if [ -n "$locale_language" ] && ! is_in_list "$locale_language" "${merged_languages[@]}"; then
    merged_languages+=("$locale_language")
  fi

  printf '%s\n' "${merged_languages[@]}"
}

load_primary_languages() {
  if [ "$target_mode" = "all" ]; then
    read_all_languages
  elif should_use_login_window_languages && ! should_use_account_languages; then
    read_login_window_languages
  else
    read_account_languages
  fi
}

print_language_list() {
  local heading="$1"
  shift

  echo "$heading"
  if [ "$#" -gt 0 ]; then
    printf '  %s\n' "$@"
  else
    echo "  unavailable"
  fi
}

print_locale_value() {
  local heading="$1"
  local value="$2"

  echo "$heading"
  if [ -n "$value" ]; then
    echo "  $value"
  else
    echo "  unavailable"
  fi
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

  locale_value="$(read_account_locale)"
  if [ -n "$locale_value" ]; then
    region="$(extract_locale_region "$locale_value" || true)"
    if [ -n "$region" ]; then
      printf '%s\n' "$region"
      return 0
    fi
  fi

  locale_value="$(read_system_locale)"
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

build_locale_value() {
  local language="$1"
  local normalized=""

  normalized="$(build_missing_language_tag "$language")"
  printf '%s\n' "${normalized//-/_}"
}

build_startup_language_value() {
  local language="$1"
  local normalized=""
  local language_code=""
  local layout_id=""

  normalized="$(build_missing_language_tag "$language")"
  language_code="${normalized%%-*}"
  [ -z "$language_code" ] && language_code="$normalized"
  layout_id="$(get_startup_keyboard_layout_id || true)"

  if [ -n "$layout_id" ]; then
    printf '%s:%s\n' "$language_code" "$layout_id"
  else
    printf '%s\n' "$language_code"
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

while [ "$#" -gt 0 ]; do
  if [ "$target_set" = false ]; then
    case "$1" in
      --help|-h)
        show_usage
        exit 0
        ;;
      --*|-*)
        echo "The first argument must be a target: account, login-window, locale, or all."
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
done <<EOLOAD
$(load_primary_languages)
EOLOAD

if ! should_use_locale_target && [ "${#current_languages[@]}" -eq 0 ]; then
  echo "Failed to read language settings."
  exit 1
fi

if [ "${#requested_languages[@]}" -lt 1 ]; then
  if [ "$dry_run" = true ] || [ "$restart_after_change" = true ]; then
    show_usage
    exit 1
  fi

  case "$target_mode" in
    account)
      print_language_list "Current account language order:" "${current_languages[@]}"
      ;;
    login-window)
      print_language_list "Current login window language order:" "${current_languages[@]}"
      ;;
    locale)
      print_locale_value "Current account locale:" "$(read_account_locale)"
      echo
      print_locale_value "Current system locale:" "$(read_system_locale)"
      ;;
    all)
      account_languages=()
      while IFS= read -r language; do
        account_languages+=("$language")
      done <<EOACCOUNT
$(read_account_languages)
EOACCOUNT
      login_window_languages=()
      while IFS= read -r language; do
        login_window_languages+=("$language")
      done <<EOLOGIN
$(read_login_window_languages)
EOLOGIN
      print_language_list "Current merged language order:" "${current_languages[@]}"
      echo
      print_language_list "Current account language order:" "${account_languages[@]}"
      echo
      print_language_list "Current login window language order:" "${login_window_languages[@]}"
      echo
      print_locale_value "Current account locale:" "$(read_account_locale)"
      echo
      print_locale_value "Current system locale:" "$(read_system_locale)"
      echo
      print_locale_value "Current startup language setting:" "$(read_startup_language_value)"
      ;;
  esac

  exit 0
fi

result=()

if should_use_account_languages || should_use_login_window_languages; then
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
fi

new_locale="$(build_locale_value "${requested_languages[0]}")"
if should_use_locale_target; then
  echo "New locale value:"
  echo "  $new_locale"
  echo
fi

new_startup_value="$(build_startup_language_value "${requested_languages[0]}")"
if [ "$target_mode" = "all" ]; then
  echo "New startup language setting:"
  echo "  $new_startup_value"
  echo
fi

if [ "$dry_run" = true ]; then
  echo "Dry run: no changes were saved."
else
  if should_use_account_languages; then
    echo "Applying language order to the current account."
    defaults write -g AppleLanguages -array "${result[@]}"
  fi

  if should_use_login_window_languages; then
    echo "Applying language order to the login window."
    run_privileged defaults write /Library/Preferences/.GlobalPreferences AppleLanguages -array "${result[@]}"
    echo "Refreshing APFS preboot data."
    run_preboot_refresh
  fi

  if should_use_locale_target; then
    echo "Applying locale to the current account."
    defaults write -g AppleLocale "$new_locale"
    echo "Applying locale to the system."
    run_privileged defaults write /Library/Preferences/.GlobalPreferences AppleLocale "$new_locale"
  fi

  if [ "$target_mode" = "all" ]; then
    echo "Applying startup language setting."
    run_privileged nvram "prev-lang:kbd=$new_startup_value"
    echo "Syncing NVRAM."
    run_privileged nvram -s
  fi
fi

if [ "$restart_after_change" = true ]; then
  echo "Restarting the Mac."
  osascript -e 'tell application "System Events" to restart'
elif [ "$dry_run" != true ]; then
  echo "The change usually takes full effect after logging out and back in."
fi
