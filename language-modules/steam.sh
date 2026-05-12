module_init() {
  module_key="steam"
  module_display_name="Steam"
  module_storage_label="registry file"
  module_example_language="czech"
  module_example_dry_run_language="japanese"
  module_alias_help=""
  steam_dir="${STEAM_DIR:-$HOME/Library/Application Support/Steam}"
  steam_registry_file="$steam_dir/registry.vdf"
  module_supported_languages=(
    bulgarian schinese tchinese czech danish dutch english finnish french german greek
    hungarian indonesian italian japanese koreana norwegian polish portuguese brazilian
    romanian russian spanish latam swedish thai turkish ukrainian vietnamese
  )
}

module_storage_path() {
  echo "$steam_registry_file"
}

module_ensure_storage_exists() {
  [ -f "$steam_registry_file" ] || fail "Steam registry file not found: $steam_registry_file"
}

module_print_supported_languages() {
  printf '  %s\n' "${module_supported_languages[@]}"
}

module_canonicalize_language() {
  local language="$1"
  local supported_language

  case "$language" in
    [a-z]*) ;;
    *) fail "Invalid Steam language value: $language" ;;
  esac

  for supported_language in "${module_supported_languages[@]}"; do
    if [ "$language" = "$supported_language" ]; then
      printf '%s\n' "$supported_language"
      return 0
    fi
  done

  fail "Unsupported Steam interface language: $language"
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
