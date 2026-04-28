#!/bin/bash
set -eo pipefail

display_command="./manage-macos-languages.sh"
target_mode=""
verbose_help=false

display_target_list() {
  echo "  account        Read or write the current account language order."
  echo "  login-window   Read or write the login window language order."
  echo "  locale         Read or write locale settings derived from the first language."
  echo "  startup        Read or write startup NVRAM language settings."
  echo "  all            Read or write account, login window, locale, and startup NVRAM settings."
}

show_usage() {
  echo "Manage the macOS preferred language list."
  echo "Move selected languages to the front, place them before another language or at the end, add missing ones, and remove entries when requested."
  echo
  echo "Usage: $display_command account [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command login-window [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command locale [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command startup [--dry-run|-n] [--restart|-r] [language ...]"
  echo "       $display_command all [--dry-run|-n] [--restart|-r] [language ...]"
  echo
  echo "Targets:"
  display_target_list
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the new values without saving changes."
  echo "  --restart, -r   Restart the Mac after evaluating the command."
  echo "  --help, -h      Show this help message. Use --verbose or -v for supported language tags."
  echo "  --verbose, -v   Show help together with supported macOS language tags."
  echo
  echo "Language arguments:"
  echo "  xx        Move or add the language at the front."
  echo "  +xx       Move or add the language at the front."
  echo "  -xx       Remove matching language entries."
  echo "  xx:yy     Move or add xx immediately before yy."
  echo "  xx:       Move or add xx at the end of the list."
  echo
  echo "Notes:"
  echo "  If you request a language that is not in the list yet, the script adds it."
  echo "  For short tags like 'ja', it also adds the system locale region when available."
  echo "  Example: with locale cs_CZ, 'ja' is added as 'ja-CZ'."
  echo "  A missing anchor in xx:yy is treated like an implicit request for yy, so xx:yy behaves like xx yy."
  echo "  The locale target derives AppleLocale from the first added language, for example 'ja-CZ' -> 'ja_CZ'."
  echo "  The all target also updates NVRAM prev-lang:kbd for the startup screen."
  echo "  Writing login-window, startup, or system locale settings may prompt for administrator privileges."
  echo
  echo "Examples:"
  echo "  $display_command account"
  echo "  $display_command login-window"
  echo "  $display_command locale"
  echo "  $display_command startup"
  echo "  $display_command all"
  echo "  $display_command account cs en"
  echo "  $display_command account --dry-run +ko ja -en"
  echo "  $display_command account --dry-run ja:cs"
  echo "  $display_command account --dry-run ja:ko -ko"
  echo "  $display_command account --dry-run ja ko: cs"
  echo "  $display_command login-window de ko"
  echo "  $display_command locale ja"
  echo "  $display_command startup ja"
  echo "  $display_command all ja ko -en"
  echo "  $display_command account --restart ja ko"
  echo "  $display_command --help"

  if $verbose_help; then
    echo
    print_verbose_help_languages
  fi
}

dry_run=false
restart_after_change=false
requested_languages=()
removed_languages=()
operation_kinds=()
operation_sources=()
operation_anchors=()
parse_options=true
target_set=false

entity_languages=()
entity_base_indexes=()
entity_parents=()
entity_root_sections=()
entity_orders=()
resolved_entity_index=""

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
    account|login-window|locale|startup|all)
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

