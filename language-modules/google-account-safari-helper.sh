#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
preferred_languages_url="${GOOGLE_ACCOUNT_LANGUAGE_URL:-https://myaccount.google.com/language?hl=en}"
timeout_seconds="${GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT:-180}"
session_marker="${GOOGLE_ACCOUNT_SAFARI_SESSION:-codex-google-language-$$-$(date +%s)}"
browser_profile="${GOOGLE_ACCOUNT_BROWSER_PROFILE:-}"
profile_cache_path="${GOOGLE_ACCOUNT_BROWSER_PROFILE_CACHE:-${SAFARI_BROWSER_PROFILE_CACHE:-$HOME/Library/Application Support/macos-language-manager/safari-browser-profiles.txt}}"
safari_tabs_db_override="${GOOGLE_ACCOUNT_SAFARI_TABS_DB:-${SAFARI_BROWSER_PROFILE_TABS_DB:-}}"
browser_profiles_override="${GOOGLE_ACCOUNT_BROWSER_PROFILES:-}"
browser_profile_menu_data_override="${GOOGLE_ACCOUNT_BROWSER_PROFILE_MENU_DATA:-${SAFARI_BROWSER_PROFILE_MENU_DATA:-}}"
browser_profile_menu_items_override="${GOOGLE_ACCOUNT_BROWSER_PROFILE_MENU_ITEMS:-${SAFARI_BROWSER_PROFILE_MENU_ITEMS:-}}"
safari_target_url_env_var="GOOGLE_ACCOUNT_SAFARI_TARGET_URL"
safari_target_profile_env_var="GOOGLE_ACCOUNT_SAFARI_TARGET_PROFILE"
safari_js_env_var="GOOGLE_ACCOUNT_SAFARI_JS"
safari_session_env_var="GOOGLE_ACCOUNT_SAFARI_SESSION"
safari_window_id_env_var="GOOGLE_ACCOUNT_SAFARI_WINDOW_ID"
open_default_browser_profile_mode="new-document"
window_id=""

fail() {
  echo "$1" >&2
  exit 1
}
# shellcheck disable=SC1091
source "$script_dir/safari-browser-profile-helper.sh"

