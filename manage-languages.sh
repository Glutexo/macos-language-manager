#!/bin/bash
set -euo pipefail

resolve_script_path() {
  local source_path="$1"
  local source_dir=""
  local target_path=""

  while [ -L "$source_path" ]; do
    source_dir="$(cd "$(dirname "$source_path")" && pwd)"
    target_path="$(readlink "$source_path")"
    if [[ "$target_path" != /* ]]; then
      source_path="$source_dir/$target_path"
    else
      source_path="$target_path"
    fi
  done

  source_dir="$(cd "$(dirname "$source_path")" && pwd)"
  printf '%s\n' "$source_dir/$(basename "$source_path")"
}

script_path="$(resolve_script_path "$0")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
modules_dir="$script_dir/language-modules"
display_command="${DISPLAY_COMMAND:-./manage-languages.sh}"
default_app="${DEFAULT_APP:-}"
show_help=false
verbose_help=false
list_apps=false
self_test=false
requested_app="$default_app"
selected_apps=()
module_pre_args=()
module_post_args=()

fail() {
  echo "$1" >&2
  exit 1
}

available_modules() {
  find "$modules_dir" -maxdepth 1 -type f -name '*.sh' -print 2>/dev/null \
    | sed 's#.*/##' \
    | sed 's#\.sh$##' \
    | grep -Ev '(-command|-helper)$' \
    | sort
}

print_available_apps() {
  local app

  echo "  all"
  echo "  everything"
  for app in $(available_modules); do
    echo "  $app"
  done
}

is_known_app() {
  local candidate="$1"
  local app

  if [ "$candidate" = "all" ] || [ "$candidate" = "everything" ]; then
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
  echo "Read or change macOS and application interface languages through dynamically loaded modules."
  echo
  echo "Usage: $display_command <module> [<module> ...] [--dry-run|-n] [--force|-f] [language]"
  echo "       $display_command <module> [<module> ...] --inherit-macos [--dry-run|-n] [--force|-f]"
  echo "       $display_command <module> [<module> ...] --restore [--dry-run|-n] [--force|-f]"
  echo "       $display_command everything [--dry-run|-n] [language ...]"
  echo "       $display_command --list-apps|--list-modules"
  echo "       $display_command --self-test"
  echo
  echo "Options:"
  echo "  --dry-run, -n        Module option. Print the planned change without writing it."
  echo "  --force, -f          Module option. Write even if the application appears to be running."
  echo "  --help, -h           Show help. Add a module name for module-specific help."
  echo "  --verbose, -v        Show help together with supported language values."
  echo "  --inherit-macos, -M  Module option for app-language modules."
  echo "  --restore, -R        Module option for app-language modules."
  echo "  --list-apps          List supported modules."
  echo "  --list-modules       Alias for --list-apps."
  echo "  --self-test          Verify that all discovered modules implement the required contract."
  echo
  echo "Available modules:"
  print_available_apps
  echo
  echo "Examples:"
  echo "  $display_command steam"
  echo "  $display_command steam anki ja"
  echo "  $display_command anki ja"
  echo "  $display_command factorio --dry-run zh-CN"
  echo "  $display_command macos account ja:cs"
  echo "  $display_command steam --inherit-macos"
  echo "  $display_command all --inherit-macos"
  echo "  $display_command everything de"
}

load_module() {
  local module_file="$modules_dir/$1.sh"

  [ -f "$module_file" ] || fail "Unknown module implementation: $1"

  module_key=""
  module_display_name=""
  module_storage_label=""
  module_example_language=""
  module_example_dry_run_language=""
  module_alias_help=""
  module_primary_storage_path=""
  module_supports_bulk="false"
  module_flow_kind="standard"
  module_requested_help=false
  module_requested_verbose_help=false
  # shellcheck disable=SC1090
  source "$module_file"

  module_init

  : "${module_key:?}"
  : "${module_display_name:?}"
  : "${module_storage_label:?}"
  : "${module_example_language:?}"
  : "${module_example_dry_run_language:?}"
  : "${module_supports_bulk:=false}"
  : "${module_flow_kind:=standard}"
}

assert_module_function() {
  local function_name="$1"

  if ! declare -F "$function_name" >/dev/null 2>&1; then
    fail "Module $module_key is missing required function: $function_name"
  fi
}

standard_module_reset_state() {
  module_requested_help=false
  module_requested_verbose_help=false
  module_dry_run=false
  module_force_write=false
  module_restore_from_backup=false
  module_inherit_macos=false
  module_requested_language=""
}

standard_module_parse_arguments() {
  standard_module_reset_state

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run|-n)
        module_dry_run=true
        ;;
      --force|-f)
        module_force_write=true
        ;;
      --help|-h)
        module_requested_help=true
        ;;
      --verbose|-v)
        module_requested_verbose_help=true
        ;;
      --restore|-R)
        module_restore_from_backup=true
        ;;
      --inherit-macos|-M)
        module_inherit_macos=true
        ;;
      -* )
        fail "Unknown option: $1"
        ;;
      *)
        if [ -z "$module_requested_language" ]; then
          module_requested_language="$1"
        else
          fail "Only one language value can be provided."
        fi
        ;;
    esac
    shift
  done

  if $module_restore_from_backup && [ -n "$module_requested_language" ]; then
    fail "The --restore mode does not accept a language value."
  fi

  if $module_inherit_macos && [ -n "$module_requested_language" ]; then
    fail "The --inherit-macos mode does not accept a language value."
  fi

  if $module_restore_from_backup && $module_inherit_macos; then
    fail "The --restore and --inherit-macos modes cannot be used together."
  fi
}

