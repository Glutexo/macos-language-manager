#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
modules_dir="$script_dir/language-modules"
display_command="${DISPLAY_COMMAND:-./manage-app-language.sh}"
default_app="${DEFAULT_APP:-}"
show_help=false
verbose_help=false
dry_run=false
force_write=false
list_apps=false
self_test=false
restore_from_backup=false
inherit_macos=false
requested_app="$default_app"
requested_language=""

fail() {
  echo "$1" >&2
  exit 1
}

available_modules() {
  find "$modules_dir" -maxdepth 1 -type f -name '*.sh' -print 2>/dev/null \
    | sed 's#.*/##' \
    | sed 's#\.sh$##' \
    | sort
}

print_available_apps() {
  local app

  echo "  all"
  for app in $(available_modules); do
    echo "  $app"
  done
}

is_known_app() {
  local candidate="$1"
  local app

  if [ "$candidate" = "all" ]; then
    return 0
  fi

  for app in $(available_modules); do
    if [ "$candidate" = "$app" ]; then
      return 0
    fi
  done

  return 1
}

read_macos_preferred_language() {
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
      return 0
    fi
  done <<EOF_LANG
$raw_language
EOF_LANG

  return 1
}

show_global_usage() {
  echo "Read or change interface languages for supported macOS applications."
  echo
  echo "Usage: $display_command <app> [--dry-run|-n] [--force|-f] [language]"
  echo "       $display_command <app> --inherit-macos [--dry-run|-n] [--force|-f]"
  echo "       $display_command <app> --restore [--dry-run|-n] [--force|-f]"
  echo "       $display_command --list-apps"
  echo "       $display_command --self-test"
  echo
  echo "Options:"
  echo "  --dry-run, -n        Print the planned change without writing it."
  echo "  --force, -f          Write even if the application appears to be running."
  echo "  --help, -h           Show help. Add an app name for app-specific help."
  echo "  --verbose, -v        Show help together with supported language values."
  echo "  --inherit-macos, -M  Use the current macOS preferred language as the requested app language."
  echo "  --restore, -R        Restore the application language files from their .bak backups."
  echo "  --list-apps          List supported application modules."
  echo "  --self-test          Verify that all discovered modules implement the required contract."
  echo
  echo "Available apps:"
  print_available_apps

  echo
  echo "Examples:"
  echo "  $display_command steam"
  echo "  $display_command anki ja"
  echo "  $display_command factorio --dry-run zh-CN"
  echo "  $display_command steam --inherit-macos"
  echo "  $display_command all --inherit-macos"
}

load_module() {
  local module_file="$modules_dir/$1.sh"

  [ -f "$module_file" ] || fail "Unknown application module: $1"
  # shellcheck disable=SC1090
  source "$module_file"

  module_init

  : "${module_key:?}"
  : "${module_display_name:?}"
  : "${module_storage_label:?}"
  : "${module_example_language:?}"
  : "${module_example_dry_run_language:?}"
  module_primary_storage_path="$(module_primary_path)"
  [ -n "$module_primary_storage_path" ] || fail "Module $module_key did not report a primary storage path."
}

assert_module_function() {
  local function_name="$1"

  if ! declare -F "$function_name" >/dev/null 2>&1; then
    fail "Module $module_key is missing required function: $function_name"
  fi
}

run_module_self_test() {
  local app="$1"

  module_key=""
  module_display_name=""
  module_storage_label=""
  module_example_language=""
  module_example_dry_run_language=""
  module_alias_help=""
  module_primary_storage_path=""

  load_module "$app"

  assert_module_function "module_primary_path"
  assert_module_function "module_ensure_storage_exists"
  assert_module_function "module_print_supported_languages"
  assert_module_function "module_print_aliases"
  assert_module_function "module_backup_paths"
  assert_module_function "module_validate_backup_paths"
  assert_module_function "module_canonicalize_language"
  assert_module_function "module_is_running"
  assert_module_function "module_read_current_language"
  assert_module_function "module_write_language"

  echo "OK: $app"
}

run_self_test() {
  local app=""
  local found_any=false

  for app in $(available_modules); do
    found_any=true
    run_module_self_test "$app"
  done

  if ! $found_any; then
    fail "No application modules were found in $modules_dir"
  fi
}

