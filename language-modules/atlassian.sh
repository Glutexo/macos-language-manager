module_init() {
  module_key="atlassian"
  module_display_name="Atlassian Account"
  module_storage_label="account language preference"
  module_example_language="English (US)"
  module_example_dry_run_language="--dry-run Czech"
  module_alias_help="This module changes the Atlassian account language preference that Jira and other Atlassian Cloud apps inherit for the signed-in account."
  module_supports_bulk="false"
  module_flow_kind="external-cli"
  atlassian_account_module_command="${ATLASSIAN_ACCOUNT_LANGUAGE_COMMAND:-$script_dir/language-modules/atlassian-command.sh}"
  atlassian_account_module_args=()
}

module_parse_arguments() {
  local arg=""

  module_requested_help=false
  module_requested_verbose_help=false
  atlassian_account_module_args=("$@")

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
    "$atlassian_account_module_command" --verbose --help
  else
    "$atlassian_account_module_command" --help
  fi
}

module_run() {
  if [ "${#atlassian_account_module_args[@]}" -gt 0 ]; then
    "$atlassian_account_module_command" "${atlassian_account_module_args[@]}"
  else
    "$atlassian_account_module_command"
  fi
}