standard_module_show_usage() {
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

  if $module_requested_verbose_help; then
    echo
    echo "Supported $module_display_name interface language values:"
    print_standard_module_language_reference
  fi
}

join_by_comma() {
  local first_item=true
  local item=""

  for item in "$@"; do
    if $first_item; then
      printf '%s' "$item"
      first_item=false
    else
      printf ', %s' "$item"
    fi
  done
}

print_standard_module_language_reference() {
  local supported_values=()
  local alias_values=()
  local alias_targets=()
  local line=""
  local trimmed_line=""
  local alias_value=""
  local alias_target=""
  local supported_value=""
  local matched_aliases=()
  local index=0

  while IFS= read -r line; do
    trimmed_line="${line#"${line%%[![:space:]]*}"}"
    [ -n "$trimmed_line" ] || continue
    supported_values+=("$trimmed_line")
  done < <(module_print_supported_languages)

  if declare -F module_print_aliases >/dev/null 2>&1; then
    while IFS= read -r line; do
      trimmed_line="${line#"${line%%[![:space:]]*}"}"
      [ -n "$trimmed_line" ] || continue
      case "$trimmed_line" in
        *" -> "*)
          alias_value="${trimmed_line%% -> *}"
          alias_target="${trimmed_line#* -> }"
          alias_values+=("$alias_value")
          alias_targets+=("$alias_target")
          ;;
      esac
    done < <(module_print_aliases)
  fi

  for supported_value in "${supported_values[@]}"; do
    matched_aliases=()
    index=0
    while [ "$index" -lt "${#alias_values[@]}" ]; do
      if [ "${alias_targets[$index]}" = "$supported_value" ]; then
        matched_aliases+=("${alias_values[$index]}")
      fi
      index=$((index + 1))
    done

    if [ "${#matched_aliases[@]}" -gt 0 ]; then
      printf '  %s (%s)\n' "$supported_value" "$(join_by_comma "${matched_aliases[@]}")"
    else
      printf '  %s\n' "$supported_value"
    fi
  done
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
  local backup_path=""

  for backup_path in "${module_backup_file_paths[@]}"; do
    backup_file="$backup_path.bak"
    cp "$backup_path" "$backup_file"
    echo "Backup saved to $backup_file"
  done
}

validate_restore_sources() {
  local restore_source=""
  local backup_path=""

  for backup_path in "${module_backup_file_paths[@]}"; do
    restore_source="$backup_path.bak"
    [ -f "$restore_source" ] || fail "Backup file not found: $restore_source"
    [ -r "$restore_source" ] || fail "Backup file is not readable: $restore_source"
  done
}

