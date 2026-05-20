#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
display_command="${DISPLAY_COMMAND:-./manage-languages.sh atlassian-account}"
helper_command="${ATLASSIAN_ACCOUNT_LANGUAGE_HELPER:-$script_dir/atlassian-account-safari-helper.sh}"
account_preferences_url="${ATLASSIAN_ACCOUNT_LANGUAGE_URL:-https://id.atlassian.com/manage-profile/account-preferences}"
timeout_seconds="${ATLASSIAN_ACCOUNT_LANGUAGE_TIMEOUT:-180}"
helper_browser_profile_env_var="ATLASSIAN_ACCOUNT_BROWSER_PROFILE"
# shellcheck disable=SC1091
source "$script_dir/browser-profile-command-helper.sh"
# shellcheck disable=SC1091
source "$script_dir/macos-language-inherit-helper.sh"
dry_run=false
verbose_help=false
inherit_macos=false
all_browser_profiles=false
all_known_browser_profiles=false
selected_browser_profiles=()
requested_language=""
target_browser_profiles=()

fail() {
  echo "$1" >&2
  exit 1
}

normalize_whitespace() {
  printf '%s\n' "$1" | awk '{$1=$1; print}'
}

language_catalog() {
  cat <<'EOF'
English (US)|en-US|en,en-US,en_US,english,english us,english usa
English (UK)|en-GB|en-GB,en_GB,en-UK,en_UK,en-AU,en_AU,english uk,english gb,british english
Chinese (Simplified)|zh-CN|zh,zh-CN,zh_CN,zh-Hans,zh_Hans,zh-SG,zh_SG,zh-MY,zh_MY,chinese simplified,simplified chinese
Chinese (Traditional)|zh-TW|zh-TW,zh_TW,zh-HK,zh_HK,zh-MO,zh_MO,zh-Hant,zh_Hant,chinese traditional,traditional chinese
Czech|cs|cs,cs-CZ,cs_CZ,cestina,čeština,czech
Danish|da|da,da-DK,da_DK,danish
Dutch|nl|nl,nl-NL,nl_NL,dutch
Estonian|et|et,et-EE,et_EE,estonian
Finnish|fi|fi,fi-FI,fi_FI,finnish
French|fr|fr,fr-FR,fr_FR,french
German|de|de,de-DE,de_DE,german,deutsch
Hungarian|hu|hu,hu-HU,hu_HU,hungarian
Icelandic|is|is,is-IS,is_IS,icelandic
Italian|it|it,it-IT,it_IT,italian
Japanese|ja|ja,ja-JP,ja_JP,japanese
Korean|ko|ko,ko-KR,ko_KR,korean
Norwegian|nb|no,no-NO,no_NO,nb,nb-NO,nb_NO,norwegian,norwegian bokmal,norwegian bokmål
Polish|pl|pl,pl-PL,pl_PL,polish
Portuguese (Brazil)|pt-BR|pt-BR,pt_BR,portuguese brazil,brazilian portuguese
Portuguese (Portugal)|pt-PT|pt-PT,pt_PT,portuguese portugal,european portuguese
Romanian|ro|ro,ro-RO,ro_RO,romanian
Russian|ru|ru,ru-RU,ru_RU,russian
Serbian (Cyrillic)|sr-Cyrl|sr-Cyrl,sr_Cyrl,sr-Cyrl-RS,sr_Cyrl_RS,serbian cyrillic
Serbian (Latin)|sr-Latn|sr-Latn,sr_Latn,sr-Latn-RS,sr_Latn_RS,serbian latin
Slovak|sk|sk,sk-SK,sk_SK,slovak
Slovenian|sl|sl,sl-SI,sl_SI,slovenian
Spanish|es|es,es-ES,es_ES,spanish
Swedish|sv|sv,sv-SE,sv_SE,swedish
Turkish|tr|tr,tr-TR,tr_TR,turkish
Ukrainian|uk|uk,uk-UA,uk_UA,ukrainian
Vietnamese|vi|vi,vi-VN,vi_VN,vietnamese
EOF
}

supported_language_lines() {
  language_catalog | while IFS='|' read -r display _ aliases; do
    printf '  %s (%s)\n' "$display" "$aliases"
  done
}

canonicalize_requested_language() {
  local requested=""
  local normalized=""
  local display=""
  local canonical_tag=""
  local aliases=""
  local alias=""

  requested="$(normalize_whitespace "$1")"
  [ -n "$requested" ] || fail "Invalid language value: $1"
  normalized="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"

  while IFS='|' read -r display canonical_tag aliases; do
    if [ "$(printf '%s' "$display" | tr '[:upper:]' '[:lower:]')" = "$normalized" ]; then
      printf '%s\n' "$display"
      return 0
    fi
    IFS=',' read -r -a alias_items <<<"$aliases"
    for alias in "${alias_items[@]}"; do
      if [ "$(printf '%s' "$alias" | tr '[:upper:]' '[:lower:]')" = "$normalized" ]; then
        printf '%s\n' "$display"
        return 0
      fi
    done
  done <<EOF
$(language_catalog)
EOF

  fail "Unsupported Atlassian account language: $1"
}

