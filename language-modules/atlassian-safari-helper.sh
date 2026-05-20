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
  const requestedTag = __REQUESTED_TAG__;

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

  const readSingleValueText = (node) => {
    if (!node || !node.getAttribute) {
      return "";
    }
    const describedByIds = (node.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean);
    for (const describedById of describedByIds) {
      const describedByNode = document.getElementById(describedById);
      const describedByText = textOf(describedByNode);
      if (describedByText) {
        return describedByText;
      }
    }

    const fieldGroup = node.closest("label, div, section, form") || node.parentElement;
    if (!fieldGroup) {
      return "";
    }

    const singleValueNode = fieldGroup.querySelector("[id$='-single-value']");
    return textOf(singleValueNode);
  };

  const controlCandidates = [...document.querySelectorAll("select, input, button, [role='combobox'], [aria-haspopup='listbox']")]
    .filter((node) => isVisible(node))
    .map((node) => {
      const combinedText = [
        node.getAttribute("id") || "",
        node.getAttribute("aria-label") || "",
        node.getAttribute("name") || "",
        node.getAttribute("placeholder") || "",
        findLabelText(node),
        textOf(node.parentElement || node)
      ].join(" ");
      const combinedSlug = slug(combinedText);
      const score = combinedSlug.includes("language dropdown") || combinedSlug.includes("language")
        ? 2
        : combinedSlug.includes("timezone dropdown") || combinedSlug.includes("time zone")
          ? -1
          : 0;
      return { node, score };
    })
    .filter((item) => item.score > 0)
    .sort((left, right) => right.score - left.score);

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

    const isCombobox = (control.getAttribute("role") || "") === "combobox";
    const fieldValue = normalize(control.value || "");
    const buttonText = normalize(textOf(control));
    const singleValueText = normalize(readSingleValueText(control));
    const committedValue = singleValueText || buttonText;
    return {
      value: committedValue || (isCombobox ? "" : fieldValue),
      label: committedValue || (isCombobox ? "" : fieldValue)
    };
  };

  const current = readCurrentLanguage();
  if (mode === "read-json" && !current.label) {
    return JSON.stringify({ status: "waiting", message: "Waiting for the current Atlassian account language value." });
  }

  if (mode === "read-json") {
    return JSON.stringify({ status: "ok", language: current });
  }

  const requestedLanguage = requested[0] || "";
  const buildSearchCandidates = (label, tag) => {
    const values = [];
    const fallbackValues = [];
    const normalizedLabelSlug = slug(label || "");
    const fromCodePoints = (...points) => String.fromCodePoint(...points);
    const pushUnique = (target, value) => {
      const normalized = normalize(value || "");
      if (!normalized) {
        return;
      }
      const normalizedSlug = slug(normalized);
      if (
        !values.some((existing) => slug(existing) === normalizedSlug) &&
        !fallbackValues.some((existing) => slug(existing) === normalizedSlug)
      ) {
        target.push(normalized);
      }
    };
    const push = (value) => pushUnique(values, value);
    const pushFallback = (value) => pushUnique(fallbackValues, value);

    const nativeLabelCases = {
      "japanese": [fromCodePoints(0x65e5, 0x672c, 0x8a9e), fromCodePoints(0x65e5)],
      "korean": [fromCodePoints(0xd55c, 0xad6d, 0xc5b4)],
      "chinese simplified": [fromCodePoints(0x7b80, 0x4f53, 0x4e2d, 0x6587)],
      "chinese traditional": [fromCodePoints(0x7e41, 0x9ad4, 0x4e2d, 0x6587)],
      "czech": ["\u010ce\u0161tina", "Cestina", "\u010de\u0161tina"]
    };
    for (const variant of nativeLabelCases[normalizedLabelSlug] || []) {
      push(variant);
    }

    if (tag && typeof Intl !== "undefined" && Intl.DisplayNames) {
      const canonicalTag = Intl.getCanonicalLocales([tag])[0] || tag;
      const baseLanguage = canonicalTag.split("-")[0];
      const localeCandidates = [
        document.documentElement.lang || "",
        navigator.language || "",
        "en"
      ].filter(Boolean);

      for (const locale of localeCandidates) {
        try {
          const displayNames = new Intl.DisplayNames([locale], { type: "language" });
          push(displayNames.of(canonicalTag));
          push(displayNames.of(baseLanguage));
        } catch (_) {
        }
      }

      const specialCases = {
        ja: [fromCodePoints(0x65e5, 0x672c, 0x8a9e), fromCodePoints(0x65e5)],
        ko: [fromCodePoints(0xd55c, 0xad6d, 0xc5b4)],
        zh: [fromCodePoints(0x4e2d, 0x6587)],
        "zh-cn": [fromCodePoints(0x7b80, 0x4f53, 0x4e2d, 0x6587)],
        "zh-tw": [fromCodePoints(0x7e41, 0x9ad4, 0x4e2d, 0x6587)]
      };
      for (const variant of specialCases[canonicalTag.toLowerCase()] || []) {
        push(variant);
      }
      for (const variant of specialCases[baseLanguage.toLowerCase()] || []) {
        push(variant);
      }
    }

    pushFallback(label);
    pushFallback(label.replace(/\s*\([^)]*\)\s*$/u, ""));

    return [...values, ...fallbackValues];
  };

  const searchCandidates = buildSearchCandidates(requestedLanguage, requestedTag);
  const matchesRequestedLanguage = (language) => {
    if (searchCandidates.length === 0) {
      return false;
    }
    const currentSlugs = [slug(language.label || ""), slug(language.value || "")].filter(Boolean);
    return searchCandidates.some((candidate) => {
      const candidateSlug = slug(candidate);
      return currentSlugs.includes(candidateSlug);
    });
  };

  const matchesCurrent = matchesRequestedLanguage(current);
  if (mode === "write" && matchesCurrent) {
    return JSON.stringify({ status: "ok", changed: false, language: current });
  }

  const currentSearchCandidate = () => {
    const index = window.__codexAtlassianLanguageSearchIndex || 0;
    return searchCandidates[index] || searchCandidates[0] || requestedLanguage;
  };

  const advanceSearchCandidate = () => {
    const index = window.__codexAtlassianLanguageSearchIndex || 0;
    if (index + 1 >= searchCandidates.length) {
      return false;
    }
    window.__codexAtlassianLanguageSearchIndex = index + 1;
    return true;
  };

  const findVisibleOption = () => {
    const options = [...document.querySelectorAll("[role='option'], option")]
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
      return searchCandidates.some((candidate) => {
        const candidateSlug = slug(candidate);
        return labelSlug === candidateSlug || valueSlug === candidateSlug;
      });
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
    if (node.focus) {
      node.focus();
    }
    node.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true, view: window }));
    node.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, cancelable: true, view: window }));
    node.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
    return true;
  };

  const setComboboxValue = (node, value) => {
    if (!node || typeof value !== "string") {
      return;
    }
    if (node.focus) {
      node.focus();
    }
    if (node instanceof HTMLInputElement || node instanceof HTMLTextAreaElement) {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
      if (setter) {
        setter.call(node, value);
      } else {
        node.value = value;
      }
    } else {
      node.value = value;
    }
    node.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, key: value.slice(-1) || " ", code: "KeyA" }));
    node.dispatchEvent(new Event("input", { bubbles: true }));
    node.dispatchEvent(new Event("change", { bubbles: true }));
    node.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true, key: value.slice(-1) || " ", code: "KeyA" }));
  };

  const visibleOptionsContainNoResults = () => {
    const optionContainerText = textOf(document.querySelector("[role='listbox']") || document.body).toLowerCase();
    return optionContainerText.includes("no options") || optionContainerText.includes("no results");
  };

  const marker = window.__codexAtlassianLanguageTarget || "";
  if (marker !== requestedLanguage) {
    window.__codexAtlassianLanguageTarget = requestedLanguage;
    window.__codexAtlassianLanguagePhase = "";
    window.__codexAtlassianLanguageSearchIndex = 0;
    window.__codexAtlassianLanguageDidChange = false;
  }

  const phase = window.__codexAtlassianLanguagePhase || "";
  if (phase === "" && !current.label) {
    return JSON.stringify({ status: "waiting", message: "Waiting for the current Atlassian account language value." });
  }

  if (control.tagName === "SELECT") {
    const matchingOption = [...control.options].find((option) => {
      const labelSlug = slug(option.textContent || "");
      const valueSlug = slug(option.value || "");
      return searchCandidates.some((candidate) => {
        const candidateSlug = slug(candidate);
        return labelSlug === candidateSlug || valueSlug === candidateSlug;
      });
    });
    if (!matchingOption) {
      return JSON.stringify({ status: "error", message: `Could not find Atlassian account language option ${requestedLanguage}.` });
    }
    control.value = matchingOption.value;
    control.dispatchEvent(new Event("input", { bubbles: true }));
    control.dispatchEvent(new Event("change", { bubbles: true }));
    window.__codexAtlassianLanguageDidChange = true;
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
    setComboboxValue(control, currentSearchCandidate());
    window.__codexAtlassianLanguagePhase = "choose";
    return JSON.stringify({ status: "waiting", message: "Opening the Atlassian language selector." });
  }

  if (phase === "choose") {
    const option = findVisibleOption();
    if (!option) {
      if (visibleOptionsContainNoResults() && advanceSearchCandidate()) {
        setComboboxValue(control, currentSearchCandidate());
        return JSON.stringify({ status: "waiting", message: `Retrying the Atlassian language search for ${requestedLanguage}.` });
      }
      setComboboxValue(control, currentSearchCandidate());
      return JSON.stringify({ status: "waiting", message: `Waiting for the Atlassian language option ${requestedLanguage}.` });
    }
    clickNode(option.node);
    window.__codexAtlassianLanguageDidChange = true;
    window.__codexAtlassianLanguagePhase = "confirm";
    return JSON.stringify({ status: "waiting", message: "Selecting the Atlassian account language." });
  }

  const saveButton = findSaveButton();
  if (saveButton && !saveButton.disabled) {
    saveButton.click();
    return JSON.stringify({ status: "waiting", message: "Saving the Atlassian account language." });
  }

  const refreshedCurrent = readCurrentLanguage();
  if (matchesRequestedLanguage(refreshedCurrent)) {
    return JSON.stringify({
      status: "ok",
      changed: !!window.__codexAtlassianLanguageDidChange,
      language: refreshedCurrent
    });
  }

  return JSON.stringify({ status: "waiting", message: "Waiting for the Atlassian account language to refresh." });
})()
EOF
}