collect_module_backup_paths() {
  module_backup_file_paths=()

  while IFS= read -r backup_path; do
    [ -n "$backup_path" ] || continue
    module_backup_file_paths+=("$backup_path")
  done < <(module_backup_paths)

  if [ "${#module_backup_file_paths[@]}" -eq 0 ]; then
    fail "Module $module_key did not report any files to back up."
  fi
}

backup_module_files() {
  local backup_file=""

  for backup_path in "${module_backup_file_paths[@]}"; do
    backup_file="$backup_path.bak"
    cp "$backup_path" "$backup_file"
    echo "Backup saved to $backup_file"
  done
}

validate_restore_sources() {
  local restore_source=""

  for backup_path in "${module_backup_file_paths[@]}"; do
    restore_source="$backup_path.bak"
    [ -f "$restore_source" ] || fail "Backup file not found: $restore_source"
    [ -r "$restore_source" ] || fail "Backup file is not readable: $restore_source"
  done
}

restore_module_files() {
  local restore_source=""

  for backup_path in "${module_backup_file_paths[@]}"; do
    restore_source="$backup_path.bak"
    cp "$restore_source" "$backup_path"
    echo "Restored $backup_path from $restore_source"
  done
}

try_read_current_language() {
  if [ -f "$module_primary_storage_path" ]; then
    module_read_current_language || true
  fi
}

show_module_usage() {
  local usage_target="$display_command $module_key"

  if [ -n "$default_app" ]; then
    usage_target="$display_command"
  fi

  echo "Read or change the $module_display_name interface language on macOS."
  echo
  echo "Usage: $usage_target [--dry-run|-n] [--force|-f] [language]"
  echo "       $usage_target --inherit-macos [--dry-run|-n] [--force|-f]"
  echo "       $usage_target --restore [--dry-run|-n] [--force|-f]"
  echo
  echo "Options:"
  echo "  --dry-run, -n        Print the planned change without writing it."
  echo "  --force, -f          Write even if $module_display_name appears to be running."
  echo "  --help, -h           Show this help message. Use --verbose or -v for the supported language list."
  echo "  --verbose, -v        Show help together with supported language values."
  echo "  --inherit-macos, -M  Use the current macOS preferred language as the requested $module_display_name language."
  echo "  --restore, -R        Restore the $module_display_name language files from their .bak backups."
  echo
  echo "Examples:"
  echo "  $usage_target"
  echo "  $usage_target $module_example_language"
  echo "  $usage_target --dry-run $module_example_dry_run_language"
  echo "  $usage_target --inherit-macos"

  if $verbose_help; then
    echo
    echo "Supported $module_display_name interface language values:"
    module_print_supported_languages

    if [ -n "${module_alias_help:-}" ]; then
      echo
      echo "$module_alias_help"
    fi

    if declare -F module_print_aliases >/dev/null 2>&1; then
      echo
      echo "Accepted aliases:"
      module_print_aliases
    fi
  fi
}

show_all_usage() {
  echo "Read or change the interface language for all supported macOS applications."
  echo
  echo "Usage: $display_command all [--dry-run|-n] [--force|-f] [language]"
  echo "       $display_command all --inherit-macos [--dry-run|-n] [--force|-f]"
  echo "       $display_command all --restore [--dry-run|-n] [--force|-f]"
  echo
  echo "Options:"
  echo "  --dry-run, -n        Print the planned changes without writing them."
  echo "  --force, -f          Write even if one of the applications appears to be running."
  echo "  --help, -h           Show this help message."
  echo "  --verbose, -v        Show the list of managed applications."
  echo "  --inherit-macos, -M  Use the current macOS preferred language for every application module."
  echo "  --restore, -R        Restore every module's language files from their .bak backups."
  echo
  echo "Managed applications:"
  print_available_apps
  echo
  echo "Examples:"
  echo "  $display_command all"
  echo "  $display_command all ja"
  echo "  $display_command all --inherit-macos"
  echo "  $display_command all --restore"
}

