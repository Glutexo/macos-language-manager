module_init() {
  module_key="macos"
  module_display_name="macOS"
  module_storage_label="system language settings"
  module_example_language="account ja"
  module_example_dry_run_language="all ja"
  module_alias_help="The macOS module has its own target-based CLI: account, login-window, locale, startup, and all."
  module_type="custom"
  macos_module_command="$script_dir/language-modules/macos-command.sh"
}

module_show_help_custom() {
  "$macos_module_command" --help
}

module_run_custom() {
  "$macos_module_command" "$@"
}
