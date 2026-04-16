#!/bin/bash
set -euo pipefail

display_command="./manage-steam-language.sh"
steam_dir="${STEAM_DIR:-$HOME/Library/Application Support/Steam}"
registry_file="$steam_dir/registry.vdf"
dry_run=false
force_write=false

show_usage() {
  echo "Read or change the Steam interface language on macOS."
  echo
  echo "Usage: $display_command [--dry-run|-n] [--force|-f] [language]"
  echo
  echo "Options:"
  echo "  --dry-run, -n   Print the planned change without writing it."
  echo "  --force, -f     Write even if Steam appears to be running."
  echo "  --help, -h      Show this help message."
  echo
  echo "Examples:"
  echo "  $display_command"
  echo "  $display_command czech"
  echo "  $display_command --dry-run japanese"
}

fail() {
  echo "$1" >&2
  exit 1
}

ensure_registry_exists() {
  [ -f "$registry_file" ] || fail "Steam registry file not found: $registry_file"
}

validate_language() {
  local language="$1"

  case "$language" in
    [A-Za-z0-9_-]*)
      return 0
      ;;
  esac

  fail "Invalid Steam language value: $language"
}

is_steam_running() {
  pgrep -x Steam >/dev/null 2>&1
}

print_current_language() {
  local current_language=""

  current_language="$(perl -0ne '
    if (/"steamglobal"\s*\{\s*"language"\s*"([^"]+)"/s) {
      print "$1\n";
      exit;
    }
  ' "$registry_file")"

  if [ -n "$current_language" ]; then
    echo "$current_language"
    return 0
  fi

  current_language="$(perl -0ne '
    if (/"language"\s*"([^"]+)"/) {
      print "$1\n";
      exit;
    }
  ' "$registry_file")"

  [ -n "$current_language" ] || fail "Could not detect the current Steam language in $registry_file"
  echo "$current_language"
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

ensure_registry_exists
current_language="$(print_current_language)"

if [ -z "$requested_language" ]; then
  echo "Current Steam interface language: $current_language"
  exit 0
fi

validate_language "$requested_language"

if [ "$requested_language" = "$current_language" ]; then
  echo "Steam interface language is already set to $requested_language."
  exit 0
fi

if ! $dry_run && ! $force_write && is_steam_running; then
  fail "Steam appears to be running. Quit Steam first, or rerun with --force."
fi

if $dry_run; then
  echo "Would change Steam interface language from $current_language to $requested_language."
  exit 0
fi

backup_file="$registry_file.bak"
cp "$registry_file" "$backup_file"

REGISTRY_FILE="$registry_file" REQUESTED_LANGUAGE="$requested_language" perl -0pi -e '
  my $language = $ENV{REQUESTED_LANGUAGE};
  my $changed = 0;

  $changed += s/("steamglobal"\s*\{\s*"language"\s*")([^"]+)(")/${1}${language}${3}/sg;
  $changed += s/("Steamsteamglobal"\s*\{\s*"language"\s*")([^"]+)(")/${1}${language}${3}/sg;
  $changed += s/("Steam"\s*\{.*?"steamglobal"\s*\{\s*"language"\s*"[^"]+"\s*\}\s*"language"\s*")([^"]+)(")/${1}${language}${3}/sg;

  if (!$changed) {
    die "No Steam language entries were updated\n";
  }
' "$registry_file"

echo "Changed Steam interface language from $current_language to $requested_language."
echo "Backup saved to $backup_file"
echo "Restart Steam to apply the new interface language."
