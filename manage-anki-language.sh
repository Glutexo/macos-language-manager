#!/bin/bash
set -euo pipefail

display_command="./manage-anki-language.sh"
anki_base_dir="${ANKI_BASE_DIR:-$HOME/Library/Application Support/Anki2}"
prefs_file="$anki_base_dir/prefs21.db"
dry_run=false
force_write=false
verbose_help=false
supported_languages=(
  af_ZA
  ar_SA
  be_BY
  bg_BG
  ca_ES
  cs_CZ
  da_DK
  de_DE
  el_GR
  en_GB
  en_US
  eo_UY
  es_ES
  et_EE
  eu_ES
  fa_IR
  fi_FI
  fr_FR
  ga_IE
  gl_ES
  he_IL
  hr_HR
  hu_HU
  hy_AM
  it_IT
  ja_JP
  jbo_EN
  kk_KZ
  ko_KR
  la_LA
  mn_MN
  ms_MY
  nb_NO
  nl_NL
  oc_FR
  or_OR
  pl_PL
  pt_BR
  pt_PT
  ro_RO
  ru_RU
  sk_SK
  sl_SI
  sr_SP
  sv_SE
  th_TH
  tl
  tr_TR
  ug
  uk_UA
  uz_UZ
  vi_VN
  yi
  zh_CN
  zh_TW
)

show_usage() {
  echo "Read or change the Anki interface language on macOS."
  echo
  echo "Usage: $display_command [--dry-run|-n] [--force|-f] [language]"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned change without writing it."
  echo "  --force, -f     Write even if Anki appears to be running."
  echo "  --help, -h      Show this help message. Use --verbose or -v for the supported language list."
  echo "  --verbose, -v   Show help together with supported language values."
  echo
  echo "Examples:"
  echo "  $display_command"
  echo "  $display_command cs_CZ"
  echo "  $display_command --dry-run ja"

  if $verbose_help; then
    echo
    echo "Supported Anki interface language values:"
    printf '  %s\n' "${supported_languages[@]}"
    echo
    echo "Short aliases such as en, cs, ja, pt, or zh are also accepted when they map to one supported value."
  fi
}

fail() {
  echo "$1" >&2
  exit 1
}

ensure_prefs_exists() {
  [ -f "$prefs_file" ] || fail "Anki preferences database not found: $prefs_file"
}

canonicalize_language() {
  local language="$1"
  local supported_language=""

  case "$language" in
    [A-Za-z_-]*)
      ;;
    *)
      fail "Invalid Anki language value: $language"
      ;;
  esac

  language="${language//-/_}"

  case "$language" in
    af) language="af_ZA" ;;
    ar) language="ar_SA" ;;
    be) language="be_BY" ;;
    bg) language="bg_BG" ;;
    ca) language="ca_ES" ;;
    cs) language="cs_CZ" ;;
    da) language="da_DK" ;;
    de) language="de_DE" ;;
    el) language="el_GR" ;;
    en) language="en_US" ;;
    eo) language="eo_UY" ;;
    es) language="es_ES" ;;
    et) language="et_EE" ;;
    eu) language="eu_ES" ;;
    fa) language="fa_IR" ;;
    fi) language="fi_FI" ;;
    fr) language="fr_FR" ;;
    ga) language="ga_IE" ;;
    gl) language="gl_ES" ;;
    he) language="he_IL" ;;
    hr) language="hr_HR" ;;
    hu) language="hu_HU" ;;
    hy) language="hy_AM" ;;
    it) language="it_IT" ;;
    ja) language="ja_JP" ;;
    jbo) language="jbo_EN" ;;
    kk) language="kk_KZ" ;;
    ko) language="ko_KR" ;;
    la) language="la_LA" ;;
    mn) language="mn_MN" ;;
    ms) language="ms_MY" ;;
    nb|no) language="nb_NO" ;;
    nl) language="nl_NL" ;;
    oc) language="oc_FR" ;;
    or) language="or_OR" ;;
    pl) language="pl_PL" ;;
    pt) language="pt_PT" ;;
    ro) language="ro_RO" ;;
    ru) language="ru_RU" ;;
    sk) language="sk_SK" ;;
    sl) language="sl_SI" ;;
    sr) language="sr_SP" ;;
    sv) language="sv_SE" ;;
    th) language="th_TH" ;;
    tl) language="tl" ;;
    tr) language="tr_TR" ;;
    ug) language="ug" ;;
    uk) language="uk_UA" ;;
    uz) language="uz_UZ" ;;
    vi) language="vi_VN" ;;
    yi) language="yi" ;;
    zh) language="zh_CN" ;;
  esac

  for supported_language in "${supported_languages[@]}"; do
    if [ "$language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Anki interface language: $1"
}

