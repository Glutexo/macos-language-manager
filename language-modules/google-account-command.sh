#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
display_command="${DISPLAY_COMMAND:-./manage-languages.sh google-account}"
helper_command="${GOOGLE_ACCOUNT_LANGUAGE_HELPER:-$script_dir/google-account-safari-helper.sh}"
preferred_languages_url="${GOOGLE_ACCOUNT_LANGUAGE_URL:-https://myaccount.google.com/language?hl=en}"
timeout_seconds="${GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT:-180}"
# shellcheck disable=SC1091
source "$script_dir/ordered-language-list-helper.sh"
dry_run=false
verbose_help=false
inherit_macos=false
disable_auto_add=false
google_current_language_ids=()
google_current_languages=()
google_added_for_you_languages=()
google_auto_add_enabled=false
reset_ordered_language_state

fail() {
  echo "$1" >&2
  exit 1
}

normalize_whitespace() {
  printf '%s\n' "$1" | awk '{$1=$1; print}'
}

read_current_languages_json() {
  "$helper_command" read-json
}

disable_google_auto_add() {
  "$helper_command" disable-auto-add
}

read_macos_preferred_languages() {
  local raw_language=""
  local candidate=""

  if [ -n "${MACOS_APP_LANGUAGE_INHERIT:-}" ]; then
    printf '%s\n' "$MACOS_APP_LANGUAGE_INHERIT"
    return 0
  fi

  raw_language="$(defaults read -g AppleLanguages 2>/dev/null || true)"
  [ -n "$raw_language" ] || return 1

  while IFS= read -r candidate; do
    candidate="${candidate//[()\", ]/}"
    if [[ "$candidate" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
      printf '%s\n' "$candidate"
    fi
  done <<EOF_LANG
$raw_language
EOF_LANG

  return 0
}

build_language_label_candidates() {
  local language_tag="$1"

  LANGUAGE_TAG="$language_tag" swift - <<'SWIFT'
import Foundation

let env = ProcessInfo.processInfo.environment
let rawTag = env["LANGUAGE_TAG"] ?? ""
let normalizedTag = rawTag.replacingOccurrences(of: "_", with: "-")
let english = Locale(identifier: "en_US")
let locale = Locale(identifier: normalizedTag)
let components = Locale.Components(identifier: normalizedTag)

var candidates: [String] = []

func append(_ value: String?) {
    guard let value else { return }
    let trimmed = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if !candidates.contains(trimmed) {
        candidates.append(trimmed)
    }
}

let languageCode = components.languageComponents.languageCode?.identifier ?? locale.language.languageCode?.identifier
let scriptCode = components.languageComponents.script?.identifier
let regionCode = components.languageComponents.region?.identifier

if let languageCode {
    append(english.localizedString(forLanguageCode: languageCode))
}
append(english.localizedString(forIdentifier: normalizedTag))
if let languageCode, let regionCode,
   let languageName = english.localizedString(forLanguageCode: languageCode),
   let regionName = english.localizedString(forRegionCode: regionCode) {
    append("\(languageName) (\(regionName))")
}
if let languageCode, let scriptCode,
   let languageName = english.localizedString(forLanguageCode: languageCode),
   let scriptName = english.localizedString(forScriptCode: scriptCode) {
    append("\(languageName) (\(scriptName))")
}

for candidate in candidates {
    print(candidate)
}
SWIFT
}

resolve_inherited_google_language() {
  local language_tag=""
  local candidate=""
  local current_language=""
  local current_language_id=""
  local label_candidates=()
  local normalized_tag=""
  local base_tag=""

  language_tag="$1"
  [ -n "$language_tag" ] || fail "Could not detect the current macOS preferred language."
  normalized_tag="${language_tag//_/-}"
  base_tag="${normalized_tag%%-*}"

  if [ "${#google_current_language_ids[@]}" -eq "${#google_current_languages[@]}" ]; then
    local index=0
    while [ "$index" -lt "${#google_current_language_ids[@]}" ]; do
      current_language_id="${google_current_language_ids[$index]}"
      current_language="${google_current_languages[$index]}"
      if [ "$current_language_id" = "$normalized_tag" ] || [ "${current_language_id%%-*}" = "$base_tag" ]; then
        printf '%s\n' "$current_language"
        return 0
      fi
      index=$((index + 1))
    done
  fi

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    label_candidates+=("$candidate")
  done < <(build_language_label_candidates "$language_tag")

  if [ "${#label_candidates[@]}" -eq 0 ]; then
    fail "Could not derive a Google Account language label from macOS language $language_tag."
  fi

  for candidate in "${label_candidates[@]}"; do
    for current_language in "${google_current_languages[@]}"; do
      if matches_requested_language "$candidate" "$current_language"; then
        printf '%s\n' "$current_language"
        return 0
      fi
    done
  done

  printf '%s\n' "${label_candidates[0]}"
}

prepare_inherited_google_language_requests() {
  local macos_languages=()
  local desired_google_languages=()
  local macos_language=""
  local google_language=""
  local current_language=""
  local index=0
  local wanted=""
  local found=false

  while IFS= read -r macos_language; do
    [ -n "$macos_language" ] || continue
    macos_languages+=("$macos_language")
  done < <(read_macos_preferred_languages)

  [ "${#macos_languages[@]}" -gt 0 ] || fail "Could not detect the current macOS preferred languages."

  for macos_language in "${macos_languages[@]}"; do
    google_language="$(resolve_inherited_google_language "$macos_language")"
    desired_google_languages+=("$google_language")
  done

  for wanted in "${desired_google_languages[@]}"; do
    parse_language_argument "$wanted"
  done

  for current_language in "${google_current_languages[@]-}"; do
    found=false
    for wanted in "${desired_google_languages[@]}"; do
      if matches_requested_language "$wanted" "$current_language"; then
        found=true
        break
      fi
    done
    if ! $found; then
      parse_language_argument "-$current_language"
    fi
  done
}

is_valid_configured_language() {
  local language="$1"

  [ -n "$(normalize_whitespace "$language")" ]
}

matches_requested_language() {
  local requested="$1"
  local language="$2"

  [ "$(normalize_whitespace "$requested")" = "$(normalize_whitespace "$language")" ]
}

build_missing_language_tag() {
  local requested="$1"

  printf '%s\n' "$(normalize_whitespace "$requested")"
}

show_usage() {
  echo "Read or change the preferred language order in the signed-in Google account through Safari automation."
  echo
  echo "Usage: $display_command [--dry-run|-n] [language ...]"
  echo
  echo "Behavior:"
  echo "  - without language arguments, prints the current Google Account preferred-language list"
  echo "  - with language arguments, uses the same token syntax as the macOS module"
  echo "  - adds, removes, and reorders languages through Safari automation"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned reorder without changing the Google Account page."
  echo "  --help, -h      Show this help message."
  echo "  --verbose, -v   Show help together with the Safari automation notes."
  echo "  --inherit-macos, -M  Replace the Google Account language list with the current macOS preferred language order."
  echo "  --disable-auto-add   Turn off Google's automatic language additions before writing."
  echo
  echo "Language arguments:"
  echo "  xx        Move the language at the front."
  echo "  +xx       Move the language at the front."
  echo "  -xx       Remove matching language entries."
  echo "  xx:yy     Move xx immediately before yy."
  echo "  xx:       Move xx at the end of the list."
  echo
  echo "Examples:"
  echo "  $display_command"
  echo "  $display_command --disable-auto-add"
  echo "  $display_command --inherit-macos"
  echo "  $display_command --dry-run \"English\""
  echo "  $display_command --dry-run \"English:Czech\""
  echo "  $display_command --dry-run \"English:\" \"-Czech\""
  echo "  $display_command \"English\" \"-Czech\""

  if ! $verbose_help; then
    return 0
  fi

  echo
  echo "Safari automation notes:"
  echo "  URL: $preferred_languages_url"
  echo "  Timeout: ${timeout_seconds}s"
  echo "  Safari must be allowed to run JavaScript on the Google Account language page."
  echo "  If Google requests sign-in or 2-step verification, complete it in Safari before the timeout expires."
  echo "  Use the exact labels printed by read-only mode."
  echo "  Missing languages are added through the Google Account editor when the helper can find them."
  echo "  --disable-auto-add clicks Google's \"Stop adding\" flow before the write."
  echo "  This flow is experimental because Google does not expose a public API for preferred-language ordering."
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run|-n)
        dry_run=true
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      --verbose|-v)
        verbose_help=true
        ;;
      --restore|-R)
        fail "The Google Account module does not support --restore."
        ;;
      --inherit-macos|-M)
        inherit_macos=true
        ;;
      --disable-auto-add)
        disable_auto_add=true
        ;;
      --force|-f)
        fail "The Google Account module does not support --force."
        ;;
      -*)
        parse_language_argument "$(normalize_whitespace "$1")"
        ;;
      *)
        parse_language_argument "$(normalize_whitespace "$1")"
        ;;
    esac
    shift
  done
}

