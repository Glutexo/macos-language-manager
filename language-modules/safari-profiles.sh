module_init() {
  module_key="safari-profiles"
  module_display_name="Safari Profiles"
  module_storage_label="browser profile cache"
  module_example_language="--refresh"
  module_example_dry_run_language="--show-cache-path"
  module_alias_help="This module manages the shared Safari browser-profile cache used by browser-automation modules."
  module_supports_bulk="false"
  module_flow_kind="external-cli"
  safari_profiles_module_command="${SAFARI_PROFILES_COMMAND:-$script_dir/language-modules/safari-profiles-command.sh}"
  safari_profiles_module_args=()
}

module_parse_arguments() {
  local arg=""

  module_requested_help=false
  module_requested_verbose_help=false
  safari_profiles_module_args=("$@")

  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        module_requested_help=true
        ;;
      --verbose|-v)
        module_requested_verbose_help=true
        ;;
    esac
  done
}

module_show_usage() {
  if $module_requested_verbose_help; then
    "$safari_profiles_module_command" --verbose --help
  else
    "$safari_profiles_module_command" --help
  fi
}

module_run() {
  if [ "${#safari_profiles_module_args[@]}" -gt 0 ]; then
    "$safari_profiles_module_command" "${safari_profiles_module_args[@]}"
  else
    "$safari_profiles_module_command"
  fi
}