restore_module_files() {
  local restore_source=""
  local backup_path=""

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

standard_module_run() {
  local current_language=""
  local restored_language=""
  local canonical_requested_language=""
  local display_current_language=""

  module_primary_storage_path="$(module_primary_path)"
  [ -n "$module_primary_storage_path" ] || fail "Module $module_key did not report a primary storage path."

  collect_module_backup_paths

  if $module_restore_from_backup; then
    current_language="$(try_read_current_language)"

    if ! $module_dry_run && ! $module_force_write && module_is_running; then
      fail "$module_display_name appears to be running. Quit $module_display_name first, or rerun with --force."
    fi

    validate_restore_sources

    if $module_dry_run; then
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

  if [ -z "$module_requested_language" ] && ! $module_inherit_macos; then
    [ -n "$current_language" ] || fail "Could not detect the current $module_display_name language in $module_primary_storage_path"
    echo "Current $module_display_name interface language: $current_language"
    return 0
  fi

  if $module_inherit_macos; then
    module_requested_language="$(read_macos_preferred_language || true)"
    [ -n "$module_requested_language" ] || fail "Could not detect the current macOS preferred language."
  fi

  canonical_requested_language="$(module_canonicalize_language "$module_requested_language")"
  display_current_language="${current_language:-unset}"

  if [ "$canonical_requested_language" = "$current_language" ]; then
    echo "$module_display_name interface language is already set to $canonical_requested_language."
    return 0
  fi

  if ! $module_dry_run && ! $module_force_write && module_is_running; then
    fail "$module_display_name appears to be running. Quit $module_display_name first, or rerun with --force."
  fi

  if $module_dry_run; then
    echo "Would change $module_display_name interface language from $display_current_language to $canonical_requested_language."
    return 0
  fi

  module_validate_backup_paths "${module_backup_file_paths[@]}"
  backup_module_files
  module_write_language "$canonical_requested_language"

  echo "Changed $module_display_name interface language from $display_current_language to $canonical_requested_language."
  echo "Restart $module_display_name to apply the new interface language."
}

run_module_self_test() {
  local app="$1"

  load_module "$app"

  assert_module_function "module_show_usage"
  assert_module_function "module_parse_arguments"
  assert_module_function "module_run"

  if [ "$module_flow_kind" = "standard" ]; then
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
  fi

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
    fail "No modules were found in $modules_dir"
  fi
}

show_all_usage() {
  echo "Read or change the interface language for all bulk-capable application modules."
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

show_everything_usage() {
  echo "Read or change both application interface languages and macOS language settings in one run."
  echo
  echo "Usage: $display_command everything [--dry-run|-n] [language ...]"
  echo
  echo "Behavior:"
  echo "  1. Runs the existing application pseudo-module: $display_command all ..."
  echo "  2. Runs the existing macOS command: $display_command macos all ..."
  echo
  echo "Notes:"
  echo "  Use arguments that make sense for both flows."
  echo "  The most useful shared forms are read-only mode, --dry-run, and explicit language tokens such as de or ja."
  echo
  echo "Examples:"
  echo "  $display_command everything"
  echo "  $display_command everything de"
  echo "  $display_command everything --dry-run de"
}

parse_global_arguments() {
  local module_found=false
  local module_selection_finished=false

  while [ "$#" -gt 0 ]; do
    if ! $module_selection_finished && is_known_app "$1"; then
      requested_app="$1"
      selected_apps+=("$1")
      module_found=true
      if [ "$1" = "macos" ] || [ "$1" = "all" ] || [ "$1" = "everything" ]; then
        module_selection_finished=true
      fi
      shift
      continue
    fi

    if ! $module_found; then
      if [[ "$1" != -* ]]; then
        fail "Unknown module: $1"
      fi

      case "$1" in
        --list-apps|--list-modules)
          list_apps=true
          ;;
        --self-test)
          self_test=true
          ;;
        --help|-h)
          show_help=true
          ;;
        --verbose|-v)
          verbose_help=true
          ;;
      esac
      module_pre_args+=("$1")
    else
      module_selection_finished=true
      module_post_args+=("$1")
    fi
    shift
  done
}

validate_selected_apps() {
  local app=""
  local arg=""

  [ "${#selected_apps[@]}" -gt 0 ] || return 0

  if [ "$requested_app" = "all" ]; then
    if [ "${#module_post_args[@]}" -gt 0 ]; then
      for arg in "${module_post_args[@]}"; do
        if is_known_app "$arg"; then
          fail "The all pseudo-module cannot be combined with other modules."
        fi
      done
    fi
  fi

  if [ "${#selected_apps[@]}" -gt 1 ]; then
    for app in "${selected_apps[@]}"; do
      if [ "$app" = "all" ]; then
        fail "The all pseudo-module cannot be combined with other modules."
      fi
      if [ "$app" = "everything" ]; then
        fail "The everything pseudo-module cannot be combined with other modules."
      fi
      if [ "$app" = "macos" ]; then
        fail "The macos module cannot be combined with other modules."
      fi
    done
  fi

  if [ "$requested_app" = "everything" ]; then
    if [ "${#module_post_args[@]}" -gt 0 ]; then
      for arg in "${module_post_args[@]}"; do
        if is_known_app "$arg"; then
          fail "The everything pseudo-module cannot be combined with other modules."
        fi
      done
    fi
  fi
}