is_anki_running() {
  pgrep -x Anki >/dev/null 2>&1
}

print_current_language() {
  PREFS_FILE="$prefs_file" python3 - <<'PY'
import os
import pickle
import sqlite3
import sys

path = os.environ["PREFS_FILE"]

try:
    conn = sqlite3.connect(path)
    row = conn.execute(
        "select cast(data as blob) from profiles where name = '_global'"
    ).fetchone()
finally:
    try:
        conn.close()
    except Exception:
        pass

if not row or row[0] is None:
    print(f"Could not detect the current Anki language in {path}", file=sys.stderr)
    sys.exit(1)

meta = pickle.loads(row[0])
language = meta.get("defaultLang")
if not isinstance(language, str) or not language:
    print(f"Could not detect the current Anki language in {path}", file=sys.stderr)
    sys.exit(1)

print(language)
PY
}

write_language() {
  PREFS_FILE="$prefs_file" REQUESTED_LANGUAGE="$1" python3 - <<'PY'
import os
import pickle
import sqlite3
import sys

path = os.environ["PREFS_FILE"]
language = os.environ["REQUESTED_LANGUAGE"]

conn = sqlite3.connect(path)
try:
    row = conn.execute(
        "select cast(data as blob) from profiles where name = '_global'"
    ).fetchone()
    if not row or row[0] is None:
        print("Anki global profile metadata not found", file=sys.stderr)
        sys.exit(1)

    meta = pickle.loads(row[0])
    meta["defaultLang"] = language
    conn.execute(
        "update profiles set data = ? where name = '_global'",
        (sqlite3.Binary(pickle.dumps(meta, protocol=4)),),
    )
    conn.commit()
finally:
    conn.close()
PY
}

requested_language=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-n)
      dry_run=true
      ;;
    --force|-f)
      force_write=true
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    --verbose|-v)
      verbose_help=true
      show_usage
      exit 0
      ;;
    -*)
      fail "Unknown option: $1"
      ;;
    *)
      if [ -n "$requested_language" ]; then
        fail "Only one language value can be provided."
      fi
      requested_language="$1"
      ;;
  esac
  shift
done

ensure_prefs_exists
current_language="$(print_current_language)"

if [ -z "$requested_language" ]; then
  echo "Current Anki interface language: $current_language"
  exit 0
fi

requested_language="$(canonicalize_language "$requested_language")"

if [ "$requested_language" = "$current_language" ]; then
  echo "Anki interface language is already set to $requested_language."
  exit 0
fi

if ! $dry_run && ! $force_write && is_anki_running; then
  fail "Anki appears to be running. Quit Anki first, or rerun with --force."
fi

if $dry_run; then
  echo "Would change Anki interface language from $current_language to $requested_language."
  exit 0
fi

backup_file="$prefs_file.bak"
cp "$prefs_file" "$backup_file"
write_language "$requested_language"

echo "Changed Anki interface language from $current_language to $requested_language."
echo "Backup saved to $backup_file"
echo "Restart Anki to apply the new interface language."
