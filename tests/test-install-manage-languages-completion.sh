#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/install-manage-languages-completion.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $message"
    echo "Missing: $needle"
    printf '%s\n' "$haystack"
    exit 1
  fi
}

zsh_rc="$tmp_dir/.zshrc"
bash_rc="$tmp_dir/.bashrc"

output="$(SHELL=/bin/zsh "$script" --rc-file "$zsh_rc")"
assert_contains "$output" "Installed completion block into $zsh_rc" "auto mode should install into custom zsh rc file"
assert_contains "$(cat "$zsh_rc")" '# manage-languages completion start' "installer should add start marker"
assert_contains "$(cat "$zsh_rc")" 'source "'"$repo_root"'/completions/manage-languages.zsh"' "installer should add zsh completion source line"

output="$(SHELL=/bin/zsh "$script" --rc-file "$zsh_rc")"
assert_contains "$output" "Updated completion block in $zsh_rc" "second run should update existing block"
count="$(grep -c 'manage-languages completion start' "$zsh_rc")"
[ "$count" = "1" ] || { echo "FAIL: installer should keep a single managed block"; exit 1; }

output="$(SHELL=/bin/zsh "$script" --shell bash --rc-file "$bash_rc")"
assert_contains "$output" "Installed completion block into $bash_rc" "explicit shell mode should install into custom bash rc file"
assert_contains "$(cat "$bash_rc")" 'source "'"$repo_root"'/completions/manage-languages.bash"' "installer should add bash completion source line"

output="$(( "$script" --shell fish --rc-file "$tmp_dir/.config/fish/config.fish" ) 2>&1 || true)"
assert_contains "$output" "Unsupported shell: fish" "unsupported shells should fail clearly"

printf 'All installer tests passed.\n'
