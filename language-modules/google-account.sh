module_init() {
  module_key="google-account"
  module_display_name="Google Account"
  module_storage_label="account language settings"
  module_example_language="English Czech"
  module_example_dry_run_language="--dry-run English Czech"
  module_alias_help="This module uses Safari automation and expects the exact preferred-language labels printed by read-only mode."
  module_supports_bulk="false"
  module_flow_kind="external-cli"
  google_account_module_command="${GOOGLE_ACCOUNT_LANGUAGE_COMMAND:-$script_dir/language-modules/google-account-command.sh}"
  google_account_module_args=()
}

module_parse_arguments() {
  local arg=""

  module_requested_help=false
  module_requested_verbose_help=false
  google_account_module_args=("$@")

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
    "$google_account_module_command" --verbose --help
  else
    "$google_account_module_command" --help
  fi
}

module_run() {
  if [ "${#google_account_module_args[@]}" -gt 0 ]; then
    "$google_account_module_command" "${google_account_module_args[@]}"
  else
    "$google_account_module_command"
  fi
}