run_all_modules() {
  local app=""
  local found_any=false
  local module_args=("$@")
  local bulk_requested_language=""
  local bulk_change_mode=false
  local module_output=""
  local module_status=0

  if [ "${#module_args[@]}" -gt 0 ]; then
    standard_module_parse_arguments "${module_args[@]}"
  else
    standard_module_parse_arguments
  fi

  if $module_requested_help || $module_requested_verbose_help; then
    show_all_usage
    return 0
  fi

  if [ -n "$module_requested_language" ] || $module_inherit_macos; then
    bulk_change_mode=true
  fi

  if $module_inherit_macos; then
    bulk_requested_language="$(read_macos_preferred_language || true)"
    [ -n "$bulk_requested_language" ] || fail "Could not detect the current macOS preferred language."
  else
    bulk_requested_language="$module_requested_language"
  fi

  for app in $(available_modules); do
    load_module "$app"
    if [ "$module_supports_bulk" != "true" ]; then
      continue
    fi
    found_any=true
    if [ "${#module_args[@]}" -gt 0 ]; then
      module_parse_arguments "${module_args[@]}"
    else
      module_parse_arguments
    fi

    if $bulk_change_mode; then
      set +e
      module_output="$(module_run 2>&1)"
      module_status=$?
      set -e

      if [ "$module_status" -eq 0 ]; then
        [ -n "$module_output" ] && printf '%s\n' "$module_output"
        continue
      fi

      if printf '%s\n' "$module_output" | grep -Eq '^Unsupported .+ interface language: '; then
        printf 'Skipping %s: interface language %s is not supported.\n' "$module_display_name" "$bulk_requested_language"
        continue
      fi

      printf '%s\n' "$module_output" >&2
      exit "$module_status"
    fi

    module_run
  done

  if ! $found_any; then
    fail "No bulk-capable application modules were found in $modules_dir"
  fi
}

run_selected_modules() {
  local app=""
  local module_args=("$@")
  local shown_help=false

  for app in "${selected_apps[@]}"; do
    load_module "$app"
    if [ "${#module_args[@]}" -gt 0 ]; then
      module_parse_arguments "${module_args[@]}"
    else
      module_parse_arguments
    fi

    if $module_requested_help || $module_requested_verbose_help; then
      if $shown_help; then
        echo
      fi
      module_show_usage
      shown_help=true
      continue
    fi

    module_run
  done
}

run_everything() {
  local everything_args=("$@")
  local macos_args=("all")

  if [ "${#everything_args[@]}" -gt 0 ]; then
    standard_module_parse_arguments "${everything_args[@]}" || true
  else
    standard_module_parse_arguments
  fi

  if $module_requested_help || $module_requested_verbose_help; then
    show_everything_usage
    return 0
  fi

  if [ "${#everything_args[@]}" -gt 0 ]; then
    run_all_modules "${everything_args[@]}"
    macos_args+=("${everything_args[@]}")
  else
    run_all_modules
  fi

  load_module "macos"
  if [ "${#macos_args[@]}" -gt 0 ]; then
    module_parse_arguments "${macos_args[@]}"
  else
    module_parse_arguments
  fi
  module_run
}

parse_global_arguments "$@"
validate_selected_apps

if $list_apps && [ -z "$requested_app" ]; then
  available_modules
  exit 0
fi

if $self_test && [ -z "$requested_app" ]; then
  run_self_test
  exit 0
fi

if [ -z "$requested_app" ]; then
  if $show_help || $verbose_help; then
    show_global_usage
    exit 0
  fi

  fail "Missing module name. Use --help to see supported modules."
fi

module_cli_args=()
if [ "${#module_pre_args[@]}" -gt 0 ]; then
  module_cli_args+=("${module_pre_args[@]}")
fi
if [ "${#module_post_args[@]}" -gt 0 ]; then
  module_cli_args+=("${module_post_args[@]}")
fi

if [ "$requested_app" = "all" ]; then
  if [ "${#module_cli_args[@]}" -gt 0 ]; then
    run_all_modules "${module_cli_args[@]}"
  else
    run_all_modules
  fi
  exit 0
fi

if [ "$requested_app" = "everything" ]; then
  if [ "${#module_cli_args[@]}" -gt 0 ]; then
    run_everything "${module_cli_args[@]}"
  else
    run_everything
  fi
  exit 0
fi

if [ "${#module_cli_args[@]}" -gt 0 ]; then
  run_selected_modules "${module_cli_args[@]}"
else
  run_selected_modules
fi
