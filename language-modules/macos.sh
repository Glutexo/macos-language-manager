module_init() {
  module_key="macos"
  module_display_name="macOS"
  module_storage_label="system language settings"
  module_example_language="account ja"
  module_example_dry_run_language="all ja"
  module_alias_help="The macOS module has its own target-based CLI: account, login-window, locale, startup, and all."
  module_supports_bulk="false"
  module_flow_kind="external-cli"
  macos_module_command="$script_dir/language-modules/macos-command.sh"
  macos_module_args=()
}

module_parse_arguments() {
  local arg=""

  module_requested_help=false
  module_requested_verbose_help=false
  macos_module_args=("$@")

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
    "$macos_module_command" --verbose --help
  else
    "$macos_module_command" --help
  fi
}

module_run() {
  "$macos_module_command" "${macos_module_args[@]}"
}
