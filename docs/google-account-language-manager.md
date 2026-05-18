# Google Account Language Manager Technical Notes

This document describes the experimental `google-account` module behind `manage-languages.sh`.

## Scope

The module targets the preferred language list in a signed-in Google account.

Version 1 is intentionally narrow:

- it uses Safari browser automation
- it reads the current preferred-language list from the Google Account language page
- it uses the same command-line token syntax as the macOS module
- it can reorder, remove, or add languages through the Google Account page
- it supports `--inherit-macos` by resolving the full current macOS preferred language list against the current Google list or addable Google language labels
- it does not use a public Google API, because no supported public API for preferred-language ordering was identified

## Entry Point

```text
./manage-languages.sh google-account
```

## Usage

```bash
./manage-languages.sh google-account
./manage-languages.sh google-account --inherit-macos
./manage-languages.sh google-account --dry-run "English:Czech"
./manage-languages.sh google-account "English" "-Czech"
```

Behavior:

- without language arguments, the module prints the current preferred-language list
- with language arguments, the module applies the same token parsing model as `manage-languages.sh macos`
- language arguments currently match the visible labels from the Google Account page rather than a separate ISO-tag mapping layer

Token forms:

- `xx` or `+xx` → move the matching language to the front
- `-xx` → remove the matching language after ordering
- `xx:yy` or `+xx:yy` → move `xx` immediately before `yy`
- `xx:` or `+xx:` → move `xx` to the end
- `--inherit-macos` or `-M` → replace the Google Account list with the full current macOS preferred language order

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
5. when writing, opens a dedicated Safari window for the session, adds missing languages when needed, removes extra ones, and repeatedly uses the page controls until the on-page order matches the requested sequence

The page is forced to `hl=en` so the automation can rely on stable English UI text when it looks for sign-in or page-state hints.

## Requirements

- Safari
- permission to run AppleScript automation against Safari
- a signed-in Google session, or enough time to complete sign-in and 2-step verification while the helper waits

## Current Limitations

- the write path is best-effort DOM automation against a live Google page and may break when Google changes the page structure
- page structure changes on Google's side may break the helper
- there is no backup or restore mode because the data lives remotely in the Google account
- `--force` is not supported for this module

## Environment Variables

- `GOOGLE_ACCOUNT_LANGUAGE_COMMAND` → override the module command wrapper
- `GOOGLE_ACCOUNT_LANGUAGE_HELPER` → override the Safari helper, useful for tests
- `GOOGLE_ACCOUNT_LANGUAGE_URL` → override the Google Account language page URL
- `GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT` → timeout in seconds for sign-in and page loading

## Related Files

- `language-modules/google-account.sh`
- `language-modules/google-account-command.sh`
- `language-modules/google-account-safari-helper.sh`