show_usage() {
  echo "Read or change the Atlassian account language preference that Jira and other Atlassian Cloud apps inherit."
  echo
  echo "Usage: $display_command [--dry-run|-n] [language]"
  echo
  echo "Behavior:"
  echo "  - without a language argument, prints the current Atlassian account language"
  echo "  - with a language argument, writes one Atlassian account language preference"
  echo "  - uses Safari automation because acli does not expose an account-language command here"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned language change without writing it."
  echo "  --help, -h      Show this help message."
  echo "  --verbose, -v   Show help together with supported values and Safari notes."
  echo "  --inherit-macos, -M  Use the first current macOS preferred language."
  echo "  --browser-profile NAME  Use the named browser profile. Repeatable."
  echo "  --all-browser-profiles  Apply the command to every valid browser profile."
  echo "  --all-known-browser-profiles  Apply the command to every browser profile currently known to the helper."
  echo
  echo "Examples:"
  echo "  $display_command"
  echo "  $display_command Czech"
  echo "  $display_command \"English (US)\""
  echo "  $display_command --inherit-macos"
  echo "  $display_command --browser-profile work Czech"
  echo "  $display_command --all-known-browser-profiles --dry-run Japanese"

  if ! $verbose_help; then
    return 0
  fi

  echo
  echo "Supported Atlassian account language values:"
  supported_language_lines
  echo
  echo "Safari automation notes:"
  echo "  URL: $account_preferences_url"
  echo "  Timeout: ${timeout_seconds}s"
  echo "  Safari must be allowed to run JavaScript on the Atlassian account preferences page."
  echo "  If Atlassian requests sign-in or verification, complete it in Safari before the timeout expires."
  echo "  Use ./manage-languages.sh safari-profiles to inspect or refresh the shared Safari profile cache."
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run|-n)
        dry_run=true
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      --verbose|-v)
        verbose_help=true
        ;;
      --restore|-R)
        fail "The Atlassian account module does not support --restore."
        ;;
      --inherit-macos|-M)
        inherit_macos=true
        ;;
      --browser-profile)
        shift
        [ "$#" -gt 0 ] || fail "The --browser-profile option requires a value."
        selected_browser_profiles+=("$1")
        ;;
      --browser-profile=*)
        selected_browser_profiles+=("${1#--browser-profile=}")
        ;;
      --all-browser-profiles)
        all_browser_profiles=true
        ;;
      --all-known-browser-profiles)
        all_known_browser_profiles=true
        ;;
      --force|-f)
        fail "The Atlassian account module does not support --force."
        ;;
      -*)
        fail "Unknown option: $1"
        ;;
      *)
        if [ -n "$requested_language" ]; then
          fail "Only one language value can be provided."
        fi
        requested_language="$(normalize_whitespace "$1")"
        ;;
    esac
    shift
  done
}

load_atlassian_current_state() {
  local profile_name="${1:-}"
  local payload=""

  payload="$(run_helper_for_profile "$profile_name" read-json)"

  current_language_label="$(printf '%s' "$payload" | python3 -c 'import json, sys; payload = json.load(sys.stdin); print(payload.get("language", {}).get("label", ""))')"
  current_language_value="$(printf '%s' "$payload" | python3 -c 'import json, sys; payload = json.load(sys.stdin); print(payload.get("language", {}).get("value", ""))')"
}

main() {
  local profile_name=""
  local multiple_profiles=false
  local profile_loop_index=0
  local last_profile_index=0
  local canonical_language=""
  local inherited_language=""
  local effective_language=""
  local previous_language_label=""

  parse_arguments "$@"

  load_target_browser_profiles
  if [ "${#target_browser_profiles[@]}" -gt 1 ]; then
    multiple_profiles=true
  fi
  last_profile_index=$((${#target_browser_profiles[@]} - 1))

  if $inherit_macos; then
    [ -z "$requested_language" ] || fail "The --inherit-macos mode does not accept an explicit language argument."
    inherited_language="$(read_macos_preferred_language || true)"
    [ -n "$inherited_language" ] || fail "Could not detect the current macOS preferred language."
    requested_language="$inherited_language"
  fi

  if [ -n "$requested_language" ]; then
    canonical_language="$(canonicalize_requested_language "$requested_language")"
  fi

  for profile_name in "${target_browser_profiles[@]}"; do
    load_atlassian_current_state "$profile_name"
    [ -n "$current_language_label" ] || fail "Could not detect the current Atlassian account language from Safari."

    if $multiple_profiles; then
      if [ -n "$profile_name" ]; then
        echo "Browser profile: $profile_name"
      else
        echo "Browser profile: default"
      fi
    fi

    if [ -z "$canonical_language" ]; then
      echo "Current Atlassian account language: $current_language_label"
      if [ "$profile_loop_index" -lt "$last_profile_index" ]; then
        echo
      fi
      profile_loop_index=$((profile_loop_index + 1))
      continue
    fi

    effective_language="$canonical_language"
    if [ "$current_language_label" = "$effective_language" ]; then
      echo "Atlassian account language is already set to $effective_language."
      if [ "$profile_loop_index" -lt "$last_profile_index" ]; then
        echo
      fi
      profile_loop_index=$((profile_loop_index + 1))
      continue
    fi

    if $dry_run; then
      echo "Current Atlassian account language: $current_language_label"
      echo "New Atlassian account language: $effective_language"
      echo "Would change the Atlassian account language in Safari."
      if [ "$profile_loop_index" -lt "$last_profile_index" ]; then
        echo
      fi
      profile_loop_index=$((profile_loop_index + 1))
      continue
    fi

    previous_language_label="$current_language_label"
    run_helper_for_profile "$profile_name" write "$effective_language"
    load_atlassian_current_state "$profile_name"
    echo "Changed Atlassian account language from $previous_language_label to $effective_language."
    if [ "$profile_loop_index" -lt "$last_profile_index" ]; then
      echo
    fi
    profile_loop_index=$((profile_loop_index + 1))
  done
}

main "$@"
