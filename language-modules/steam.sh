module_init() {
  module_key="steam"
  module_display_name="Steam"
  module_storage_label="registry file"
  module_example_language="cs"
  module_example_dry_run_language="ja"
  module_alias_help="ISO aliases such as bg, cs, da, de, el, en, es, es-419, fi, fr, hu, id, it, ja, ko, nl, no, pl, pt, pt-BR, ro, ru, sv, th, tr, uk, vi, zh-CN, and zh-TW are also accepted."
  steam_dir="${STEAM_DIR:-$HOME/Library/Application Support/Steam}"
  steam_registry_file="$steam_dir/registry.vdf"
  module_supported_languages=(
    bulgarian schinese tchinese czech danish dutch english finnish french german greek
    hungarian indonesian italian japanese koreana norwegian polish portuguese brazilian
    romanian russian spanish latam swedish thai turkish ukrainian vietnamese
  )
}

module_primary_path() {
  echo "$steam_registry_file"
}

module_backup_paths() {
  echo "$steam_registry_file"
}

module_validate_backup_paths() {
  local backup_path=""

  for backup_path in "$@"; do
    [ -f "$backup_path" ] || fail "Steam backup source file not found: $backup_path"
    [ -r "$backup_path" ] || fail "Steam backup source file is not readable: $backup_path"
  done
}

module_ensure_storage_exists() {
  [ -f "$steam_registry_file" ] || fail "Steam registry file not found: $steam_registry_file"
}

module_print_supported_languages() {
  printf '  %s\n' "${module_supported_languages[@]}"
}

module_print_aliases() {
  cat <<'EOF'
  bg -> bulgarian
  cs -> czech
  da -> danish
  de -> german
  el -> greek
  en -> english
  es -> spanish
  es-419 -> latam
  es-latam -> latam
  fi -> finnish
  fr -> french
  hu -> hungarian
  id -> indonesian
  it -> italian
  ja -> japanese
  ko -> koreana
  nl -> dutch
  no -> norwegian
  nb -> norwegian
  pl -> polish
  pt -> portuguese
  pt-BR -> brazilian
  ro -> romanian
  ru -> russian
  sv -> swedish
  th -> thai
  tr -> turkish
  uk -> ukrainian
  vi -> vietnamese
  zh -> schinese
  zh-CN -> schinese
  zh-Hans -> schinese
  zh-TW -> tchinese
  zh-Hant -> tchinese
EOF
}

module_canonicalize_language() {
  local original_language="$1"
  local language="$1"
  local supported_language

  case "$language" in
    [A-Za-z][A-Za-z_-]*)
      ;;
    *)
      fail "Invalid Steam language value: $language"
      ;;
  esac

  language="${language//_/-}"
  language="$(printf '%s' "$language" | tr '[:upper:]' '[:lower:]')"

  case "$language" in
    bg) language="bulgarian" ;;
    zh|zh-cn|zh-hans) language="schinese" ;;
    zh-tw|zh-hant) language="tchinese" ;;
    cs) language="czech" ;;
    da) language="danish" ;;
    nl) language="dutch" ;;
    en) language="english" ;;
    fi) language="finnish" ;;
    fr) language="french" ;;
    de) language="german" ;;
    el) language="greek" ;;
    hu) language="hungarian" ;;
    id) language="indonesian" ;;
    it) language="italian" ;;
    ja) language="japanese" ;;
    ko) language="koreana" ;;
    nb|no) language="norwegian" ;;
    pl) language="polish" ;;
    pt) language="portuguese" ;;
    pt-br) language="brazilian" ;;
    ro) language="romanian" ;;
    ru) language="russian" ;;
    es) language="spanish" ;;
    es-419|es-xl|es-latam) language="latam" ;;
    sv) language="swedish" ;;
    th) language="thai" ;;
    tr) language="turkish" ;;
    uk) language="ukrainian" ;;
    vi) language="vietnamese" ;;
  esac

  for supported_language in "${module_supported_languages[@]}"; do
    if [ "$language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Steam interface language: $original_language"
}

module_is_running() {
  pgrep -x Steam >/dev/null 2>&1
}

module_read_current_language() {
  local current_language=""

  current_language="$(perl -0ne '
    if (/"steamglobal"\s*\{\s*"language"\s*"([^"]+)"/s) {
      print "$1\n";
      exit;
    }
  ' "$steam_registry_file")"

  if [ -n "$current_language" ]; then
    echo "$current_language"
    return 0
  fi

  perl -0ne '
    if (/"language"\s*"([^"]+)"/) {
      print "$1\n";
      exit;
    }
  ' "$steam_registry_file"
}

module_write_language() {
  REGISTRY_FILE="$steam_registry_file" REQUESTED_LANGUAGE="$1" perl -0pi -e '
    my $language = $ENV{REQUESTED_LANGUAGE};
    my $changed = 0;

    $changed += s/("steamglobal"\s*\{\s*"language"\s*")([^"]+)(")/${1}${language}${3}/sg;
    $changed += s/("Steamsteamglobal"\s*\{\s*"language"\s*")([^"]+)(")/${1}${language}${3}/sg;
    $changed += s/("Steam"\s*\{.*?"steamglobal"\s*\{\s*"language"\s*"[^"]+"\s*\}\s*"language"\s*")([^"]+)(")/${1}${language}${3}/sg;

    if (!$changed) {
      die "No Steam language entries were updated\n";
    }
  ' "$steam_registry_file"
}