run_loaded_module() {
  local requested_language_input="$1"
  local current_language=""
  local restored_language=""
  local canonical_requested_language=""
  local display_current_language=""

  collect_module_backup_paths

  if $restore_from_backup; then
    current_language="$(try_read_current_language)"

    if ! $dry_run && ! $force_write && module_is_running; then
      fail "$module_display_name appears to be running. Quit $module_display_name first, or rerun with --force."
    fi

    validate_restore_sources

    if $dry_run; then
      echo "Would restore $module_display_name interface language files from backup."
      return 0
    fi

    restore_module_files
    restored_language="$(try_read_current_language)"

    if [ -n "$current_language" ] && [ -n "$restored_language" ]; then
      echo "Restored $module_display_name interface language from $current_language to $restored_language."
    elif [ -n "$restored_language" ]; then
      echo "Restored $module_display_name interface language to $restored_language from backup."
    else
      echo "Restored $module_display_name interface language files from backup."
    fi

    echo "Restart $module_display_name to apply the restored interface language."
    return 0
  fi

  module_ensure_storage_exists
  current_language="$(try_read_current_language)"

  if [ -z "$requested_language_input" ]; then
    [ -n "$current_language" ] || fail "Could not detect the current $module_display_name language in $module_primary_storage_path"
    echo "Current $module_display_name interface language: $current_language"
    return 0
  fi

  canonical_requested_language="$(module_canonicalize_language "$requested_language_input")"
  display_current_language="${current_language:-unset}"

  if [ "$canonical_requested_language" = "$current_language" ]; then
    echo "$module_display_name interface language is already set to $canonical_requested_language."
    return 0
  fi

  if ! $dry_run && ! $force_write && module_is_running; then
    fail "$module_display_name appears to be running. Quit $module_display_name first, or rerun with --force."
  fi

  if $dry_run; then
    echo "Would change $module_display_name interface language from $display_current_language to $canonical_requested_language."
    return 0
  fi

  module_validate_backup_paths "${module_backup_file_paths[@]}"
  backup_module_files
  module_write_language "$canonical_requested_language"

  echo "Changed $module_display_name interface language from $display_current_language to $canonical_requested_language."
  echo "Restart $module_display_name to apply the new interface language."
}

run_all_modules() {
  local app=""
  local found_any=false
  local requested_language_input="$1"

  for app in $(available_modules); do
    found_any=true
    load_module "$app"
    run_loaded_module "$requested_language_input"
  done

  if ! $found_any; then
    fail "No application modules were found in $modules_dir"
  fi
}

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
    --list-apps)
      list_apps=true
      ;;
    --self-test)
      self_test=true
      ;;
    --restore|-R)
      restore_from_backup=true
      ;;
    --inherit-macos|-M)
      inherit_macos=true
      ;;
    -*)
      fail "Unknown option: $1"
      ;;
    *)
      if [ -z "$requested_app" ] && is_known_app "$1"; then
        requested_app="$1"
      elif [ -z "$requested_app" ]; then
        fail "Unknown application: $1"
      elif [ -z "$requested_language" ]; then
        requested_language="$1"
      else
        fail "Only one language value can be provided."
      fi
      ;;
  esac
  shift
done

if $list_apps; then
  available_modules
  exit 0
fi

if $self_test; then
  run_self_test
  exit 0
fi

if [ -z "$requested_app" ]; then
  if $show_help || $verbose_help; then
    show_global_usage
    exit 0
  fi

  fail "Missing application name. Use --help to see supported apps."
fi

if $restore_from_backup && [ -n "$requested_language" ]; then
  fail "The --restore mode does not accept a language value."
fi

if $inherit_macos && [ -n "$requested_language" ]; then
  fail "The --inherit-macos mode does not accept a language value."
fi

if $restore_from_backup && $inherit_macos; then
  fail "The --restore and --inherit-macos modes cannot be used together."
fi

if [ "$requested_app" = "all" ]; then
  if $show_help || $verbose_help; then
    show_all_usage
    exit 0
  fi
else
  load_module "$requested_app"

  if $show_help || $verbose_help; then
    show_module_usage
    exit 0
  fi
fi

if $inherit_macos; then
  macos_requested_language="$(read_macos_preferred_language || true)"
  [ -n "$macos_requested_language" ] || fail "Could not detect the current macOS preferred language."
  requested_language="$macos_requested_language"
fi

if [ "$requested_app" = "all" ]; then
  run_all_modules "$requested_language"
  exit 0
fi

run_loaded_module "$requested_language"
