# Google Account Language Manager Technical Notes

This document describes the experimental `google` module behind `manage-languages.sh`.

## Scope

The module targets the preferred language list in a signed-in Google account.

Version 1 is intentionally narrow:

- it uses Safari browser automation
- it reads the current preferred-language list from the Google Account language page
- it uses the same command-line token syntax as the macOS module
- it can reorder, remove, or add languages through the Google Account page
- it can disable Google's `Automatically add languages` setting through the same page when requested
- it can enable Google's `Automatically add languages` setting through the same page when requested
- it supports `--inherit-macos` by resolving the full current macOS preferred language list against the current Google list or addable Google language labels
- it does not use a public Google API, because no supported public API for preferred-language ordering was identified

## Entry Point

```text
./manage-languages.sh google
```

## Usage

```bash
./manage-languages.sh google
./manage-languages.sh google --all-known-browser-profiles --dry-run "English"
./manage-languages.sh google --browser-profile work --browser-profile personal
./manage-languages.sh google --disable-auto-add
./manage-languages.sh google --enable-auto-add
./manage-languages.sh google --inherit-macos
./manage-languages.sh google --dry-run "English:Czech"
./manage-languages.sh google "English" "-Czech"
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
- `--browser-profile NAME` → target one browser profile; repeat the switch to target more than one
- `--all-browser-profiles` → target every valid browser profile
- `--all-known-browser-profiles` → target every browser profile currently known to the helper
- use `./manage-languages.sh safari-profiles` to inspect or refresh the shared Safari profile cache
- `--disable-auto-add` → turn off Google's `Automatically add languages` setting before writing; with no language arguments it performs only that maintenance step
- `--enable-auto-add` → turn Google's `Automatically add languages` setting back on before writing; with no language arguments it performs only that maintenance step

## Automation Strategy

The module delegates to:

```text
./language-modules/google-safari-helper.sh
```

The helper:

1. opens `https://myaccount.google.com/language?hl=en` in Safari
2. waits for the Google Account language page to become available
3. executes JavaScript in the active Safari tab to inspect the page
4. returns the detected preferred-language labels back to the shell command
5. when writing, opens a dedicated Safari window for the session and sends the same Google internal update request that the page uses for preferred-language ordering
6. when `--disable-auto-add` is requested, follows Google's own `Stop adding` confirmation flow through page JavaScript without depending on the window being frontmost
7. when `--enable-auto-add` is requested, toggles the same setting back on through page JavaScript
8. when browser profiles are selected, opens a dedicated Safari window for that profile through Safari's File menu and runs the same flow once per selected profile
9. when profile names are needed during normal runs, reads the shared Safari profile cache first, then Safari's `SafariTabs.db` profile rows when that database is available, then falls back to `default`

The page is forced to `hl=en` so the automation can rely on stable English UI text when it looks for sign-in or page-state hints.

## Requirements

- Safari
- permission to run AppleScript automation against Safari
- a signed-in Google session, or enough time to complete sign-in and 2-step verification while the helper waits

## Current Limitations

- the write path depends on internal Google page requests and maintenance controls rather than a supported public API, so Google-side changes may still break it
- Google may still surface `Added for you` entries separately from the main preferred-language list; the command warns when it sees them
- Safari does not expose named profiles through its AppleScript dictionary here; the helper therefore uses Safari UI automation for explicit profile discovery and profile-window creation
- page structure changes on Google's side may break the helper
- there is no backup or restore mode because the data lives remotely in the Google account
- `--force` is not supported for this module

## Environment Variables

- `GOOGLE_ACCOUNT_LANGUAGE_COMMAND` → override the module command wrapper
- `GOOGLE_ACCOUNT_LANGUAGE_HELPER` → override the Safari helper, useful for tests
- `GOOGLE_ACCOUNT_LANGUAGE_URL` → override the Google Account language page URL
- `GOOGLE_ACCOUNT_LANGUAGE_TIMEOUT` → timeout in seconds for sign-in and page loading
- `GOOGLE_ACCOUNT_SAFARI_TABS_DB` → override the Safari profile database path, useful for tests
- `GOOGLE_ACCOUNT_BROWSER_PROFILE_CACHE` → override the shared Safari profile-name cache path for this module
- `SAFARI_BROWSER_PROFILE_CACHE` → override the shared default Safari profile-name cache path
- `GOOGLE_ACCOUNT_BROWSER_PROFILE` → helper-internal selector for one browser profile
- `GOOGLE_ACCOUNT_BROWSER_PROFILES` → newline-separated helper override for valid browser profile names, useful for tests

## Related Files

- `language-modules/google.sh`
- `language-modules/google-command.sh`
- `language-modules/google-safari-helper.sh`