should_use_startup_target() {
  [ "$target_mode" = "startup" ] || [ "$target_mode" = "all" ]
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

print_verbose_help_languages() {
  local search_paths="${MACOS_LANGUAGE_LPROJ_DIRS:-/System/Library}"
  local languages=()
  local language=""
  local search_path=""

  IFS=':' read -r -a verbose_language_paths <<< "$search_paths"
  for search_path in "${verbose_language_paths[@]}"; do
    [ -d "$search_path" ] || continue

    while IFS= read -r language; do
      language="${language%.lproj}"
      language="${language//_/-}"
      case "$language" in
        Base|English|French|German|Italian|Japanese|Spanish|Dutch)
          continue
          ;;
      esac
      if [ -n "$language" ] && is_valid_configured_language "$language" && ! is_in_list "$language" "${languages[@]}"; then
        languages+=("$language")
      fi
    done <<EOLANGS
$(find "$search_path" -maxdepth 4 -type d -name '*.lproj' -exec basename {} \; | sort -u)
EOLANGS
  done

  echo "Supported macOS language tags:"
  if [ "${#languages[@]}" -gt 0 ]; then
    printf '  %s\n' "${languages[@]}"
  else
    echo "  unavailable"
  fi
  echo "  The script also accepts missing tags such as ja or en-US and inserts them when needed."
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
  elif [ "$target_mode" = "startup" ]; then
    startup_value_to_language_tag "$(read_startup_language_value)" || true
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

parse_language_argument() {
  local token="$1"
  local normalized_token="$token"
  local source=""
  local anchor=""

  case "$normalized_token" in
    +*)
      normalized_token="${normalized_token#+}"
      ;;
  esac

  case "$normalized_token" in
    -* )
      source="${normalized_token#-}"
      if [[ "$source" == *:* ]]; then
        echo "Removal syntax does not support anchors: $token"
        exit 1
      fi
      if ! is_valid_configured_language "$source"; then
        echo "Invalid language value: $token"
        exit 1
      fi
      removed_languages+=("$source")
      return 0
      ;;
  esac

  if [[ "$normalized_token" == *:* ]]; then
    source="${normalized_token%%:*}"
    anchor="${normalized_token#*:}"
    if [ -z "$source" ]; then
      echo "Invalid language value: $token"
      exit 1
    fi
    if ! is_valid_configured_language "$source"; then
      echo "Invalid language value: $token"
      exit 1
    fi
    if [ -n "$anchor" ] && ! is_valid_configured_language "$anchor"; then
      echo "Invalid language value: $token"
      exit 1
    fi

    if [ -n "$anchor" ]; then
      operation_kinds+=("before")
      operation_sources+=("$source")
      operation_anchors+=("$anchor")
    else
      operation_kinds+=("end")
      operation_sources+=("$source")
      operation_anchors+=("")
    fi
    requested_languages+=("$source")
    return 0
  fi

  if ! is_valid_configured_language "$normalized_token"; then
    echo "Invalid language value: $token"
    exit 1
  fi

  operation_kinds+=("front")
  operation_sources+=("$normalized_token")
  operation_anchors+=("")
  requested_languages+=("$normalized_token")
}

find_matching_entity() {
  local requested="$1"
  local index=0

  resolved_entity_index=""

  while [ "$index" -lt "${#entity_languages[@]}" ]; do
    if matches_requested_language "$requested" "${entity_languages[$index]}"; then
      resolved_entity_index="$index"
      return 0
    fi
    index=$((index + 1))
  done

  return 1
}

create_entity() {
  local language="$1"
  local base_index="$2"
  local root_section="$3"
  local order="$4"
  local new_index="${#entity_languages[@]}"

  entity_languages+=("$language")
  entity_base_indexes+=("$base_index")
  entity_parents+=(-1)
  entity_root_sections+=("$root_section")
  entity_orders+=("$order")
  resolved_entity_index="$new_index"
}

ensure_entity() {
  local requested="$1"
  local default_section="$2"
  local default_order="$3"
  local created_language=""

  if find_matching_entity "$requested"; then
    return 0
  fi

  created_language="$(build_missing_language_tag "$requested")"
  create_entity "$created_language" -1 "$default_section" "$default_order"
}

is_ancestor_entity() {
  local potential_ancestor="$1"
  local entity_index="$2"
  local parent_index=""

  parent_index="${entity_parents[$entity_index]}"
  while [ "$parent_index" -ge 0 ]; do
    if [ "$parent_index" -eq "$potential_ancestor" ]; then
      return 0
    fi
    parent_index="${entity_parents[$parent_index]}"
  done

  return 1
}

set_entity_root() {
  local entity_index="$1"
  local root_section="$2"
  local order="$3"

  entity_parents[$entity_index]=-1
  entity_root_sections[$entity_index]="$root_section"
  entity_orders[$entity_index]="$order"
}

set_entity_parent() {
  local entity_index="$1"
  local parent_index="$2"
  local order="$3"

  if [ "$entity_index" -eq "$parent_index" ]; then
    echo "A language cannot be placed relative to itself: ${entity_languages[$entity_index]}"
    exit 1
  fi

  if is_ancestor_entity "$entity_index" "$parent_index"; then
    echo "Cannot create a placement cycle involving ${entity_languages[$entity_index]} and ${entity_languages[$parent_index]}."
    exit 1
  fi

  entity_parents[$entity_index]="$parent_index"
  entity_orders[$entity_index]="$order"
}

get_sorted_entity_ids() {
  local mode="$1"
  local needle="$2"
  local index=0
  local sort_key=""

  while [ "$index" -lt "${#entity_languages[@]}" ]; do
    if [ "$mode" = "root" ]; then
      if [ "${entity_parents[$index]}" -eq -1 ] && [ "${entity_root_sections[$index]}" = "$needle" ]; then
        if [ "$needle" = "base" ]; then
          sort_key="${entity_base_indexes[$index]}"
        else
          sort_key="${entity_orders[$index]}"
        fi
        printf '%012d:%s\n' "$sort_key" "$index"
      fi
    else
      if [ "${entity_parents[$index]}" -eq "$needle" ]; then
        sort_key="${entity_orders[$index]}"
        printf '%012d:%s\n' "$sort_key" "$index"
      fi
    fi
    index=$((index + 1))
  done | sort -n | cut -d: -f2
}

