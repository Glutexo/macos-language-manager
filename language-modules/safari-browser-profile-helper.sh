run_applescript() {
  osascript - "$@"
}

read_profile_cache() {
  [ -r "$profile_cache_path" ] || return 1

  awk 'NF && !seen[$0]++' "$profile_cache_path"
}

write_profile_cache() {
  local cache_dir=""

  cache_dir="$(dirname "$profile_cache_path")"
  mkdir -p "$cache_dir"
  awk 'NF && !seen[$0]++' >"$profile_cache_path"
}

find_safari_tabs_db() {
  local candidate=""

  for candidate in \
    "$safari_tabs_db_override" \
    "$HOME/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db" \
    "$HOME/Library/Containers/Safari/Data/Library/Safari/SafariTabs.db"
  do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

list_browser_profiles() {
  local safari_tabs_db=""
  local detected_profiles=""

  if [ -n "$browser_profiles_override" ]; then
    printf '%s\n' "$browser_profiles_override" | while IFS= read -r profile_name; do
      [ -n "$profile_name" ] || continue
      printf '%s\n' "$profile_name"
    done
    return 0
  fi

  if read_profile_cache >/dev/null 2>&1; then
    read_profile_cache
    return 0
  fi

  safari_tabs_db="$(find_safari_tabs_db 2>/dev/null || true)"
  if [ -n "$safari_tabs_db" ]; then
    detected_profiles="$(
      sqlite3 -readonly "$safari_tabs_db" "
        SELECT CASE
          WHEN external_uuid = 'DefaultProfile' THEN 'default'
          WHEN title = '' THEN external_uuid
          ELSE title
        END AS profile_name
        FROM bookmarks
        WHERE type = 1 AND subtype = 2
        ORDER BY CASE WHEN external_uuid = 'DefaultProfile' THEN 0 ELSE 1 END, order_index, id;
      " 2>/dev/null | awk 'NF && !seen[$0]++' || true
    )"
    if [ -n "$detected_profiles" ]; then
      printf '%s\n' "$detected_profiles"
      return 0
    fi
  fi

  printf 'default\n'
}

refresh_browser_profiles() {
  local raw_menu_data=""
  local profile_names=""

  if [ -n "$browser_profile_menu_data_override" ]; then
    raw_menu_data="${browser_profile_menu_data_override}"
  elif [ -n "$browser_profile_menu_items_override" ]; then
    raw_menu_data="${browser_profile_menu_items_override}"
  else
    raw_menu_data="$(run_applescript <<'APPLESCRIPT'
tell application "Safari"
  activate
end tell

tell application "System Events"
  tell process "Safari"
    set frontmost to true
    repeat 30 times
      try
        set out to ""
        tell menu 1 of menu bar item 3 of menu bar 1
          repeat with currentMenuItem in every menu item
            try
              set itemIdentifier to value of attribute "AXIdentifier" of currentMenuItem as text
            on error
              set itemIdentifier to ""
            end try
            try
              set itemTitle to name of currentMenuItem as text
            on error
              set itemTitle to ""
            end try
            set out to out & itemIdentifier & tab & itemTitle & linefeed
          end repeat
        end tell
        return out
      on error
        delay 0.2
      end try
    end repeat
  end tell
end tell

error "Could not read Safari's File menu."
APPLESCRIPT
)"
  fi

  profile_names="$(
    RAW_MENU_DATA="$raw_menu_data" python3 - <<'PY'
import os
import re

raw = os.environ["RAW_MENU_DATA"]
items = [part.rstrip("\n") for part in raw.splitlines() if part.strip()]
profiles = []

for item in items:
    if "\t" in item:
        identifier, title = item.split("\t", 1)
    else:
        identifier, title = "", item

    identifier = identifier.strip()
    title = title.strip()
    if not title or title == "missing value":
        title = ""

    match = re.fullmatch(r"New(.+)Window\?isDefaultProfile=(true|false)", identifier)
    if match:
        profiles.append(match.group(1))
        continue

    match = re.search(r'[\"“”„«»「」『』](.+?)[\"“”„«»「」『』]', title)
    if match:
        profiles.append(match.group(1))

seen = set()
for profile in profiles:
    if profile and profile not in seen:
        print(profile)
        seen.add(profile)

if not seen:
    print("default")
PY
  )"

  printf '%s\n' "$profile_names" | write_profile_cache
  printf '%s\n' "$profile_names"
}

ensure_valid_browser_profile() {
  local candidate="$1"

  [ -n "$candidate" ] || return 0

  if list_browser_profiles | rg -Fx -- "$candidate" >/dev/null 2>&1; then
    return 0
  fi

  fail "Unknown browser profile: $candidate"
}

