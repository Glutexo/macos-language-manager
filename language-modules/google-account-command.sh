#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
display_command="${DISPLAY_COMMAND:-./manage-languages.sh google-account}"
helper_command="${GOOGLE_ACCOUNT_LANGUAGE_HELPER:-$script_dir/google-account-safari-helper.sh}"
preferred_languages_url="${GOOGLE_ACCOUNT_LANGUAGE_URL:-https://myaccount.google.com/language?hl=en}"
timeout_seconds="${GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT:-180}"
dry_run=false
verbose_help=false
requested_languages=()

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

show_usage() {
  echo "Read or change the preferred language order in the signed-in Google account through Safari automation."
  echo
  echo "Usage: $display_command [--dry-run|-n] [language ...]"
  echo
  echo "Behavior:"
  echo "  - without language arguments, prints the current Google Account preferred-language list"
  echo "  - with language arguments, expects the full final list in the desired order"
  echo "  - version 1 only reorders languages that already exist in the account"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned reorder without changing the Google Account page."
  echo "  --help, -h      Show this help message."
  echo "  --verbose, -v   Show help together with the Safari automation notes."
  echo
  echo "Examples:"
  echo "  $display_command"
  echo "  $display_command --dry-run \"English\" \"Czech\""
  echo "  $display_command \"English\" \"Czech\""

  if ! $verbose_help; then
    return 0
  fi

  echo
  echo "Safari automation notes:"
  echo "  URL: $preferred_languages_url"
  echo "  Timeout: ${timeout_seconds}s"
  echo "  Safari must be allowed to run JavaScript on the Google Account language page."
  echo "  If Google requests sign-in or 2-step verification, complete it in Safari before the timeout expires."
  echo "  Use the exact labels printed by read-only mode. The helper does not add or remove languages yet."
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
        fail "Unknown option: $1"
        ;;
      *)
        requested_languages+=("$(normalize_whitespace "$1")")
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
  local requested_joined=""

  parse_arguments "$@"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    current_languages+=("$(normalize_whitespace "$line")")
  done < <(read_current_languages)

  if [ "${#current_languages[@]}" -eq 0 ]; then
    fail "Could not detect any Google Account preferred languages from Safari."
  fi

  if [ "${#requested_languages[@]}" -eq 0 ]; then
    print_list "Current Google Account preferred languages:" "${current_languages[@]}"
    return 0
  fi

  current_joined="$(printf '%s\n' "${current_languages[@]}")"
  requested_joined="$(printf '%s\n' "${requested_languages[@]}")"

  if [ "$current_joined" = "$requested_joined" ]; then
    echo "Google Account preferred languages are already in the requested order."
    return 0
  fi

  if [ "${#requested_languages[@]}" -ne "${#current_languages[@]}" ]; then
    fail "Requested ${#requested_languages[@]} languages, but the account currently shows ${#current_languages[@]}. Version 1 only reorders the existing list."
  fi

  if $dry_run; then
    print_list "Current Google Account preferred languages:" "${current_languages[@]}"
    print_list "Requested Google Account preferred languages:" "${requested_languages[@]}"
    echo "Would reorder the Google Account preferred-language list in Safari."
    return 0
  fi

  "$helper_command" write "${requested_languages[@]}"
  print_list "Applied Google Account preferred languages:" "${requested_languages[@]}"
}

main "$@"
