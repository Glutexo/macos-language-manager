#!/bin/bash
set -euo pipefail

preferred_languages_url="${GOOGLE_ACCOUNT_LANGUAGE_URL:-https://myaccount.google.com/language?hl=en}"
timeout_seconds="${GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT:-180}"
session_marker="${GOOGLE_ACCOUNT_SAFARI_SESSION:-codex-google-language-$$-$(date +%s)}"
window_id=""

fail() {
  echo "$1" >&2
  exit 1
}

run_applescript() {
  osascript - "$@"
}

safari_open_page() {
  local url="$1"
  local separator='?'

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
    return id of front window
  end tell
end run
APPLESCRIPT
}

safari_eval_js() {
  local script="$1"

  GOOGLE_ACCOUNT_SAFARI_JS="$script" GOOGLE_ACCOUNT_SAFARI_SESSION="$session_marker" GOOGLE_ACCOUNT_SAFARI_WINDOW_ID="$window_id" run_applescript <<'APPLESCRIPT'
set jsSource to system attribute "GOOGLE_ACCOUNT_SAFARI_JS"
set sessionMarker to system attribute "GOOGLE_ACCOUNT_SAFARI_SESSION"
set rawWindowId to system attribute "GOOGLE_ACCOUNT_SAFARI_WINDOW_ID"
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

language_page_script() {
  cat <<'EOF'
(() => {
  const mode = __MODE__;
  const requested = __REQUESTED__;

  const normalize = (value) => value.replace(/\s+/g, " ").trim();
  const slug = (value) => normalize(value).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
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
        const region = textOf(regionNode);
        const display = region ? `${label} (${region})` : label;
        return {
          id: node.getAttribute("data-id") || "",
          label,
          region,
          display,
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
    for (const node of root.querySelectorAll("button, [role='button'], a, div")) {
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
      languages: currentRows.map((item) => ({
        id: item.id,
        label: item.label,
        region: item.region,
        display: item.display
      }))
    });
  }

  const expected = requested.map((item) => slug(item));
  const actual = currentRows.map((item) => item.slug);
  const missing = expected.filter((item) => !actual.includes(item));

  const findSearchInput = (root) => {
    return [...root.querySelectorAll("input, textarea")]
      .find((node) => isVisible(node) && (node.type === "search" || node.type === "text" || node.getAttribute("role") === "combobox"));
  };

  const setInputValue = (node, value) => {
    const prototype = Object.getPrototypeOf(node);
    const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
    if (descriptor && descriptor.set) {
      descriptor.set.call(node, value);
    } else {
      node.value = value;
    }
    node.dispatchEvent(new Event("input", { bubbles: true }));
    node.dispatchEvent(new Event("change", { bubbles: true }));
  };

  const findMatchingOption = (root, wantedSlug) => {
    for (const node of root.querySelectorAll('[role="option"], [role="listitem"], li, button, div, span')) {
      if (!isVisible(node)) {
        continue;
      }
      const optionSlug = slug(textOf(node));
      if (!optionSlug) {
        continue;
      }
      if (optionSlug === wantedSlug || optionSlug.includes(wantedSlug) || wantedSlug.includes(optionSlug)) {
        return node;
      }
    }
    return null;
  };

  const addDialog = [...document.querySelectorAll("[role='dialog'], dialog, c-wiz")]
    .find((node) => isVisible(node) && (/language/i.test(textOf(node)) || !!findSearchInput(node)));

  if (missing.length > 0) {
    const nextMissing = missing[0];
    if (!addDialog) {
      const addButton = findClickable(["add another language", "add language", "add"], cardRoot || pageRoot) || findClickable(["add another language", "add language", "add"]);
      if (!addButton) {
        return JSON.stringify({ status: "error", message: `Could not locate the add-language button while trying to add ${nextMissing}.` });
      }
      addButton.click();
      return JSON.stringify({ status: "waiting", message: `Opening the add-language dialog for ${nextMissing}.` });
    }

    const searchInput = findSearchInput(addDialog);
    if (!searchInput) {
      return JSON.stringify({ status: "error", message: `Could not locate the language search field while trying to add ${nextMissing}.` });
    }

    if (slug(searchInput.value || "") !== nextMissing) {
      setInputValue(searchInput, requested[expected.indexOf(nextMissing)]);
      return JSON.stringify({ status: "waiting", message: `Searching for ${nextMissing}.` });
    }

    const optionNode = findMatchingOption(addDialog, nextMissing);
    if (!optionNode) {
      return JSON.stringify({ status: "waiting", message: `Waiting for a search result for ${nextMissing}.` });
    }

    optionNode.click();

    const confirmButton = findClickable(["done", "save", "add"], addDialog);
    if (confirmButton) {
      confirmButton.click();
    }

    return JSON.stringify({ status: "waiting", message: `Adding ${nextMissing}.` });
  }

  const extras = currentRows.filter((item) => !expected.includes(item.slug));
  if (extras.length > 0) {
    const removable = extras.find((item) => item.removeButton);
    if (!removable) {
      return JSON.stringify({ status: "error", message: `Could not locate a remove button for ${extras[0].display}.` });
    }
    removable.removeButton.click();
    return JSON.stringify({ status: "waiting", message: `Removing ${removable.display}.` });
  }

  const actualOrder = currentRows.map((item) => item.slug);
  const firstMismatch = expected.findIndex((item, index) => actualOrder[index] !== item);
  if (firstMismatch >= 0) {
    const wantedSlug = expected[firstMismatch];
    const targetRow = currentRows.find((item) => item.slug === wantedSlug);
    if (!targetRow) {
      return JSON.stringify({ status: "error", message: `Could not locate the requested language row for ${wantedSlug}.` });
    }
    if (!targetRow.moveButton) {
      return JSON.stringify({ status: "error", message: `Could not locate a move-up button for ${targetRow.display}.` });
    }
    targetRow.moveButton.click();
    return JSON.stringify({ status: "waiting", message: `Moving ${targetRow.display} upward.` });
  }

  return JSON.stringify({ status: "ok", languages: requested });
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
    status="$(printf '%s' "$payload" | json_extract status)"
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

window_id="$(safari_open_page "$preferred_languages_url")"
[ -n "$window_id" ] || fail "Could not create a dedicated Safari window."

case "$command" in
  read)
    wait_for_payload read | json_extract languages
    ;;
  read-json)
    wait_for_payload read-json
    ;;
  write)
    [ "$#" -gt 0 ] || fail "The write helper requires at least one requested language label."
    wait_for_payload write "$(requested_json_from_args "$@")" >/dev/null
    ;;
  *)
    fail "Unknown helper command: $command"
    ;;
esac
