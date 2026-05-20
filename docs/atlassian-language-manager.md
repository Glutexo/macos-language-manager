# Atlassian Account Language Manager Technical Notes

This document describes the `atlassian` module behind `manage-languages.sh`.

## Scope

The module targets the Atlassian account language preference used by signed-in Atlassian Cloud products such as Jira.

Version 1 is intentionally narrow:

- it uses Safari browser automation
- it reads the current Atlassian account language from the account preferences page
- it writes one selected Atlassian account language
- it supports `--inherit-macos` by mapping the first current macOS preferred language to a supported Atlassian account language
- it supports the same Safari profile-selection flow as `google`
- it does not use `acli`, because the locally available CLI does not expose an account-language command here

## Entry Point

```text
./manage-languages.sh atlassian
```

## Usage

```bash
./manage-languages.sh atlassian
./manage-languages.sh atlassian Czech
./manage-languages.sh atlassian "English (US)"
./manage-languages.sh atlassian --inherit-macos
./manage-languages.sh atlassian --browser-profile work Czech
./manage-languages.sh atlassian --all-browser-profiles --dry-run Japanese
```

Behavior:

- without a language argument, the module prints the current Atlassian account language
- with a language argument, the module changes one Atlassian account language preference
- `--inherit-macos` maps the first current macOS preferred language tag to one supported Atlassian account language
- `--browser-profile NAME` targets one browser profile; repeat the switch to target more than one
- `--all-browser-profiles` targets every valid browser profile
- use `./manage-languages.sh safari-profiles` to inspect or refresh the shared Safari profile cache

## Automation Strategy

The module delegates to:

```text
./language-modules/atlassian-safari-helper.sh
```

The helper:

1. opens `https://id.atlassian.com/manage-profile/account-preferences` in Safari
2. waits for the Atlassian account preferences page to become available
3. detects the visible language control through page JavaScript
4. reads the current language value from that control
5. when writing, selects the requested language and clicks a visible save button when Atlassian renders one
6. when browser profiles are selected, opens a dedicated Safari window for that profile through Safari's File menu and runs the same flow once per selected profile
7. when profile names are needed during normal runs, reads the shared Safari profile cache first, then Safari's `SafariTabs.db` profile rows when that database is available, then falls back to `default`

## Requirements

- Safari
- permission to run AppleScript automation against Safari
- a signed-in Atlassian session, or enough time to complete sign-in and verification while the helper waits

## Current Limitations

- the write path depends on the current Atlassian account-preferences page structure and visible controls rather than a supported public API
- page structure changes on Atlassian's side may break the helper
- there is no backup or restore mode because the data lives remotely in the Atlassian account
- `--force` is not supported for this module

## Environment Variables

- `ATLASSIAN_ACCOUNT_LANGUAGE_COMMAND` → override the module command wrapper
- `ATLASSIAN_ACCOUNT_LANGUAGE_HELPER` → override the Safari helper, useful for tests
- `ATLASSIAN_ACCOUNT_LANGUAGE_URL` → override the Atlassian account preferences URL
- `ATLASSIAN_ACCOUNT_LANGUAGE_TIMEOUT` → timeout in seconds for sign-in and page loading
- `ATLASSIAN_ACCOUNT_SAFARI_TABS_DB` → override the Safari profile database path, useful for tests
- `ATLASSIAN_ACCOUNT_BROWSER_PROFILE_CACHE` → override the shared Safari profile-name cache path for this module
- `SAFARI_BROWSER_PROFILE_CACHE` → override the shared default Safari profile-name cache path
- `ATLASSIAN_ACCOUNT_BROWSER_PROFILE` → helper-internal selector for one browser profile
- `ATLASSIAN_ACCOUNT_BROWSER_PROFILES` → newline-separated helper override for valid browser profile names, useful for tests

## Related Files

- `language-modules/atlassian.sh`
- `language-modules/atlassian-command.sh`
- `language-modules/atlassian-safari-helper.sh`
