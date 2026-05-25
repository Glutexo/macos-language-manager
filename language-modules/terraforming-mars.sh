script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/plist-language-helper.sh"

module_init() {
  module_key="terraforming-mars"
  module_display_name="Terraforming Mars"
  module_storage_label="preferences plist"
  module_example_language="de"
  module_example_dry_run_language="sv"
  module_alias_help="Short aliases such as de, en, es, fr, it, and sv are accepted."
  module_supports_bulk="true"
  terraforming_mars_preferences_file="${TERRAFORMING_MARS_PREFERENCES_FILE:-$HOME/Library/Preferences/Terraforming Mars.plist}"
  terraforming_mars_process_match="${TERRAFORMING_MARS_PROCESS_MATCH:-/TerraformingMars.app/Contents/MacOS/Terraforming Mars}"
  module_supported_languages=(
    English French German Spanish Italian Swedish
  )
}

module_primary_path() {
  echo "$terraforming_mars_preferences_file"
}

module_backup_paths() {
  echo "$terraforming_mars_preferences_file"
}

module_validate_backup_paths() {
  local backup_path=""

  for backup_path in "$@"; do
    [ -f "$backup_path" ] || fail "Terraforming Mars backup source file not found: $backup_path"
    [ -r "$backup_path" ] || fail "Terraforming Mars backup source file is not readable: $backup_path"
  done
}

module_ensure_storage_exists() {
  [ -f "$terraforming_mars_preferences_file" ] || fail "Terraforming Mars preferences plist not found: $terraforming_mars_preferences_file"
}

module_print_supported_languages() {
  printf '  %s\n' "${module_supported_languages[@]}"
}

module_print_aliases() {
  cat <<'EOF_ALIASES'
  de -> German
  en -> English
  es -> Spanish
  fr -> French
  it -> Italian
  sv -> Swedish
EOF_ALIASES
}

terraforming_mars_locale_for_language() {
  case "$1" in
    English) echo "en_US" ;;
    French) echo "fr_FR" ;;
    German) echo "de_DE" ;;
    Spanish) echo "es_ES" ;;
    Italian) echo "it_IT" ;;
    Swedish) echo "sv_SE" ;;
    *) return 1 ;;
  esac
}

module_canonicalize_language() {
  local original_language="$1"
  local language="$1"
  local normalized_language="$1"
  local primary_language=""
  local supported_language=""

  [ -n "$language" ] || fail "Invalid Terraforming Mars language value: $language"

  normalized_language="${normalized_language//_/-}"
  primary_language="${normalized_language%%-*}"

  case "$language" in
    de|de-DE|de_AT|de-AT|de_CH|de-CH|German) language="German" ;;
    en|en-US|en_GB|en-GB|English) language="English" ;;
    es|es-ES|es_ES|Spanish|Español|Espanol) language="Spanish" ;;
    fr|fr-FR|fr_FR|French|Français|Francais) language="French" ;;
    it|it-IT|it_IT|Italian|Italiano) language="Italian" ;;
    sv|sv-SE|sv_SE|Swedish|Svenska) language="Swedish" ;;
  esac

  if [ "$language" = "$original_language" ] && [ "$primary_language" != "$normalized_language" ]; then
    case "$primary_language" in
      de) language="German" ;;
      en) language="English" ;;
      es) language="Spanish" ;;
      fr) language="French" ;;
      it) language="Italian" ;;
      sv) language="Swedish" ;;
    esac
  fi

  for supported_language in "${module_supported_languages[@]}"; do
    if [ "$language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Terraforming Mars interface language: $original_language"
}

module_is_running() {
  pgrep -f "$terraforming_mars_process_match" >/dev/null 2>&1
}

module_read_current_language() {
  plist_read_first_string_key "$terraforming_mars_preferences_file" "I2 Language" "OSXPlayerCurrentLanguage"
}

module_write_language() {
  local locale=""

  locale="$(terraforming_mars_locale_for_language "$1")"
  [ -n "$locale" ] || fail "Unsupported Terraforming Mars locale mapping for: $1"

  plist_write_string_keys \
    "$terraforming_mars_preferences_file" \
    "I2 Language" "$1" \
    "OSXPlayerCurrentLanguage" "$locale"
}

module_show_usage() {
  standard_module_show_usage
}

module_parse_arguments() {
  standard_module_parse_arguments "$@"
}

module_run() {
  standard_module_run
}