build_page_script() {
  local mode="$1"
  local requested_json="${2:-[]}"
  local requested_tag="${3:-}"
  MODE="$mode" REQUESTED_JSON="$requested_json" REQUESTED_TAG="$requested_tag" python3 - <<'PY'
import json
import os

script = os.environ["SCRIPT_TEMPLATE"]
mode = json.dumps(os.environ["MODE"])
requested = os.environ["REQUESTED_JSON"]
requested_tag = json.dumps(os.environ["REQUESTED_TAG"])

script = script.replace("__MODE__", mode)
script = script.replace("__REQUESTED__", requested)
script = script.replace("__REQUESTED_TAG__", requested_tag)
print(script)
PY
}

run_account_preferences_script() {
  local mode="$1"
  local requested_json="${2:-[]}"
  local requested_tag="${3:-}"
  local template=""
  local script=""

  template="$(account_preferences_script)"
  SCRIPT_TEMPLATE="$template" build_page_script "$mode" "$requested_json" "$requested_tag" >/tmp/atlassian-language-script.$$
  script="$(cat /tmp/atlassian-language-script.$$)"
  rm -f /tmp/atlassian-language-script.$$
  safari_eval_js "$script"
}

wait_for_payload() {
  local mode="$1"
  local requested_json="${2:-[]}"
  local requested_tag="${3:-}"
  local deadline=$((SECONDS + timeout_seconds))
  local payload=""
  local status=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    payload="$(run_account_preferences_script "$mode" "$requested_json" "$requested_tag")"
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
    wait_for_payload write "$(requested_json_from_args "$@")" "${ATLASSIAN_ACCOUNT_REQUESTED_LANGUAGE_TAG:-}"
    ;;
  *)
    fail "Unknown helper command: $command"
    ;;
esac