ordered_languages=()

append_flattened_entity() {
  local entity_index="$1"
  local child_index=""

  while IFS= read -r child_index; do
    if [ -n "$child_index" ]; then
      append_flattened_entity "$child_index"
    fi
  done <<EOCHILDREN
$(get_sorted_entity_ids child "$entity_index")
EOCHILDREN

  ordered_languages+=("${entity_languages[$entity_index]}")
}

build_ordered_languages() {
  local root_index=""

  ordered_languages=()

  for section in front base end; do
    while IFS= read -r root_index; do
      if [ -n "$root_index" ]; then
        append_flattened_entity "$root_index"
      fi
    done <<EOROOTS
$(get_sorted_entity_ids root "$section")
EOROOTS
  done
}

should_remove_language() {
  local language="$1"
  local removed=""

  for removed in "${removed_languages[@]}"; do
    if matches_requested_language "$removed" "$language"; then
      return 0
    fi
  done

  return 1
}

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
      --verbose|-v)
        verbose_help=true
        show_usage
        exit 0
        ;;
      --)
        parse_options=false
        shift
        continue
        ;;
      -* )
        if [ "$target_set" = true ]; then
          parse_language_argument "$1"
          shift
          continue
        fi
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  fi

  if [ "$target_set" = false ]; then
    set_target_mode "$1"
    target_set=true
    shift
    continue
  fi

  parse_language_argument "$1"
  shift
done

if [ "$target_set" = false ]; then
  show_usage
  exit 1
fi

current_languages=()
while IFS= read -r language; do
  current_languages+=("$language")
done <<EOLOAD
$(load_primary_languages)
EOLOAD

if ! should_use_locale_target && ! should_use_startup_target && [ "${#current_languages[@]}" -eq 0 ]; then
  echo "Failed to read language settings."
  exit 1
fi

if [ "${#requested_languages[@]}" -lt 1 ] && [ "${#removed_languages[@]}" -lt 1 ]; then
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
    startup)
      print_locale_value "Current startup language setting:" "$(read_startup_language_value)"
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

if [ "${#requested_languages[@]}" -lt 1 ] && (should_use_locale_target || should_use_startup_target); then
  echo "The $target_mode target requires at least one added language argument for locale/startup updates."
  exit 1
fi

entity_languages=()
entity_base_indexes=()
entity_parents=()
entity_root_sections=()
entity_orders=()

base_index=0
for language in "${current_languages[@]}"; do
  create_entity "$language" "$base_index" base "$base_index" >/dev/null
  base_index=$((base_index + 1))
done

operation_order=0
operation_index=0
while [ "$operation_index" -lt "${#operation_kinds[@]}" ]; do
  operation_order=$((operation_order + 1))

  kind="${operation_kinds[$operation_index]}"
  source_request="${operation_sources[$operation_index]}"
  anchor_request="${operation_anchors[$operation_index]}"

  ensure_entity "$source_request" front "$operation_order"
  source_entity="$resolved_entity_index"

  case "$kind" in
    front)
      set_entity_root "$source_entity" front "$operation_order"
      ;;
    end)
      set_entity_root "$source_entity" end "$operation_order"
      ;;
    before)
      ensure_entity "$anchor_request" front "$operation_order"
      anchor_entity="$resolved_entity_index"
      set_entity_parent "$source_entity" "$anchor_entity" "$operation_order"
      ;;
  esac

  operation_index=$((operation_index + 1))
done

build_ordered_languages

result=()
if should_use_account_languages || should_use_login_window_languages; then
  for lang in "${ordered_languages[@]}"; do
    if ! should_remove_language "$lang"; then
      result+=("$lang")
    fi
  done

  echo "New language order:"
  if [ "${#result[@]}" -gt 0 ]; then
    printf '  %s\n' "${result[@]}"
  else
    echo "  empty"
  fi
  echo
fi

effective_locale_language="${requested_languages[0]}"
if [ "${#result[@]}" -gt 0 ]; then
  effective_locale_language="${result[0]}"
fi

new_locale=""
if should_use_locale_target; then
  new_locale="$(build_locale_value "$effective_locale_language")"
  echo "New locale value:"
  echo "  $new_locale"
  echo
fi

new_startup_value=""
if should_use_startup_target; then
  new_startup_value="$(build_startup_language_value "$effective_locale_language")"
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

  if should_use_startup_target; then
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
