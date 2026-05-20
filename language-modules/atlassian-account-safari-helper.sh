#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
account_preferences_url="${ATLASSIAN_ACCOUNT_LANGUAGE_URL:-https://id.atlassian.com/manage-profile/account-preferences}"
timeout_seconds="${ATLASSIAN_ACCOUNT_LANGUAGE_TIMEOUT:-180}"
session_marker="${ATLASSIAN_ACCOUNT_SAFARI_SESSION:-codex-atlassian-language-$$-$(date +%s)}"
browser_profile="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE:-}"
profile_cache_path="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_CACHE:-${SAFARI_BROWSER_PROFILE_CACHE:-$HOME/Library/Application Support/macos-language-manager/safari-browser-profiles.txt}}"
safari_tabs_db_override="${ATLASSIAN_ACCOUNT_SAFARI_TABS_DB:-${SAFARI_BROWSER_PROFILE_TABS_DB:-}}"
browser_profiles_override="${ATLASSIAN_ACCOUNT_BROWSER_PROFILES:-}"
browser_profile_menu_data_override="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_MENU_DATA:-${SAFARI_BROWSER_PROFILE_MENU_DATA:-}}"
browser_profile_menu_items_override="${ATLASSIAN_ACCOUNT_BROWSER_PROFILE_MENU_ITEMS:-${SAFARI_BROWSER_PROFILE_MENU_ITEMS:-}}"
safari_target_url_env_var="ATLASSIAN_ACCOUNT_SAFARI_TARGET_URL"
safari_target_profile_env_var="ATLASSIAN_ACCOUNT_SAFARI_TARGET_PROFILE"
safari_js_env_var="ATLASSIAN_ACCOUNT_SAFARI_JS"
safari_session_env_var="ATLASSIAN_ACCOUNT_SAFARI_SESSION"
safari_window_id_env_var="ATLASSIAN_ACCOUNT_SAFARI_WINDOW_ID"
open_default_browser_profile_mode="profile-window"
window_id=""

fail() {
  echo "$1" >&2
  exit 1
}
# shellcheck disable=SC1091
source "$script_dir/safari-browser-profile-helper.sh"

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