safari_open_profile_page() {
  local url="$1"
  local profile_name="$2"
  local separator='?'

  if [[ "$url" == *\?* ]]; then
    separator='&'
  fi
  url="${url}${separator}codex_session=${session_marker}"

  env \
    "SAFARI_TARGET_URL_ENV_VAR=$safari_target_url_env_var" \
    "SAFARI_TARGET_PROFILE_ENV_VAR=$safari_target_profile_env_var" \
    "$safari_target_url_env_var=$url" \
    "$safari_target_profile_env_var=$profile_name" \
    osascript - <<'APPLESCRIPT'
set targetUrl to system attribute (system attribute "SAFARI_TARGET_URL_ENV_VAR")
set targetProfile to system attribute (system attribute "SAFARI_TARGET_PROFILE_ENV_VAR")

tell application "Safari"
  activate
  set existingIds to id of every window
end tell

tell application "System Events"
  tell process "Safari"
    set frontmost to true
    if targetProfile is "" or targetProfile is "default" then
      click menu item 1 of menu 1 of menu bar item 3 of menu bar 1
    else
      set profileMenuItem to missing value
      repeat with currentMenuItem in every menu item of menu 1 of menu bar item 3 of menu bar 1
        try
          set currentIdentifier to value of attribute "AXIdentifier" of currentMenuItem as text
        on error
          set currentIdentifier to ""
        end try
        try
          set currentTitle to name of currentMenuItem as text
        on error
          set currentTitle to ""
        end try
        if currentIdentifier starts with "New" and currentIdentifier contains "Window?isDefaultProfile=" then
          set identifierSuffixOffset to offset of "Window?isDefaultProfile=" in currentIdentifier
          if identifierSuffixOffset > 0 then
            set profileIdentifierName to text 4 thru (identifierSuffixOffset - 1) of currentIdentifier
          else
            set profileIdentifierName to ""
          end if
          if targetProfile is "default" then
            if currentIdentifier ends with "isDefaultProfile=true" then
              set profileMenuItem to currentMenuItem
              exit repeat
            end if
          else if profileIdentifierName is targetProfile then
            set profileMenuItem to currentMenuItem
            exit repeat
          end if
        else if targetProfile is not "default" and currentTitle contains targetProfile then
          set profileMenuItem to currentMenuItem
          exit repeat
        end if
      end repeat
      if profileMenuItem is missing value then
        error "Could not locate Safari's profile menu item for " & targetProfile
      end if
      click profileMenuItem
    end if
  end tell
end tell

delay 0.2

tell application "Safari"
  repeat 60 times
    repeat with currentWindow in windows
      if existingIds does not contain (id of currentWindow) then
        set URL of current tab of currentWindow to targetUrl
        return id of currentWindow
      end if
    end repeat
    delay 0.2
  end repeat
end tell

error "Could not create a dedicated Safari window for browser profile " & targetProfile
APPLESCRIPT
}

safari_open_page() {
  local url="$1"
  local separator='?'

  if [ -n "$browser_profile" ] || [ "$open_default_browser_profile_mode" = "profile-window" ]; then
    safari_open_profile_page "$url" "$browser_profile"
    return 0
  fi

  if [[ "$url" == *\?* ]]; then
    separator='&'
  fi
  url="${url}${separator}codex_session=${session_marker}"

  run_applescript "$url" <<'APPLESCRIPT'
on run argv
  set targetUrl to item 1 of argv
  tell application "Safari"
    activate
    set newDocument to make new document
    delay 0.2
    set URL of newDocument to targetUrl
    repeat with currentWindow in windows
      try
        if (current tab of currentWindow) is newDocument then
          return id of currentWindow
        end if
      end try
    end repeat
    return id of front window
  end tell
end run
APPLESCRIPT
}

safari_eval_js() {
  local script="$1"

  env \
    "SAFARI_JS_ENV_VAR=$safari_js_env_var" \
    "SAFARI_SESSION_ENV_VAR=$safari_session_env_var" \
    "SAFARI_WINDOW_ID_ENV_VAR=$safari_window_id_env_var" \
    "$safari_js_env_var=$script" \
    "$safari_session_env_var=$session_marker" \
    "$safari_window_id_env_var=${window_id:-}" \
    osascript - <<'APPLESCRIPT'
set jsSource to system attribute (system attribute "SAFARI_JS_ENV_VAR")
set sessionMarker to system attribute (system attribute "SAFARI_SESSION_ENV_VAR")
set rawWindowId to system attribute (system attribute "SAFARI_WINDOW_ID_ENV_VAR")
set targetWindowId to 0
if rawWindowId is not "" then
  set targetWindowId to rawWindowId as integer
end if
tell application "Safari"
  if (count of documents) is 0 then
    error "Safari has no open document."
  end if
  if targetWindowId is not 0 then
    try
      return do JavaScript jsSource in current tab of (first window whose id is targetWindowId)
    end try
  end if
  repeat with currentWindow in windows
    try
      if (URL of current tab of currentWindow) contains sessionMarker then
        return do JavaScript jsSource in current tab of currentWindow
      end if
    end try
  end repeat
  repeat with currentDocument in documents
    try
      if (URL of currentDocument) contains sessionMarker then
        return do JavaScript jsSource in currentDocument
      end if
    end try
  end repeat
  error "Could not locate the dedicated Safari document for session " & sessionMarker
end tell
APPLESCRIPT
}

json_extract() {
  local field="$1"
  python3 -c 'import json, sys
data = json.load(sys.stdin)
value = data
for part in sys.argv[1].split("."):
    value = value[part]
if isinstance(value, list):
    print("\n".join(value))
else:
    print(value)' "$field"
}

requested_json_from_args() {
  REQUESTED_LANGUAGES="$(printf '%s\n' "$@")" python3 - <<'PY'
import json
import os

print(json.dumps([line.strip() for line in os.environ["REQUESTED_LANGUAGES"].splitlines() if line.strip()]))
PY
}
