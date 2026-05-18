module_init() {
  module_key="wingspan"
  module_display_name="Wingspan"
  module_storage_label="preferences plist"
  module_example_language="de"
  module_example_dry_run_language="ja"
  module_alias_help="Short aliases such as de, en, es, fr, it, ja, ko, pl, pt-BR, ru, uk, zh-CN, and zh-TW are accepted."
  module_supports_bulk="true"
  wingspan_preferences_file="${WINGSPAN_PREFERENCES_FILE:-$HOME/Library/Preferences/com.Monster-Couch.Wingspan.plist}"
  module_supported_languages=(
    English Polski Deutsch Français Español "Português (BR)" 日本語 Русский 简体中文 繁體中文 Italiano 한국어 Українська
  )
}

module_primary_path() {
  echo "$wingspan_preferences_file"
}

module_backup_paths() {
  echo "$wingspan_preferences_file"
}

module_validate_backup_paths() {
  local backup_path=""

  for backup_path in "$@"; do
    [ -f "$backup_path" ] || fail "Wingspan backup source file not found: $backup_path"
    [ -r "$backup_path" ] || fail "Wingspan backup source file is not readable: $backup_path"
  done
}

module_ensure_storage_exists() {
  [ -f "$wingspan_preferences_file" ] || fail "Wingspan preferences plist not found: $wingspan_preferences_file"
}

module_print_supported_languages() {
  printf '  %s\n' "${module_supported_languages[@]}"
}

module_print_aliases() {
  cat <<'EOF'
  de -> Deutsch
  en -> English
  es -> Español
  fr -> Français
  it -> Italiano
  ja -> 日本語
  ko -> 한국어
  pl -> Polski
  pt -> Português (BR)
  pt-BR -> Português (BR)
  ru -> Русский
  uk -> Українська
  zh -> 简体中文
  zh-CN -> 简体中文
  zh-TW -> 繁體中文
EOF
}

module_canonicalize_language() {
  local original_language="$1"
  local language="$1"
  local normalized_language="$1"
  local primary_language=""
  local supported_language=""

  [ -n "$language" ] || fail "Invalid Wingspan language value: $language"

  normalized_language="${normalized_language//_/-}"
  primary_language="${normalized_language%%-*}"

  case "$language" in
    de|de-DE|de_AT|de-AT|de_CH|de-CH|Deutsch) language="Deutsch" ;;
    en|en-US|en_GB|en-GB|English) language="English" ;;
    es|es-ES|es_ES|Español|Espanol) language="Español" ;;
    fr|fr-FR|fr_FR|Français|Francais) language="Français" ;;
    it|it-IT|it_IT|Italiano) language="Italiano" ;;
    ja|ja-JP|ja_JP|日本語) language="日本語" ;;
    ko|ko-KR|ko_KR|한국어) language="한국어" ;;
    pl|pl-PL|pl_PL|Polski) language="Polski" ;;
    pt|pt-BR|pt_BR|"Português (BR)"|"Portugues (BR)") language="Português (BR)" ;;
    ru|ru-RU|ru_RU|Русский) language="Русский" ;;
    uk|uk-UA|uk_UA|Українська) language="Українська" ;;
    zh|zh-CN|zh_CN|zh-Hans|zh_Hans|简体中文) language="简体中文" ;;
    zh-TW|zh_TW|zh-Hant|zh_Hant|繁體中文) language="繁體中文" ;;
  esac

  if [ "$language" = "$original_language" ] && [ "$primary_language" != "$normalized_language" ]; then
    case "$primary_language" in
      de) language="Deutsch" ;;
      en) language="English" ;;
      es) language="Español" ;;
      fr) language="Français" ;;
      it) language="Italiano" ;;
      ja) language="日本語" ;;
      ko) language="한국어" ;;
      pl) language="Polski" ;;
      pt) language="Português (BR)" ;;
      ru) language="Русский" ;;
      uk) language="Українська" ;;
      zh) language="简体中文" ;;
    esac
  fi

  for supported_language in "${module_supported_languages[@]}"; do
    if [ "$language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Wingspan interface language: $original_language"
}

module_is_running() {
  pgrep -x Wingspan >/dev/null 2>&1
}

module_read_current_language() {
  PLIST_FILE="$wingspan_preferences_file" python3 - <<'PY'
import os
import plistlib
import sys

path = os.environ["PLIST_FILE"]

with open(path, "rb") as handle:
    data = plistlib.load(handle)

value = data.get("I2 Language")
if not isinstance(value, str) or not value:
    sys.exit(1)

print(value)
PY
}

module_write_language() {
  PLIST_FILE="$wingspan_preferences_file" REQUESTED_LANGUAGE="$1" python3 - <<'PY'
import os
import plistlib
import sys

path = os.environ["PLIST_FILE"]
language = os.environ["REQUESTED_LANGUAGE"]

with open(path, "rb") as handle:
    data = plistlib.load(handle)

data["I2 Language"] = language

with open(path, "wb") as handle:
    plistlib.dump(data, handle, sort_keys=False)
PY
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
