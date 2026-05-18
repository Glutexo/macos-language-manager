#!/bin/bash
set -euo pipefail

preferred_languages_url="${GOOGLE_ACCOUNT_LANGUAGE_URL:-https://myaccount.google.com/language?hl=en}"
timeout_seconds="${GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT:-180}"

fail() {
  echo "$1" >&2
  exit 1
}

run_applescript() {
  osascript - "$@"
}

safari_open_page() {
  local url="$1"

  run_applescript "$url" <<'APPLESCRIPT' >/dev/null
on run argv
  set targetUrl to item 1 of argv
  tell application "Safari"
    activate
    if (count of documents) = 0 then
      make new document
    end if
    set URL of front document to targetUrl
  end tell
end run
APPLESCRIPT
}

safari_eval_js() {
  local script="$1"

  GOOGLE_ACCOUNT_SAFARI_JS="$script" run_applescript <<'APPLESCRIPT'
set jsSource to system attribute "GOOGLE_ACCOUNT_SAFARI_JS"
tell application "Safari"
  if (count of documents) = 0 then
    error "Safari has no open document."
  end if
  return do JavaScript jsSource in front document
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

  const sectionRoot = (() => {
    const heading = [...pageRoot.querySelectorAll("h1, h2, h3, div, span")]
      .find((node) => isVisible(node) && /preferred language/i.test(textOf(node)));
    return heading ? (heading.closest("section, [role='region'], c-wiz, div") || pageRoot) : pageRoot;
  })();

  const collectLanguages = (root) => {
    const results = [];
    const seen = new Set();

    for (const node of root.querySelectorAll("[draggable='true'], [role='listitem'], li, button, div, span")) {
      if (!isVisible(node)) {
        continue;
      }

      const text = textOf(node);
      if (!text || text.length < 2 || text.length > 80) {
        continue;
      }

      if (!/[A-Za-z]/.test(text)) {
        continue;
      }

      if (/^(preferred language|google account|edit|save|cancel|done|remove|add another language)$/i.test(text)) {
        continue;
      }

      if (text.split(/\s+/).length > 4) {
        continue;
      }

      if (!seen.has(text)) {
        seen.add(text);
        results.push({ text, slug: slug(text), node });
      }
    }

    return results;
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

  const currentLanguages = collectLanguages(sectionRoot);
  if (currentLanguages.length < 1) {
    return JSON.stringify({ status: "waiting", message: "Waiting for the preferred-language list to render." });
  }

  if (mode === "read") {
    return JSON.stringify({ status: "ok", languages: currentLanguages.map((item) => item.text) });
  }

  const expected = requested.map((item) => slug(item));
  const actual = currentLanguages.map((item) => item.slug);

  if (expected.length !== actual.length) {
    return JSON.stringify({
      status: "error",
      message: `Requested ${expected.length} languages, but the page shows ${actual.length}.`
    });
  }

  const missing = expected.filter((item) => !actual.includes(item));
  if (missing.length > 0) {
    return JSON.stringify({
      status: "error",
      message: `Requested languages are not present on the page: ${missing.join(", ")}.`
    });
  }

  const dialog = [...document.querySelectorAll("[role='dialog'], dialog, c-wiz")]
    .find((node) => isVisible(node) && /save|cancel|done/i.test(textOf(node)));

  if (!dialog) {
    const editButton = findClickable(["edit"], sectionRoot) || findClickable(["edit"]);
    if (!editButton) {
      return JSON.stringify({ status: "error", message: "Could not locate the Edit button on the Google Account language page." });
    }
    editButton.click();
    return JSON.stringify({ status: "waiting", message: "Opening the preferred-language editor." });
  }

  const editableLanguages = collectLanguages(dialog);
  if (editableLanguages.length < 1) {
    return JSON.stringify({ status: "waiting", message: "Waiting for the preferred-language editor contents." });
  }

  const matchesOrder = editableLanguages.map((item) => item.slug).join("\n") === expected.join("\n");
  if (!matchesOrder) {
    const listRoot = editableLanguages[0].node.closest("[role='list'], ul, ol, div") || dialog;
    const itemBySlug = new Map(editableLanguages.map((item) => [item.slug, item.node]));

    for (const targetSlug of expected) {
      const item = itemBySlug.get(targetSlug);
      if (!item) {
        return JSON.stringify({ status: "error", message: `Could not find editable row for ${targetSlug}.` });
      }
      listRoot.appendChild(item);
    }
  }

  const saveButton = findClickable(["save", "done"], dialog) || findClickable(["save", "done"]);
  if (!saveButton) {
    return JSON.stringify({ status: "error", message: "Could not locate the Save button in the preferred-language editor." });
  }

  saveButton.click();
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

safari_open_page "$preferred_languages_url"

case "$command" in
  read)
    wait_for_payload read | json_extract languages
    ;;
  write)
    [ "$#" -gt 0 ] || fail "The write helper requires at least one requested language label."
    wait_for_payload write "$(requested_json_from_args "$@")" >/dev/null
    ;;
  *)
    fail "Unknown helper command: $command"
    ;;
esac
