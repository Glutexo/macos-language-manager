list_available_browser_profiles() {
  "$helper_command" list-profiles
}

refresh_available_browser_profiles() {
  "$helper_command" refresh-profiles
}

run_helper_for_profile() {
  local profile_name="$1"
  shift

  if [ -n "$profile_name" ]; then
    env "$helper_browser_profile_env_var=$profile_name" "$helper_command" "$@"
  else
    "$helper_command" "$@"
  fi
}

load_target_browser_profiles() {
  local available_profiles=()
  local line=""
  local requested_profile=""
  local found=false

  if ! $all_browser_profiles && ! $all_known_browser_profiles && [ "${#selected_browser_profiles[@]}" -eq 0 ]; then
    target_browser_profiles=("")
    return 0
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    available_profiles+=("$line")
  done < <(list_available_browser_profiles)

  [ "${#available_profiles[@]}" -gt 0 ] || fail "No valid browser profiles were found."

  if $all_browser_profiles || $all_known_browser_profiles; then
    target_browser_profiles=("${available_profiles[@]}")
    return 0
  fi

  target_browser_profiles=()
  for requested_profile in "${selected_browser_profiles[@]}"; do
    found=false
    for line in "${available_profiles[@]}"; do
      if [ "$line" = "$requested_profile" ]; then
        found=true
        break
      fi
    done
    if ! $found; then
      fail "Unknown browser profile: $requested_profile"
    fi
    target_browser_profiles+=("$requested_profile")
  done
}
