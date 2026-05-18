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

assert_symlink_target() {
  local link_path="$1"
  local expected_target="$2"
  local actual_target=""

  actual_target="$(readlink "$link_path")"
  if [ "$actual_target" != "$expected_target" ]; then
    echo "FAIL: unexpected symlink target"
    echo "Expected: $expected_target"
    echo "Actual:   $actual_target"
    exit 1
  fi
}

zsh_rc="$tmp_dir/.zshrc"
zsh_completion_dir="$tmp_dir/zsh-completions"
bash_rc="$tmp_dir/.bashrc"
bash_completion_dir="$tmp_dir/bash-completions"

output="$(SHELL=/bin/zsh "$script" --rc-file "$zsh_rc" --completion-dir "$zsh_completion_dir")"
assert_contains "$output" "Installed completion loader block into $zsh_rc" "auto mode should install loader into custom zsh rc file"
assert_contains "$output" "Linked completion file to $zsh_completion_dir/manage-languages.zsh" "installer should link zsh completion file"
assert_contains "$(cat "$zsh_rc")" '# manage-languages completion loader start' "installer should add loader start marker"
assert_contains "$(cat "$zsh_rc")" "for completion_file in \"$zsh_completion_dir\"/*.zsh; do" "installer should source every zsh completion in the directory"
assert_symlink_target "$zsh_completion_dir/manage-languages.zsh" "$repo_root/completions/manage-languages.zsh"

output="$(SHELL=/bin/zsh "$script" --rc-file "$zsh_rc" --completion-dir "$zsh_completion_dir")"
assert_contains "$output" "Updated completion loader block in $zsh_rc" "second run should update existing loader block"
count="$(grep -c 'manage-languages completion loader start' "$zsh_rc")"
[ "$count" = "1" ] || { echo "FAIL: installer should keep a single managed loader block"; exit 1; }

output="$(SHELL=/bin/zsh "$script" --shell bash --rc-file "$bash_rc" --completion-dir "$bash_completion_dir")"
assert_contains "$output" "Installed completion loader block into $bash_rc" "explicit shell mode should install loader into custom bash rc file"
assert_contains "$output" "Linked completion file to $bash_completion_dir/manage-languages.bash" "installer should link bash completion file"
assert_contains "$(cat "$bash_rc")" "for completion_file in \"$bash_completion_dir\"/*.bash; do" "installer should source every bash completion in the directory"
assert_symlink_target "$bash_completion_dir/manage-languages.bash" "$repo_root/completions/manage-languages.bash"

output="$(( "$script" --shell fish --rc-file "$tmp_dir/.config/fish/config.fish" ) 2>&1 || true)"
assert_contains "$output" "Unsupported shell: fish" "unsupported shells should fail clearly"

printf 'All installer tests passed.\n'
