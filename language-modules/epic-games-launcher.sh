module_init() {
  module_key="epic-games-launcher"
  module_display_name="Epic Games Launcher"
  module_storage_label="preferences file"
  module_example_language="cs"
  module_example_dry_run_language="system"
  module_alias_help="Use system to remove the explicit launcher override and let Epic follow macOS directly."
  module_supports_bulk="true"
  epic_games_launcher_preferences_dir="${EPIC_GAMES_LAUNCHER_PREFERENCES_DIR:-$HOME/Library/Preferences/Unreal Engine/EpicGamesLauncher}"
  epic_games_launcher_settings_file="$epic_games_launcher_preferences_dir/Mac/GameUserSettings.ini"
  epic_games_launcher_process_match="${EPIC_GAMES_LAUNCHER_PROCESS_MATCH:-/Applications/Epic Games Launcher.app/Contents/MacOS/EpicGamesLauncher-Mac-Shipping}"
  module_supported_languages=(
    system ar bg cs da de el en es es-ES es-MX fi fil fr hi hu id it ja ko ms nl no pl pt pt-BR
    ro ru sv th tr uk vi zh-CN zh-Hans zh-Hant
  )
}

module_primary_path() {
  echo "$epic_games_launcher_settings_file"
}

module_backup_paths() {
  echo "$epic_games_launcher_settings_file"
}

module_validate_backup_paths() {
  local backup_path=""

  for backup_path in "$@"; do
    [ -f "$backup_path" ] || fail "Epic Games Launcher preferences file not found: $backup_path"
    [ -r "$backup_path" ] || fail "Epic Games Launcher preferences file is not readable: $backup_path"
  done
}

module_prepare_storage_for_write() {
  local requested_language="$1"

  mkdir -p "$(dirname "$epic_games_launcher_settings_file")"

  if [ ! -f "$epic_games_launcher_settings_file" ]; then
    cat <<'EOF' >"$epic_games_launcher_settings_file"
[Internationalization]
EOF
  fi

  if [ ! -r "$epic_games_launcher_settings_file" ]; then
    fail "Epic Games Launcher preferences file is not readable: $epic_games_launcher_settings_file"
  fi

  if [ "$requested_language" = "system" ]; then
    return 0
  fi
}

module_ensure_storage_exists() {
  if [ -e "$epic_games_launcher_settings_file" ] && [ ! -r "$epic_games_launcher_settings_file" ]; then
    fail "Epic Games Launcher preferences file is not readable: $epic_games_launcher_settings_file"
  fi
}

module_print_supported_languages() {
  printf '  %s\n' "${module_supported_languages[@]}"
}

module_print_aliases() {
  cat <<'EOF'
  default -> system
  os -> system
  use-system -> system
  en-US -> en
  en-GB -> en
  es-419 -> es-MX
  es-LATAM -> es-MX
  nb -> no
  no-NO -> no
  pt-PT -> pt
  zh -> zh-Hans
  zh-SG -> zh-Hans
  zh-TW -> zh-Hant
  zh-HK -> zh-Hant
EOF
}