print_list() {
  local prefix="$1"
  shift

  echo "$prefix"
  printf '  %s\n' "$@"
}

load_google_current_state() {
  local payload=""
  local kind=""
  local value=""
  local display=""
  local added_for_you=""

  google_current_language_ids=()
  google_current_languages=()
  google_added_for_you_languages=()
  google_auto_add_enabled=false

  payload="$(read_current_languages_json)"

  while IFS=$'\t' read -r kind value display added_for_you; do
    case "$kind" in
      auto-add)
        if [ "$value" = "true" ]; then
          google_auto_add_enabled=true
        fi
        ;;
      language)
        [ -n "$display" ] || continue
        google_current_language_ids+=("$value")
        google_current_languages+=("$display")
        if [ "$added_for_you" = "true" ]; then
          google_added_for_you_languages+=("$display")
        fi
        ;;
    esac
  done < <(
    printf '%s' "$payload" | python3 -c 'import json, sys
payload = json.load(sys.stdin)
print("auto-add\t{}".format("true" if payload.get("auto_add_enabled") else "false"))
for item in payload.get("languages", []):
    print("language\t{}\t{}\t{}".format(
        item.get("id", ""),
        item.get("display", ""),
        "true" if item.get("added_for_you") else "false",
    ))'
  )
}

