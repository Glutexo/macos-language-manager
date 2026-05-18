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
reset_ordered_language_state

fail() {
  echo "$1" >&2
  exit 1
}

normalize_whitespace() {
  printf '%s\n' "$1" | awk '{$1=$1; print}'
}

read_current_languages() {
  "$helper_command" read
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

  echo "Google Account cannot add a missing preferred language yet: $requested" >&2
  exit 1
}

show_usage() {
  echo "Read or change the preferred language order in the signed-in Google account through Safari automation."
  echo
  echo "Usage: $display_command [--dry-run|-n] [language ...]"
  echo
  echo "Behavior:"
  echo "  - without language arguments, prints the current Google Account preferred-language list"
  echo "  - with language arguments, uses the same token syntax as the macOS module"
  echo "  - version 1 reorders or removes existing languages only"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned reorder without changing the Google Account page."
  echo "  --help, -h      Show this help message."
  echo "  --verbose, -v   Show help together with the Safari automation notes."
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
  echo "  Missing languages are rejected because the helper does not add them yet."
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
        fail "The Google Account module does not support --inherit-macos."
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

main() {
  local current_languages=()
  local line=""
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

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    current_languages+=("$(normalize_whitespace "$line")")
  done < <(read_current_languages)

  if [ "${#current_languages[@]}" -eq 0 ]; then
    fail "Could not detect any Google Account preferred languages from Safari."
  fi

  if [ "${#requested_languages[@]}" -eq 0 ] && [ "${#removed_languages[@]}" -eq 0 ]; then
    print_list "Current Google Account preferred languages:" "${current_languages[@]}"
    return 0
  fi

  entity_languages=()
  entity_base_indexes=()
  entity_parents=()
  entity_root_sections=()
  entity_orders=()

  for language in "${current_languages[@]}"; do
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

  current_joined="$(printf '%s\n' "${current_languages[@]}")"
  result_joined="$(printf '%s\n' "${result[@]}")"

  if [ "$current_joined" = "$result_joined" ]; then
    echo "Google Account preferred languages are already in the requested order."
    return 0
  fi

  if [ "${#result[@]}" -eq 0 ]; then
    fail "Google Account must keep at least one preferred language."
  fi

  if $dry_run; then
    print_list "Current Google Account preferred languages:" "${current_languages[@]}"
    print_list "New Google Account preferred languages:" "${result[@]}"
    echo "Would change the Google Account preferred-language list in Safari."
    return 0
  fi

  "$helper_command" write "${result[@]}"
  print_list "Applied Google Account preferred languages:" "${result[@]}"
}

main "$@"