module_canonicalize_language() {
  local original_language="$1"
  local normalized_language=""
  local exact_supported_language=""
  local primary_language=""
  local secondary_part=""
  local supported_language=""

  case "$original_language" in
    [A-Za-z][A-Za-z0-9_-]*) ;;
    *) fail "Invalid Epic Games Launcher language value: $original_language" ;;
  esac

  normalized_language="${original_language//_/-}"

  case "$(printf '%s' "$normalized_language" | tr '[:upper:]' '[:lower:]')" in
    system|default|os|use-system) normalized_language="system" ;;
    en|en-us|en-gb) normalized_language="en" ;;
    es-419|es-latam|es-mx) normalized_language="es-MX" ;;
    es-es) normalized_language="es-ES" ;;
    nb|no|no-no) normalized_language="no" ;;
    pt|pt-pt) normalized_language="pt" ;;
    pt-br) normalized_language="pt-BR" ;;
    zh|zh-sg|zh-cn|zh-hans) normalized_language="zh-Hans" ;;
    zh-tw|zh-hk|zh-hant) normalized_language="zh-Hant" ;;
    *)
      if [[ "$normalized_language" == *-* ]]; then
        primary_language="${normalized_language%%-*}"
        secondary_part="${normalized_language#*-}"
        normalized_language="$(printf '%s' "$primary_language" | tr '[:upper:]' '[:lower:]')-$secondary_part"

        case "$primary_language" in
          zh)
            case "$(printf '%s' "$secondary_part" | tr '[:upper:]' '[:lower:]')" in
              hant|tw|hk) normalized_language="zh-Hant" ;;
              hans|cn|sg) normalized_language="zh-Hans" ;;
            esac
            ;;
          pt)
            case "$(printf '%s' "$secondary_part" | tr '[:upper:]' '[:lower:]')" in
              br) normalized_language="pt-BR" ;;
              pt) normalized_language="pt" ;;
            esac
            ;;
          es)
            case "$(printf '%s' "$secondary_part" | tr '[:upper:]' '[:lower:]')" in
              es) normalized_language="es-ES" ;;
              419|mx|latam) normalized_language="es-MX" ;;
            esac
            ;;
          en) normalized_language="en" ;;
          no|nb) normalized_language="no" ;;
        esac
      else
        normalized_language="$(printf '%s' "$normalized_language" | tr '[:upper:]' '[:lower:]')"
      fi
      ;;
  esac

  for exact_supported_language in "${module_supported_languages[@]}"; do
    if [ "$normalized_language" = "$exact_supported_language" ]; then
      printf '%s\n' "$exact_supported_language"
      return 0
    fi
  done

  if [[ "$normalized_language" == *-* ]]; then
    primary_language="${normalized_language%%-*}"
    case "$primary_language" in
      en) normalized_language="en" ;;
      es) normalized_language="es" ;;
      no|nb) normalized_language="no" ;;
      pt) normalized_language="pt" ;;
      zh) normalized_language="zh-Hans" ;;
      *) normalized_language="$primary_language" ;;
    esac
  fi

  for supported_language in "${module_supported_languages[@]}"; do
    if [ "$normalized_language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Epic Games Launcher interface language: $original_language"
}

module_is_running() {
  pgrep -f "$epic_games_launcher_process_match" >/dev/null 2>&1
}

module_read_current_language() {
  SETTINGS_FILE="$epic_games_launcher_settings_file" python3 - <<'PY'
import os
import sys

path = os.environ["SETTINGS_FILE"]

if not os.path.exists(path):
    print("system")
    raise SystemExit(0)

with open(path, "r", encoding="utf-8") as handle:
    lines = handle.readlines()

in_internationalization = False
for raw_line in lines:
    stripped = raw_line.strip()

    if stripped.startswith("[") and stripped.endswith("]"):
        in_internationalization = stripped == "[Internationalization]"
        continue

    if not in_internationalization:
        continue

    if not stripped or stripped.startswith(";") or stripped.startswith("#"):
        continue

    key, separator, value = stripped.partition("=")
    if not separator:
      continue

    if key.strip() == "Culture":
        value = value.strip()
        print(value or "system")
        raise SystemExit(0)

print("system")
PY
}

module_write_language() {
  SETTINGS_FILE="$epic_games_launcher_settings_file" REQUESTED_LANGUAGE="$1" python3 - <<'PY'
import os
import re
import sys

path = os.environ["SETTINGS_FILE"]
language = os.environ["REQUESTED_LANGUAGE"]

with open(path, "r", encoding="utf-8") as handle:
    content = handle.read()

section_pattern = re.compile(r"(^\s*\[Internationalization\]\s*$)(.*?)(?=^\s*\[|\Z)", re.MULTILINE | re.DOTALL)
match = section_pattern.search(content)

if match:
    section_body = match.group(2)
else:
    if content and not content.endswith("\n"):
        content += "\n"
    content += "[Internationalization]\n"
    match = section_pattern.search(content)
    if not match:
        print(f"Could not create the [Internationalization] section in {path}", file=sys.stderr)
        sys.exit(1)
    section_body = match.group(2)

updated_body = re.sub(r"^(\s*)(Culture|Language)\s*=.*(?:\n|$)", "", section_body, flags=re.MULTILINE)

if language != "system":
    updated_body = re.sub(
        r"^(\s*Culture\s*=\s*).*$",
        rf"\1{language}",
        updated_body,
        count=1,
        flags=re.MULTILINE,
    )
    if f"Culture={language}" not in updated_body and f"Culture = {language}" not in updated_body:
        if updated_body and not updated_body.startswith("\n"):
            updated_body = "\n" + updated_body
        updated_body = f"\nCulture={language}" + updated_body

if updated_body and not updated_body.endswith("\n"):
    updated_body += "\n"

updated_content = content[: match.start(2)] + updated_body + content[match.end(2) :]

with open(path, "w", encoding="utf-8") as handle:
    handle.write(updated_content)
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
