#!/bin/bash
set -euo pipefail

account_preferences_url="${ATLASSIAN_ACCOUNT_LANGUAGE_URL:-https://id.atlassian.com/manage-profile/account-preferences}"
timeout_seconds="${ATLASSIAN_ACCOUNT_LANGUAGE_TIMEOUT:-180}"
session_marker="${ATLASSIAN_ACCOUNT_SAFARI_SESSION:-codex-atlassian-language-$$-$(date +%s)}"
browser_profile="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE:-}"
profile_cache_path="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_CACHE:-$HOME/Library/Application Support/macos-language-manager/atlassian-account-browser-profiles.txt}"
window_id=""

fail() {
  echo "$1" >&2
  exit 1
}

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
    "${ATLASSIAN_ACCOUNT_SAFARI_TABS_DB:-}" \
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

  if [ -n "${ATLASSIAN_ACCOUNT_BROWSER_PROFILES:-}" ]; then
    printf '%s\n' "$ATLASSIAN_ACCOUNT_BROWSER_PROFILES" | while IFS= read -r profile_name; do
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

  if [ -n "${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_MENU_DATA:-}" ]; then
    raw_menu_data="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_MENU_DATA}"
  elif [ -n "${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_MENU_ITEMS:-}" ]; then
    raw_menu_data="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_MENU_ITEMS}"
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

  ATLASSIAN_ACCOUNT_SAFARI_TARGET_URL="$url" ATLASSIAN_ACCOUNT_SAFARI_TARGET_PROFILE="$profile_name" run_applescript <<'APPLESCRIPT'
set targetUrl to system attribute "ATLASSIAN_ACCOUNT_SAFARI_TARGET_URL"
set targetProfile to system attribute "ATLASSIAN_ACCOUNT_SAFARI_TARGET_PROFILE"

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
  repeat 50 times
    set newWindows to every window whose id is not in existingIds
    if (count of newWindows) > 0 then
      set targetWindow to item 1 of newWindows
      tell targetWindow
        set URL of current tab to targetUrl
      end tell
      return id of targetWindow as text
    end if
    delay 0.2
  end repeat
end tell

error "Could not create a dedicated Safari window for browser profile " & targetProfile
APPLESCRIPT
}

safari_open_page() {
  local url="$1"

  safari_open_profile_page "$url" "$browser_profile"
}