print_added_for_you_warning() {
  if [ "${#google_added_for_you_languages[@]}" -eq 0 ]; then
    return 0
  fi

  echo "Warning: Google still marks these languages as Added for you:"
  printf '  %s\n' "${google_added_for_you_languages[@]}"
  if $google_auto_add_enabled; then
    echo "Use $display_command --disable-auto-add to turn off automatic Google language additions."
  fi
}

main() {
  local current_joined=""
  local result=()
  local base_index=0
  local operation_order=0
  local operation_index=0
  local kind=""
  local source_request=""
  local anchor_request=""
  local source_entity=""
  local anchor_entity=""
  local result_joined=""

  parse_arguments "$@"

  if $disable_auto_add && ! $dry_run; then
    disable_google_auto_add >/dev/null
  fi

  load_google_current_state

  if [ "${#google_current_languages[@]}" -eq 0 ]; then
    fail "Could not detect any Google Account preferred languages from Safari."
  fi

  if $inherit_macos; then
    if [ "${#requested_languages[@]}" -gt 0 ] || [ "${#removed_languages[@]}" -gt 0 ]; then
      fail "The --inherit-macos mode does not accept explicit language arguments."
    fi
    prepare_inherited_google_language_requests
  fi

  if [ "${#requested_languages[@]}" -eq 0 ] && [ "${#removed_languages[@]}" -eq 0 ]; then
    print_list "Current Google Account preferred languages:" "${google_current_languages[@]}"
    if $disable_auto_add; then
      if $dry_run; then
        echo "Would disable automatic Google language additions in Safari."
      else
        echo "Disabled automatic Google language additions in Safari."
      fi
    fi
    print_added_for_you_warning
    return 0
  fi

  entity_languages=()
  entity_base_indexes=()
  entity_parents=()
  entity_root_sections=()
  entity_orders=()

  for language in "${google_current_languages[@]}"; do
    create_entity "$language" "$base_index" base "$base_index" >/dev/null
    base_index=$((base_index + 1))
  done

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

  for language in "${ordered_languages[@]}"; do
    if ! should_remove_language "$language"; then
      result+=("$language")
    fi
  done

  current_joined="$(printf '%s\n' "${google_current_languages[@]}")"
  result_joined="$(printf '%s\n' "${result[@]}")"

  if [ "$current_joined" = "$result_joined" ]; then
    echo "Google Account preferred languages are already in the requested order."
    return 0
  fi

  if [ "${#result[@]}" -eq 0 ]; then
    fail "Google Account must keep at least one preferred language."
  fi

  if $dry_run; then
    print_list "Current Google Account preferred languages:" "${google_current_languages[@]}"
    print_list "New Google Account preferred languages:" "${result[@]}"
    if $disable_auto_add; then
      echo "Would disable automatic Google language additions in Safari before updating the list."
    fi
    echo "Would change the Google Account preferred-language list in Safari."
    print_added_for_you_warning
    return 0
  fi

  "$helper_command" write "${result[@]}"
  load_google_current_state
  print_list "Applied Google Account preferred languages:" "${result[@]}"
  if $disable_auto_add && $google_auto_add_enabled; then
    echo "Warning: Google still reports automatic language additions as enabled."
  fi
  print_added_for_you_warning
}

main "$@"
