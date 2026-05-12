module_init() {
  module_key="factorio"
  module_display_name="Factorio"
  module_storage_label="config file"
  module_example_language="cs"
  module_example_dry_run_language="zh-CN"
  module_alias_help="Short aliases such as es, ga, fy, pt, sv, or zh are also accepted when they map to one supported value."
  factorio_dir="${FACTORIO_DIR:-$HOME/Library/Application Support/factorio}"
  factorio_config_file="$factorio_dir/config/config.ini"
  module_supported_languages=(
    af ar be bg ca cs da de el en eo es-ES et eu fa fi fil fr fy-NL ga-IE he hr hu id is it ja
    ka kk ko lt lv nl no pl pt-BR pt-PT ro ru sk sl sq sr sv-SE th tr uk vi zh-CN zh-TW
  )
}

module_primary_path() {
  echo "$factorio_config_file"
}

module_backup_paths() {
  echo "$factorio_config_file"
}

module_ensure_storage_exists() {
  [ -f "$factorio_config_file" ] || fail "Factorio config file not found: $factorio_config_file"
}

module_print_supported_languages() {
  printf '  %s\n' "${module_supported_languages[@]}"
}

module_canonicalize_language() {
  local original_language="$1"
  local normalized_language=""
  local supported_language=""

  case "$original_language" in
    [A-Za-z][A-Za-z_-]*) ;;
    *) fail "Invalid Factorio language value: $original_language" ;;
  esac

  normalized_language="${original_language//_/-}"
  normalized_language="$(printf '%s' "$normalized_language" | tr '[:upper:]' '[:lower:]')"

  case "$normalized_language" in
    es|es-es) normalized_language="es-ES" ;;
    fy|fy-nl) normalized_language="fy-NL" ;;
    ga|ga-ie) normalized_language="ga-IE" ;;
    pt|pt-pt) normalized_language="pt-PT" ;;
    pt-br) normalized_language="pt-BR" ;;
    sv|sv-se) normalized_language="sv-SE" ;;
    zh|zh-cn) normalized_language="zh-CN" ;;
    zh-tw) normalized_language="zh-TW" ;;
    *)
      if [[ "$normalized_language" == *-* ]]; then
        local language_part="${normalized_language%%-*}"
        local region_part="${normalized_language#*-}"
        normalized_language="${language_part}-$(printf '%s' "$region_part" | tr '[:lower:]' '[:upper:]')"
      fi
      ;;
  esac

  for supported_language in "${module_supported_languages[@]}"; do
    if [ "$normalized_language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Factorio interface language: $original_language"
}

module_is_running() {
  pgrep -x factorio >/dev/null 2>&1 || pgrep -x Factorio >/dev/null 2>&1
}

module_read_current_language() {
  awk '
    BEGIN { in_general = 0 }
    /^[[:space:]]*;/ { next }
    /^[[:space:]]*\[/ {
      in_general = ($0 ~ /^[[:space:]]*\[general\][[:space:]]*$/)
      next
    }
    in_general && /^[[:space:]]*locale[[:space:]]*=/ {
      sub(/^[[:space:]]*locale[[:space:]]*=[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$factorio_config_file"
}

module_write_language() {
  CONFIG_FILE="$factorio_config_file" REQUESTED_LANGUAGE="$1" python3 - <<'PY'
import os
import re
import sys

path = os.environ["CONFIG_FILE"]
language = os.environ["REQUESTED_LANGUAGE"]

with open(path, "r", encoding="utf-8") as handle:
    content = handle.read()

pattern = re.compile(r"(^\s*\[general\]\s*$)(.*?)(?=^\s*\[|\Z)", re.MULTILINE | re.DOTALL)
match = pattern.search(content)
if not match:
    print(f"Could not find the [general] section in {path}", file=sys.stderr)
    sys.exit(1)

section_body = match.group(2)
updated_body, replacements = re.subn(
    r"^(\s*locale\s*=\s*).*$",
    rf"\1{language}",
    section_body,
    count=1,
    flags=re.MULTILINE,
)

if replacements == 0:
    if updated_body and not updated_body.endswith("\n"):
        updated_body += "\n"
    updated_body = f"locale={language}\n" + updated_body

updated_content = content[: match.start(2)] + updated_body + content[match.end(2) :]

with open(path, "w", encoding="utf-8") as handle:
    handle.write(updated_content)
PY
}