safari_eval_js() {
  local script="$1"

  ATLASSIAN_ACCOUNT_SAFARI_JS="$script" ATLASSIAN_ACCOUNT_SAFARI_SESSION="$session_marker" ATLASSIAN_ACCOUNT_SAFARI_WINDOW_ID="${window_id:-}" run_applescript <<'APPLESCRIPT'
set jsSource to system attribute "ATLASSIAN_ACCOUNT_SAFARI_JS"
set sessionMarker to system attribute "ATLASSIAN_ACCOUNT_SAFARI_SESSION"
set rawWindowId to system attribute "ATLASSIAN_ACCOUNT_SAFARI_WINDOW_ID"

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

account_preferences_script() {
  cat <<'EOF'
(() => {
  const mode = __MODE__;
  const requested = __REQUESTED__;

  const normalize = (value) => value.replace(/\s+/g, " ").trim();
  const slug = (value) => normalize(value).toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  const textOf = (node) => normalize((node && (node.innerText || node.textContent)) || "");
  const isVisible = (node) => !!(node && node.getBoundingClientRect && node.getBoundingClientRect().width > 0 && node.getBoundingClientRect().height > 0);

  const pageRoot = document.body || document.documentElement;
  if (!pageRoot) {
    return JSON.stringify({ status: "waiting", message: "Document body is not ready yet." });
  }

  const pageText = textOf(pageRoot).toLowerCase();
  const loginHints = ["log in", "continue with", "enter your password", "verification code", "two-step verification"];
  if (loginHints.some((hint) => pageText.includes(hint))) {
    return JSON.stringify({ status: "waiting", message: "Waiting for Atlassian sign-in to finish in Safari." });
  }

  const findLabelText = (node) => {
    if (!node) {
      return "";
    }
    const parts = [];
    const id = node.getAttribute("id") || "";
    if (id) {
      for (const label of document.querySelectorAll(`label[for="${CSS.escape(id)}"]`)) {
        parts.push(textOf(label));
      }
    }
    const labelledBy = (node.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean);
    for (const labelId of labelledBy) {
      const labelNode = document.getElementById(labelId);
      if (labelNode) {
        parts.push(textOf(labelNode));
      }
    }
    const fieldGroup = node.closest("label, div, section, form");
    if (fieldGroup) {
      parts.push(textOf(fieldGroup).slice(0, 200));
    }
    return normalize(parts.join(" "));
  };

  const controlCandidates = [...document.querySelectorAll("select, input, button, [role='combobox'], [aria-haspopup='listbox']")]
    .filter((node) => isVisible(node))
    .map((node) => {
      const combinedText = [
        node.getAttribute("aria-label") || "",
        node.getAttribute("name") || "",
        node.getAttribute("placeholder") || "",
        findLabelText(node),
        textOf(node.parentElement || node)
      ].join(" ");
      return { node, score: slug(combinedText).includes("language") ? 1 : 0 };
    })
    .filter((item) => item.score > 0);

  const control = controlCandidates.length > 0 ? controlCandidates[0].node : null;
  if (!control) {
    return JSON.stringify({ status: "waiting", message: "Waiting for the Atlassian account language control to render." });
  }

  const readCurrentLanguage = () => {
    if (control.tagName === "SELECT") {
      const selected = control.selectedOptions && control.selectedOptions[0];
      return {
        value: selected ? selected.value : control.value || "",
        label: selected ? normalize(selected.textContent || "") : normalize(control.value || "")
      };
    }

    const fieldValue = normalize(control.value || "");
    const buttonText = normalize(textOf(control));
    return {
      value: fieldValue || buttonText,
      label: fieldValue || buttonText
    };
  };

  const current = readCurrentLanguage();
  if (!current.label) {
    return JSON.stringify({ status: "waiting", message: "Waiting for the current Atlassian account language value." });
  }

  if (mode === "read-json") {
    return JSON.stringify({ status: "ok", language: current });
  }

  const requestedLanguage = requested[0] || "";
  const requestedSlug = slug(requestedLanguage);
  const matchesCurrent = requestedSlug && (slug(current.label) === requestedSlug || slug(current.value) === requestedSlug);
  if (mode === "write" && matchesCurrent) {
    return JSON.stringify({ status: "ok", language: current });
  }

  const findVisibleOption = () => {
    const options = [...document.querySelectorAll("[role='option'], option, li, button, div")]
      .filter((node) => isVisible(node))
      .map((node) => ({
        node,
        label: textOf(node),
        value: node.getAttribute("data-value") || node.getAttribute("value") || node.dataset?.value || ""
      }))
      .filter((item) => item.label);

    return options.find((item) => {
      const labelSlug = slug(item.label);
      const valueSlug = slug(item.value);
      return labelSlug === requestedSlug || valueSlug === requestedSlug;
    }) || null;
  };

  const findSaveButton = () => {
    const candidates = [...document.querySelectorAll("button, [role='button']")].filter((node) => isVisible(node));
    return candidates.find((node) => {
      const buttonSlug = slug(textOf(node));
      const ariaSlug = slug(node.getAttribute("aria-label") || "");
      return buttonSlug === "save" || buttonSlug === "save changes" || ariaSlug === "save" || ariaSlug === "save changes";
    }) || null;
  };

  const clickNode = (node) => {
    if (!node) {
      return false;
    }
    node.click();
    return true;
  };

  const marker = window.__codexAtlassianLanguageTarget || "";
  if (marker !== requestedLanguage) {
    window.__codexAtlassianLanguageTarget = requestedLanguage;
    window.__codexAtlassianLanguagePhase = "";
  }

  const phase = window.__codexAtlassianLanguagePhase || "";

  if (control.tagName === "SELECT") {
    const matchingOption = [...control.options].find((option) => {
      const labelSlug = slug(option.textContent || "");
      const valueSlug = slug(option.value || "");
      return labelSlug === requestedSlug || valueSlug === requestedSlug;
    });
    if (!matchingOption) {
      return JSON.stringify({ status: "error", message: `Could not find Atlassian account language option ${requestedLanguage}.` });
    }
    control.value = matchingOption.value;
    control.dispatchEvent(new Event("input", { bubbles: true }));
    control.dispatchEvent(new Event("change", { bubbles: true }));
    const saveButton = findSaveButton();
    if (saveButton && !saveButton.disabled) {
      saveButton.click();
      window.__codexAtlassianLanguagePhase = "confirm";
      return JSON.stringify({ status: "waiting", message: "Saving the Atlassian account language." });
    }
    window.__codexAtlassianLanguagePhase = "confirm";
    return JSON.stringify({ status: "waiting", message: "Waiting for Atlassian to persist the selected language." });
  }

  if (phase === "") {
    clickNode(control);
    window.__codexAtlassianLanguagePhase = "choose";
    return JSON.stringify({ status: "waiting", message: "Opening the Atlassian language selector." });
  }

  if (phase === "choose") {
    const option = findVisibleOption();
    if (!option) {
      return JSON.stringify({ status: "waiting", message: `Waiting for the Atlassian language option ${requestedLanguage}.` });
    }
    option.node.click();
    window.__codexAtlassianLanguagePhase = "save";
    return JSON.stringify({ status: "waiting", message: "Selecting the Atlassian account language." });
  }

  if (phase === "save") {
    const saveButton = findSaveButton();
    if (saveButton && !saveButton.disabled) {
      saveButton.click();
      window.__codexAtlassianLanguagePhase = "confirm";
      return JSON.stringify({ status: "waiting", message: "Saving the Atlassian account language." });
    }
    window.__codexAtlassianLanguagePhase = "confirm";
    return JSON.stringify({ status: "waiting", message: "Waiting for Atlassian to persist the selected language." });
  }

  const saveButton = findSaveButton();
  if (saveButton && !saveButton.disabled) {
    saveButton.click();
    return JSON.stringify({ status: "waiting", message: "Saving the Atlassian account language." });
  }

  const refreshedCurrent = readCurrentLanguage();
  if (slug(refreshedCurrent.label) === requestedSlug || slug(refreshedCurrent.value) === requestedSlug) {
    return JSON.stringify({ status: "ok", language: refreshedCurrent });
  }

  return JSON.stringify({ status: "waiting", message: "Waiting for the Atlassian account language to refresh." });
})()
EOF
}

build_page_script() {
  local mode="$1"
  local requested_json="${2:-[]}"
  MODE="$mode" REQUESTED_JSON="$requested_json" python3 - <<'PY'
import json
import os

script = os.environ["SCRIPT_TEMPLATE"]
mode = json.dumps(os.environ["MODE"])
requested = os.environ["REQUESTED_JSON"]

script = script.replace("__MODE__", mode)
script = script.replace("__REQUESTED__", requested)
print(script)
PY
}

run_account_preferences_script() {
  local mode="$1"
  local requested_json="${2:-[]}"
  local template=""
  local script=""

  template="$(account_preferences_script)"
  SCRIPT_TEMPLATE="$template" build_page_script "$mode" "$requested_json" >/tmp/atlassian-account-language-script.$$
  script="$(cat /tmp/atlassian-account-language-script.$$)"
  rm -f /tmp/atlassian-account-language-script.$$
  safari_eval_js "$script"
}

wait_for_payload() {
  local mode="$1"
  local requested_json="${2:-[]}"
  local deadline=$((SECONDS + timeout_seconds))
  local payload=""
  local status=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    payload="$(run_account_preferences_script "$mode" "$requested_json")"
    if [ -z "$payload" ]; then
      sleep 2
      continue
    fi
    status="$(printf '%s' "$payload" | json_extract status 2>/dev/null || true)"
    if [ -z "$status" ]; then
      sleep 2
      continue
    fi
    case "$status" in
      ok)
        printf '%s\n' "$payload"
        return 0
        ;;
      error)
        printf '%s' "$payload" | json_extract message >&2 || true
        return 1
        ;;
    esac
    sleep 2
  done

  if [ -n "$payload" ]; then
    printf '%s' "$payload" | json_extract message >&2 || true
  fi
  fail "Timed out after ${timeout_seconds}s while waiting for the Atlassian account preferences page in Safari."
}

requested_json_from_args() {
  REQUESTED_LANGUAGES="$(printf '%s\n' "$@")" python3 - <<'PY'
import json
import os

print(json.dumps([line.strip() for line in os.environ["REQUESTED_LANGUAGES"].splitlines() if line.strip()]))
PY
}

command="${1:-}"
[ -n "$command" ] || fail "Missing helper command."
shift || true

case "$command" in
  list-profiles)
    list_browser_profiles
    exit 0
    ;;
  refresh-profiles)
    refresh_browser_profiles
    exit 0
    ;;
esac

ensure_valid_browser_profile "$browser_profile"

window_id="$(safari_open_page "$account_preferences_url")"
[ -n "$window_id" ] || fail "Could not create a dedicated Safari window."

case "$command" in
  read)
    wait_for_payload read-json | json_extract language.label
    ;;
  read-json)
    wait_for_payload read-json
    ;;
  write)
    [ "$#" -gt 0 ] || fail "The write helper requires a requested language label."
    wait_for_payload write "$(requested_json_from_args "$@")" >/dev/null
    ;;
  *)
    fail "Unknown helper command: $command"
    ;;
esac
