# Safari Profiles Manager Technical Notes

This document describes the `safari-profiles` module behind `manage-languages.sh`.

## Scope

The module manages the shared Safari browser-profile cache used by browser-automation modules such as `google-account` and `atlassian-account`.

It does not change any language settings.

## Entry Point

```text
./manage-languages.sh safari-profiles
```

## Usage

```bash
./manage-languages.sh safari-profiles
./manage-languages.sh safari-profiles --refresh
./manage-languages.sh safari-profiles --clear-cache
./manage-languages.sh safari-profiles --list-cache
./manage-languages.sh safari-profiles --list-effective
./manage-languages.sh safari-profiles --show-cache-path
```

Behavior:

- without options, the module prints the cache path, cached profile names, and the effective profile list
- `--refresh` updates the shared Safari profile cache from Safari's File menu
- `--clear-cache` removes the cache file
- `--list-cache` prints only the cached profile names
- `--list-effective` prints the effective profile names using cache first, then `SafariTabs.db`, then `default`
- `--show-cache-path` prints the cache file path

## Automation Strategy

The module delegates to the shared helper:

```text
./language-modules/safari-browser-profile-helper.sh
```

That helper:

1. reads the current cache file when it exists
2. refreshes the cache by reading Safari's File menu through UI automation
3. falls back to local Safari `SafariTabs.db` profile rows when the cache is absent
4. falls back to `default` when neither source yields profile names

## Requirements

- Safari
- permission to run AppleScript automation against Safari for `--refresh`

## Environment Variables

- `SAFARI_PROFILES_COMMAND` → override the module command wrapper
- `SAFARI_BROWSER_PROFILE_CACHE` → override the shared Safari profile-cache path
- `SAFARI_BROWSER_PROFILE_TABS_DB` → override the Safari profile database path, useful for tests
- `SAFARI_BROWSER_PROFILE_MENU_DATA` → override the raw Safari File-menu dump, useful for tests
- `SAFARI_BROWSER_PROFILE_MENU_ITEMS` → alternate raw Safari File-menu override, useful for tests
- `SAFARI_BROWSER_PROFILES` → newline-separated override for the effective profile list, useful for tests

## Related Files

- `language-modules/safari-profiles.sh`
- `language-modules/safari-profiles-command.sh`
- `language-modules/safari-browser-profile-helper.sh`
