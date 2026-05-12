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

is_known_app() {
  local candidate="$1"
  local app

  for app in $(available_modules); do
    if [ "$candidate" = "$app" ]; then
      return 0
    fi
  done

  return 1
}

show_global_usage() {
  echo "Read or change interface languages for supported macOS applications."
  echo
  echo "Usage: $display_command <app> [--dry-run|-n] [--force|-f] [language]"
  echo "       $display_command --list-apps"
  echo "       $display_command --self-test"
  echo
  echo "Options:"
  echo "  --dry-run, -n    Print the planned change without writing it."
  echo "  --force, -f      Write even if the application appears to be running."
  echo "  --help, -h       Show help. Add an app name for app-specific help."
  echo "  --verbose, -v    Show help together with supported language values."
  echo "  --list-apps      List supported application modules."
  echo "  --self-test      Verify that all discovered modules implement the required contract."
  echo
  echo "Available apps:"

  local app
  for app in $(available_modules); do
    echo "  $app"
  done

  echo
  echo "Examples:"
  echo "  $display_command steam"
  echo "  $display_command anki ja"
  echo "  $display_command factorio --dry-run zh-CN"
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

show_module_usage() {
  local usage_target="$display_command $module_key"

  if [ -n "$default_app" ]; then
    usage_target="$display_command"
  fi

  echo "Read or change the $module_display_name interface language on macOS."
  echo
  echo "Usage: $usage_target [--dry-run|-n] [--force|-f] [language]"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned change without writing it."
  echo "  --force, -f     Write even if $module_display_name appears to be running."
  echo "  --help, -h      Show this help message. Use --verbose or -v for the supported language list."
  echo "  --verbose, -v   Show help together with supported language values."
  echo
  echo "Examples:"
  echo "  $usage_target"
  echo "  $usage_target $module_example_language"
  echo "  $usage_target --dry-run $module_example_dry_run_language"

  if $verbose_help; then
    echo
    echo "Supported $module_display_name interface language values:"
    module_print_supported_languages

    if [ -n "${module_alias_help:-}" ]; then
      echo
      echo "$module_alias_help"
    fi
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

load_module "$requested_app"

if $show_help || $verbose_help; then
  show_module_usage
  exit 0
fi

module_ensure_storage_exists
current_language="$(module_read_current_language || true)"

if [ -z "$requested_language" ]; then
  [ -n "$current_language" ] || fail "Could not detect the current $module_display_name language in $module_primary_storage_path"
  echo "Current $module_display_name interface language: $current_language"
  exit 0
fi

requested_language="$(module_canonicalize_language "$requested_language")"
display_current_language="${current_language:-unset}"

if [ "$requested_language" = "$current_language" ]; then
  echo "$module_display_name interface language is already set to $requested_language."
  exit 0
fi

if ! $dry_run && ! $force_write && module_is_running; then
  fail "$module_display_name appears to be running. Quit $module_display_name first, or rerun with --force."
fi

if $dry_run; then
  echo "Would change $module_display_name interface language from $display_current_language to $requested_language."
  exit 0
fi

collect_module_backup_paths
module_validate_backup_paths "${module_backup_file_paths[@]}"
backup_module_files
module_write_language "$requested_language"

echo "Changed $module_display_name interface language from $display_current_language to $requested_language."
echo "Restart $module_display_name to apply the new interface language."