language_page_script() {
  cat <<'EOF'
(() => {
  const mode = __MODE__;
  const requested = __REQUESTED__;

  const normalize = (value) => value.replace(/\s+/g, " ").trim();
  const slug = (value) => normalize(value).toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  const textOf = (node) => normalize((node && (node.innerText || node.textContent)) || "");
  const isVisible = (node) => !!(node && node.getBoundingClientRect && node.getBoundingClientRect().width > 0 && node.getBoundingClientRect().height > 0);

  const loginHints = ["sign in", "choose an account", "verify it’s you", "2-step verification"];
  const pageRoot = document.body || document.documentElement;
  if (!pageRoot) {
    return JSON.stringify({ status: "waiting", message: "Document body is not ready yet." });
  }

  const pageText = textOf(pageRoot).toLowerCase();
  if (loginHints.some((hint) => pageText.includes(hint))) {
    return JSON.stringify({ status: "waiting", message: "Waiting for Google sign-in to finish in Safari." });
  }

  const cardRoot = [...pageRoot.querySelectorAll("div, section, c-wiz")]
    .find((node) => isVisible(node) && /preferred language/i.test(textOf(node)) && /other languages/i.test(textOf(node)));

  const collectLanguageRows = () => {
    const root = cardRoot || pageRoot;
    return [...root.querySelectorAll('li[data-id][jsname="sgblj"]')]
      .filter((node) => isVisible(node))
      .map((node) => {
        const labelNode = node.querySelector("label");
        const regionNode = node.querySelector(".xsr7od");
        const label = textOf(labelNode);
        const saveButton = [...node.querySelectorAll("button")].find((button) => /Save language/i.test(button.getAttribute("aria-label") || ""));
        const addedForYou = !!saveButton || /Added for you/i.test(textOf(node));
        const region = addedForYou ? "Added for you" : textOf(regionNode);
        const display = region ? `${label} (${region})` : label;
        return {
          id: node.getAttribute("data-id") || "",
          label,
          region,
          display,
          addedForYou,
          slug: slug(display),
          labelSlug: slug(label),
          node,
          moveButton: [...node.querySelectorAll("button")].find((button) => /Move language up|Make this my preferred language/i.test(button.getAttribute("aria-label") || "")),
          removeButton: [...node.querySelectorAll("button")].find((button) => /Remove language/i.test(button.getAttribute("aria-label") || "")),
          editButton: [...node.querySelectorAll("button")].find((button) => /Edit language/i.test(button.getAttribute("aria-label") || ""))
        };
      })
      .filter((item) => item.label);
  };

  const findClickable = (labels, root = pageRoot) => {
    const wanted = labels.map((label) => slug(label));
    for (const node of root.querySelectorAll("button, [role='button'], a")) {
      if (!isVisible(node)) {
        continue;
      }
      const text = slug(textOf(node));
      const aria = slug(node.getAttribute("aria-label") || "");
      if (wanted.includes(text) || wanted.includes(aria)) {
        return node;
      }
    }
    return null;
  };

  const autoAddToggle = [...pageRoot.querySelectorAll("button[role='switch']")]
    .find((node) => /Automatically add languages/i.test(node.getAttribute("aria-label") || ""));
  const autoAddEnabled = !!(autoAddToggle && autoAddToggle.getAttribute("aria-checked") === "true");
  const stopAddingButton = findClickable(["stop adding"], pageRoot);

  const currentRows = collectLanguageRows();
  if (currentRows.length < 1) {
    return JSON.stringify({ status: "waiting", message: "Waiting for the preferred-language list to render." });
  }

  if (mode === "read") {
    return JSON.stringify({ status: "ok", languages: currentRows.map((item) => item.display) });
  }

  if (mode === "read-json") {
    return JSON.stringify({
      status: "ok",
      auto_add_enabled: autoAddEnabled,
      languages: currentRows.map((item) => ({
        id: item.id,
        label: item.label,
        region: item.region,
        display: item.display,
        added_for_you: item.addedForYou
      }))
    });
  }

  if (mode === "resolve-labels") {
    const buildLanguageCatalog = () => {
      const html = document.documentElement?.outerHTML || "";
      const entryPattern = /\[\["ac\.c\.lang\.l","([^"]+)","([^"]+)","([^"]+)","([^"]*)","([^"]*)"\],0,\d+(?:,null,\[.*?\],\["([^"]+)","([^"]+)"\])?/gs;
      const catalog = [];
      let match;

      while ((match = entryPattern.exec(html)) !== null) {
        catalog.push({
          englishName: match[1],
          languageId: match[2],
          nativeName: match[3],
          englishSearch: match[4],
          nativeSearch: match[5],
          defaultId: match[6] || match[2],
          defaultRegion: match[7] || ""
        });
      }

      return catalog.map((item) => ({
        ...item,
        englishSlug: slug(item.englishName),
        nativeSlug: slug(item.nativeName),
        englishSearchSlug: slug(item.englishSearch),
        nativeSearchSlug: slug(item.nativeSearch),
        displaySlug: slug(item.defaultRegion ? `${item.nativeName} (${item.defaultRegion})` : item.nativeName)
      }));
    };

    const catalog = buildLanguageCatalog();
    const resolved = requested.map((requestedLabel) => {
      const requestedSlug = slug(requestedLabel);
      const currentMatch = currentRows.find((item) =>
        item.slug === requestedSlug ||
        item.labelSlug === requestedSlug ||
        item.slug.includes(requestedSlug) ||
        requestedSlug.includes(item.slug)
      );
      if (currentMatch) {
        return currentMatch.display;
      }

      const catalogMatch = catalog.find((item) =>
        [
          item.englishSlug,
          item.nativeSlug,
          item.englishSearchSlug,
          item.nativeSearchSlug,
          item.displaySlug
        ].some((candidate) =>
          candidate && (
            candidate === requestedSlug ||
            candidate.includes(requestedSlug) ||
            requestedSlug.includes(candidate)
          )
        )
      );

      if (catalogMatch) {
        return catalogMatch.defaultRegion ? `${catalogMatch.nativeName} (${catalogMatch.defaultRegion})` : catalogMatch.nativeName;
      }

      return requestedLabel;
    });

    return JSON.stringify({ status: "ok", labels: resolved });
  }

  if (mode === "write-ids") {
    const actualIds = currentRows.map((item) => item.id);
    if (JSON.stringify(actualIds) === JSON.stringify(requested)) {
      return JSON.stringify({ status: "ok", languages: currentRows.map((item) => item.display) });
    }

    if (window.__codexLanguageUpdateSubmitted !== JSON.stringify(requested)) {
      const submission = submitLanguageUpdate(requested);
      if (!submission.ok) {
        return JSON.stringify({ status: "error", message: submission.message });
      }
      window.__codexLanguageUpdateSubmitted = JSON.stringify(requested);
      window.location.reload();
      return JSON.stringify({ status: "waiting", message: "Submitting the Google preferred-language update." });
    }

    return JSON.stringify({ status: "waiting", message: "Waiting for the Google preferred-language page to refresh." });
  }

  if (mode === "write-ids-immediate") {
    const submission = submitLanguageUpdate(requested);
    if (!submission.ok) {
      return JSON.stringify({ status: "error", message: submission.message });
    }
    return JSON.stringify({ status: "ok" });
  }

  if (mode === "disable-auto-add") {
    if (stopAddingButton) {
      stopAddingButton.click();
      return JSON.stringify({ status: "waiting", message: "Stopping Google's automatic language additions." });
    }
    if (!autoAddEnabled) {
      return JSON.stringify({ status: "ok", auto_add_enabled: false });
    }
    if (!autoAddToggle) {
      return JSON.stringify({ status: "error", message: "Could not locate Google's automatic language additions switch." });
    }
    autoAddToggle.click();
    return JSON.stringify({ status: "waiting", message: "Opening Google's stop-adding confirmation." });
  }

  if (mode === "enable-auto-add") {
    if (autoAddEnabled) {
      return JSON.stringify({ status: "ok", auto_add_enabled: true });
    }
    if (!autoAddToggle) {
      return JSON.stringify({ status: "error", message: "Could not locate Google's automatic language additions switch." });
    }
    autoAddToggle.click();
    return JSON.stringify({ status: "waiting", message: "Starting Google's automatic language additions." });
  }

  const buildLanguageCatalog = () => {
    const html = document.documentElement?.outerHTML || "";
    const entryPattern = /\[\["ac\.c\.lang\.l","([^"]+)","([^"]+)","([^"]+)","([^"]*)","([^"]*)"\],0,\d+(?:,null,\[.*?\],\["([^"]+)","([^"]+)"\])?/gs;
    const catalog = [];
    let match;

    while ((match = entryPattern.exec(html)) !== null) {
      catalog.push({
        englishName: match[1],
        languageId: match[2],
        nativeName: match[3],
        englishSearch: match[4],
        nativeSearch: match[5],
        defaultId: match[6] || match[2],
        defaultRegion: match[7] || ""
      });
    }

    return catalog.map((item) => ({
      ...item,
      englishSlug: slug(item.englishName),
      nativeSlug: slug(item.nativeName),
      englishSearchSlug: slug(item.englishSearch),
      nativeSearchSlug: slug(item.nativeSearch),
      displaySlug: slug(item.defaultRegion ? `${item.nativeName} (${item.defaultRegion})` : item.nativeName)
    }));
  };

  const resolveRequestedLanguageId = (requestedLabel, catalog) => {
    const requestedSlug = slug(requestedLabel);
    if (!requestedSlug) {
      return null;
    }
    const requestedHasRegion = /\([^)]+\)\s*$/.test(requestedLabel);

    const currentMatch = currentRows.find((item) =>
      item.slug === requestedSlug ||
      item.labelSlug === requestedSlug ||
      item.slug.includes(requestedSlug) ||
      requestedSlug.includes(item.slug)
    );
    if (currentMatch) {
      return currentMatch.id;
    }

    const catalogMatch = catalog.find((item) =>
      [
        item.englishSlug,
        item.nativeSlug,
        item.englishSearchSlug,
        item.nativeSearchSlug,
        item.displaySlug
      ].some((candidate) =>
        candidate && (
          candidate === requestedSlug ||
          candidate.includes(requestedSlug) ||
          requestedSlug.includes(candidate)
        )
      )
    );

    if (catalogMatch) {
      return requestedHasRegion ? catalogMatch.defaultId : (catalogMatch.languageId || catalogMatch.defaultId);
    }

    const escapeRegex = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const fallbackPattern = new RegExp(
      `\\[\\["ac\\.c\\.lang\\.l","${escapeRegex(requestedLabel)}","([^"]+)","([^"]+)","[^"]*","[^"]*"\\],\\d,\\d(?:,null,\\[.*?\\],\\["([^"]+)","([^"]+)"\\])?`,
      "s"
    );
    const html = document.documentElement?.outerHTML || "";
    const fallbackMatch = html.match(fallbackPattern);
    if (!fallbackMatch) {
      return null;
    }

    return requestedHasRegion ? (fallbackMatch[3] || fallbackMatch[1]) : fallbackMatch[1];
  };

  const submitLanguageUpdate = (languageIds) => {
    const wizData = window.WIZ_global_data || {};
    if (!wizData.FdrFJe || !wizData.SNlM0e || !wizData.cfb2h) {
      return { ok: false, message: "Could not derive the Google language-update request parameters from the page." };
    }

    const params = new URLSearchParams({
      "f.sid": String(wizData.FdrFJe),
      bl: String(wizData.cfb2h),
      hl: "en",
      "soc-app": "1",
      "soc-platform": "1",
      "soc-device": "1",
      _reqid: String(Date.now() % 1000000),
      rt: "j"
    });

    const xhr = new XMLHttpRequest();
    xhr.open("POST", `/_/language_update?${params.toString()}`, false);
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8");
    xhr.send(`f.req=${encodeURIComponent(JSON.stringify([languageIds]))}&at=${encodeURIComponent(String(wizData.SNlM0e))}&`);

    if (xhr.status < 200 || xhr.status >= 300) {
      return { ok: false, message: `The Google language-update request failed with HTTP ${xhr.status}.` };
    }

    return { ok: true };
  };

  const catalog = buildLanguageCatalog();
  const expectedIds = requested.map((item) => resolveRequestedLanguageId(item, catalog));
  if (expectedIds.some((item) => !item)) {
    const missingIndex = expectedIds.findIndex((item) => !item);
    return JSON.stringify({ status: "error", message: `Could not resolve a Google Account language id for ${requested[missingIndex]}.` });
  }

  const actualIds = currentRows.map((item) => item.id);
  if (JSON.stringify(actualIds) === JSON.stringify(expectedIds)) {
    return JSON.stringify({ status: "ok", languages: requested });
  }

  if (window.__codexLanguageUpdateSubmitted !== JSON.stringify(expectedIds)) {
    const submission = submitLanguageUpdate(expectedIds);
    if (!submission.ok) {
      return JSON.stringify({ status: "error", message: submission.message });
    }
    window.__codexLanguageUpdateSubmitted = JSON.stringify(expectedIds);
    window.location.reload();
    return JSON.stringify({ status: "waiting", message: "Submitting the Google preferred-language update." });
  }

  return JSON.stringify({ status: "waiting", message: "Waiting for the Google preferred-language page to refresh." });
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

run_language_script() {
  local mode="$1"
  local requested_json="${2:-[]}"
  local template=""
  local script=""

  template="$(language_page_script)"
  SCRIPT_TEMPLATE="$template" build_page_script "$mode" "$requested_json" >/tmp/google-account-language-script.$$ 
  script="$(cat /tmp/google-account-language-script.$$)"
  rm -f /tmp/google-account-language-script.$$
  safari_eval_js "$script"
}

wait_for_payload() {
  local mode="$1"
  local requested_json="${2:-[]}"
  local deadline=$((SECONDS + timeout_seconds))
  local payload=""
  local status=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    payload="$(run_language_script "$mode" "$requested_json")"
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
  fail "Timed out after ${timeout_seconds}s while waiting for the Google Account language page in Safari."
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

window_id="$(safari_open_page "$preferred_languages_url")"
[ -n "$window_id" ] || fail "Could not create a dedicated Safari window."

case "$command" in
  read)
    wait_for_payload read | json_extract languages
    ;;
  read-json)
    wait_for_payload read-json
    ;;
  resolve-labels)
    wait_for_payload resolve-labels "$(requested_json_from_args "$@")" | json_extract labels
    ;;
  write-ids)
    [ "$#" -gt 0 ] || fail "The write-ids helper requires at least one requested language id."
    wait_for_payload write-ids "$(requested_json_from_args "$@")" >/dev/null
    ;;
  write-ids-immediate)
    [ "$#" -gt 0 ] || fail "The write-ids-immediate helper requires at least one requested language id."
    wait_for_payload write-ids-immediate "$(requested_json_from_args "$@")" >/dev/null
    ;;
  disable-auto-add)
    wait_for_payload disable-auto-add >/dev/null
    ;;
  enable-auto-add)
    wait_for_payload enable-auto-add >/dev/null
    ;;
  write)
    [ "$#" -gt 0 ] || fail "The write helper requires at least one requested language label."
    wait_for_payload write "$(requested_json_from_args "$@")" >/dev/null
    ;;
  *)
    fail "Unknown helper command: $command"
    ;;
esac
