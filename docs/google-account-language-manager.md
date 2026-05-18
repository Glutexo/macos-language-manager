# Google Account Language Manager Technical Notes

This document describes the experimental `google-account` module behind `manage-languages.sh`.

## Scope

The module targets the preferred language list in a signed-in Google account.

Version 1 is intentionally narrow:

- it uses Safari browser automation
- it reads the current preferred-language list from the Google Account language page
- it attempts to reorder the existing list only
- it does not add new languages yet
- it does not remove existing languages yet
- it does not use a public Google API, because no supported public API for preferred-language ordering was identified

## Entry Point

```text
./manage-languages.sh google-account
```

## Usage

```bash
./manage-languages.sh google-account
./manage-languages.sh google-account --dry-run "English" "Czech"
./manage-languages.sh google-account "English" "Czech"
```

Behavior:

- without language arguments, the module prints the current preferred-language list
- with language arguments, the module expects the full final list in the requested order
- language arguments currently match the visible labels from the Google Account page rather than a separate ISO-tag mapping layer

## Automation Strategy

The module delegates to:

```text
./language-modules/google-account-safari-helper.sh
```

The helper:

1. opens `https://myaccount.google.com/language?hl=en` in Safari
2. waits for the Google Account language page to become available
3. executes JavaScript in the active Safari tab to inspect the page
4. returns the detected preferred-language labels back to the shell command
5. when writing, opens the preferred-language editor, tries to reorder the existing rows to the requested sequence, and clicks Save

The page is forced to `hl=en` so the automation can rely on stable English UI text when it looks for sign-in or page-state hints.

## Requirements

- Safari
- permission to run AppleScript automation against Safari
- a signed-in Google session, or enough time to complete sign-in and 2-step verification while the helper waits

## Current Limitations

- the write path is best-effort DOM automation against a live Google page and may break when Google changes the page structure
- page structure changes on Google's side may break the helper
- there is no backup or restore mode because the data lives remotely in the Google account
- `--inherit-macos` and `--force` are not supported for this module

## Environment Variables

- `GOOGLE_ACCOUNT_LANGUAGE_COMMAND` → override the module command wrapper
- `GOOGLE_ACCOUNT_LANGUAGE_HELPER` → override the Safari helper, useful for tests
- `GOOGLE_ACCOUNT_LANGUAGE_URL` → override the Google Account language page URL
- `GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT` → timeout in seconds for sign-in and page loading

## Related Files

- `language-modules/google-account.sh`
- `language-modules/google-account-command.sh`
- `language-modules/google-account-safari-helper.sh`
