#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
display_command="${DISPLAY_COMMAND:-./manage-languages.sh safari-profiles}"
profile_cache_path="${SAFARI_BROWSER_PROFILE_CACHE:-$HOME/Library/Application Support/macos-language-manager/safari-browser-profiles.txt}"
safari_tabs_db_override="${SAFARI_BROWSER_PROFILE_TABS_DB:-}"
browser_profiles_override="${SAFARI_BROWSER_PROFILES:-}"
browser_profile_menu_data_override="${SAFARI_BROWSER_PROFILE_MENU_DATA:-}"
browser_profile_menu_items_override="${SAFARI_BROWSER_PROFILE_MENU_ITEMS:-}"
# shellcheck disable=SC1091
source "$script_dir/safari-browser-profile-helper.sh"

verbose_help=false
refresh_cache=false
clear_cache=false
show_cache_path=false
list_cache_only=false
list_effective=false

fail() {
  echo "$1" >&2
  exit 1
}

print_profile_list() {
  local heading="$1"
  shift

  echo "$heading"
  if [ "$#" -eq 0 ]; then
    echo "  (none)"
    return 0
  fi
  printf '  %s\n' "$@"
}

read_cached_profiles() {
  local cached_profiles=()
  local profile_name=""

  if read_profile_cache >/dev/null 2>&1; then
    while IFS= read -r profile_name; do
      [ -n "$profile_name" ] || continue
      cached_profiles+=("$profile_name")
    done < <(read_profile_cache)
  fi

  printf '%s\n' "${cached_profiles[@]-}"
}

remove_profile_cache() {
  rm -f "$profile_cache_path"
}

show_usage() {
  echo "Inspect or refresh the shared Safari browser-profile cache used by browser-automation modules."
  echo
  echo "Usage: $display_command"
  echo "       $display_command --refresh"
  echo "       $display_command --clear-cache"
  echo "       $display_command --list-cache"
  echo "       $display_command --list-effective"
  echo "       $display_command --show-cache-path"
  echo
  echo "Behavior:"
  echo "  - without options, prints the cache path, cached profile names, and the effective profile list"
  echo "  - --refresh updates the cache from Safari's File menu and prints the refreshed names"
  echo "  - --clear-cache removes the stored cache file"
  echo
  echo "Options:"
  echo "  --help, -h         Show this help message."
  echo "  --verbose, -v      Show help together with implementation notes."
  echo "  --refresh          Refresh the shared Safari browser-profile cache through UI automation."
  echo "  --clear-cache      Remove the shared Safari browser-profile cache file."
  echo "  --list-cache       Print only the cached Safari browser profile names."
  echo "  --list-effective   Print the effective Safari browser profile names."
  echo "  --show-cache-path  Print the cache file path."
  echo
  echo "Examples:"
  echo "  $display_command"
  echo "  $display_command --refresh"
  echo "  $display_command --clear-cache"
  echo "  $display_command --list-cache"
  echo "  $display_command --list-effective"

  if ! $verbose_help; then
    return 0
  fi

  echo
  echo "Implementation notes:"
  echo "  Cache path: $profile_cache_path"
  echo "  Effective profile listing uses cache first, then SafariTabs.db, then default."
  echo "  Refresh reads Safari's File menu through UI automation."
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h)
        show_usage
        exit 0
        ;;
      --verbose|-v)
        verbose_help=true
        ;;
      --refresh)
        refresh_cache=true
        ;;
      --clear-cache)
        clear_cache=true
        ;;
      --show-cache-path)
        show_cache_path=true
        ;;
      --list-cache)
        list_cache_only=true
        ;;
      --list-effective)
        list_effective=true
        ;;
      --dry-run|-n|--force|-f|--restore|-R|--inherit-macos|-M|--browser-profile|--list-browser-profiles|--refresh-browser-profiles)
        fail "Unsupported option for the safari-profiles module: $1"
        ;;
      -*)
        fail "Unknown option: $1"
        ;;
      *)
        fail "The safari-profiles module does not accept language arguments: $1"
        ;;
    esac
    shift
  done
}

main() {
  local cached_profiles=()
  local effective_profiles=()
  local profile_name=""

  parse_arguments "$@"

  if $refresh_cache; then
    if $clear_cache || $show_cache_path || $list_cache_only || $list_effective; then
      fail "The --refresh mode does not accept other options."
    fi
  fi

  if $clear_cache; then
    if $show_cache_path || $list_cache_only || $list_effective; then
      fail "The --clear-cache mode does not accept other options."
    fi
  fi

  if $show_cache_path; then
    if $list_cache_only || $list_effective; then
      fail "The --show-cache-path mode does not accept profile-list options."
    fi
  fi

  if $refresh_cache; then
    while IFS= read -r profile_name; do
      [ -n "$profile_name" ] || continue
      effective_profiles+=("$profile_name")
    done < <(refresh_browser_profiles)
    print_profile_list "Refreshed Safari browser profiles:" "${effective_profiles[@]}"
    return 0
  fi

  if $clear_cache; then
    remove_profile_cache
    echo "Removed Safari browser-profile cache: $profile_cache_path"
    return 0
  fi

  if $show_cache_path; then
    printf '%s\n' "$profile_cache_path"
    return 0
  fi

  while IFS= read -r profile_name; do
    [ -n "$profile_name" ] || continue
    cached_profiles+=("$profile_name")
  done < <(read_cached_profiles)

  if $list_cache_only; then
    if [ "${#cached_profiles[@]}" -gt 0 ]; then
      printf '%s\n' "${cached_profiles[@]}"
    fi
    return 0
  fi

  while IFS= read -r profile_name; do
    [ -n "$profile_name" ] || continue
    effective_profiles+=("$profile_name")
  done < <(list_browser_profiles)

  if $list_effective; then
    if [ "${#effective_profiles[@]}" -gt 0 ]; then
      printf '%s\n' "${effective_profiles[@]}"
    fi
    return 0
  fi

  echo "Safari browser-profile cache path: $profile_cache_path"
  print_profile_list "Cached Safari browser profiles:" "${cached_profiles[@]}"
  print_profile_list "Effective Safari browser profiles:" "${effective_profiles[@]}"
}

main "$@"
