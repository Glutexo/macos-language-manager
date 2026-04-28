# macOS Language Manager Technical Notes

This document describes what `manage-macos-languages.sh` reads and writes on macOS, where the values are stored, and how the script interprets language identifiers.

## Scope

The script works with five targets:

- `account`
- `login-window`
- `locale`
- `startup`
- `all`

These targets are not aliases. Each one maps to a different macOS setting backend.

## What The Script Reads

### Account language order

Command:

```bash
defaults read -g AppleLanguages
```

Meaning:

- Reads the current user's global preferred language order.
- This is the standard macOS `AppleLanguages` array in the current user's defaults domain.

Expected format:

- A property-list array of language tags.
- Typical values look like `en-US`, `cs-CZ`, `ja`, `fr-FR`.

### Login window language order

Command:

```bash
defaults read /Library/Preferences/.GlobalPreferences AppleLanguages
```

Meaning:

- Reads the system-wide language order from `/Library/Preferences/.GlobalPreferences`.
- This is used for system contexts such as the login window.

Expected format:

- A property-list array of language tags.
- Same tag style as `AppleLanguages` for the user account.

### Account locale

Command:

```bash
defaults read -g AppleLocale
```

Meaning:

- Reads the current user's locale.
- This affects formatting behavior such as dates, numbers, and separators.

Expected format:

- Locale string such as `cs_CZ`, `en_US`, `ja_CZ`.
- The script normalizes it to language-tag-like form by changing `_` to `-` when it needs to derive a language.

### System locale

Command:

```bash
defaults read /Library/Preferences/.GlobalPreferences AppleLocale
```

Meaning:

- Reads the system locale from the global preferences domain.

Expected format:

- Same locale format as the account locale, for example `cs_CZ`.

### Startup language setting

Command:

```bash
nvram prev-lang:kbd
```

Meaning:

- Reads the startup language and keyboard layout value from NVRAM.
- The script uses this for the `startup` target and includes it in the merged data for `all`.

Expected format:

- A string like `ko:252`.
- The part before `:` is the startup language code.
- The part after `:` is the keyboard layout ID.

### Selected keyboard layout fallback

Command:

```bash
defaults read com.apple.HIToolbox AppleSelectedInputSources
```

Meaning:

- Reads the currently selected keyboard layout when `prev-lang:kbd` does not already contain a layout ID.
- The script extracts `KeyboardLayout ID` from this structure.

## What The Script Writes

### `account`

Command:

```bash
defaults write -g AppleLanguages -array ...
```

Writes:

- The current user's `AppleLanguages` array.

### `login-window`

Commands:

```bash
sudo defaults write /Library/Preferences/.GlobalPreferences AppleLanguages -array ...
sudo diskutil apfs updatePreboot /
```

Writes:

- The system-wide `AppleLanguages` array.

Additional behavior:

- After writing, the script refreshes APFS preboot data.
- This is intended to help FileVault and preboot screens pick up the new language settings.

### `locale`

Commands:

```bash
defaults write -g AppleLocale VALUE
sudo defaults write /Library/Preferences/.GlobalPreferences AppleLocale VALUE
```

Writes:

- The account locale.
- The system locale.

Format conversion:

- The script derives the locale from the effective language.
- It converts hyphens to underscores, so `ja-CZ` becomes `ja_CZ`.

### `startup`

Commands:

```bash
sudo nvram "prev-lang:kbd=VALUE"
sudo nvram -s
```

Writes:

- The NVRAM variable `prev-lang:kbd`.

Format:

- Usually `language:keyboardLayoutId`, for example `ja:252`.
- The script writes only the base language code before `:`.
- If a keyboard layout ID is available, it preserves or reuses it.

### `all`

The `all` target combines all of the above:

- writes account `AppleLanguages`
- writes login-window `AppleLanguages`
- writes account `AppleLocale`
- writes system `AppleLocale`
- writes `prev-lang:kbd`
- refreshes APFS preboot data

## How Language Ordering Works

The script does not just prepend values blindly. It builds an internal ordered entity tree with three root sections:

- `front`
- `base`
- `end`

Behavior by argument type:

- `xx` or `+xx` → move or add the language to the front section
- `-xx` → remove matching languages after ordering is resolved
- `xx:yy` → move or add `xx` immediately before `yy`
- `xx:` → move or add `xx` at the end section

Important detail:

- Anchored placements are resolved before removals.
- Because of that, `ja:ko -ko` and `-ko ja:ko` produce the same Japanese placement.

## Matching Rules

Matching is intentionally broader than exact string equality.

### Exact tag

- A request like `en-US` first matches `en-US`.

### Base language match

- A request like `en` can match region-specific entries such as `en-US`.
- Removal with `-en` can therefore remove `en-US`.

### Region-aware partial matching

- For a request without `-`, the script can match language tags where the next subtag is a 2- or 3-character region code.
- This is why `ko` matches `ko-KR`.

## Missing Language Construction

If a requested language is not already present, the script constructs a new tag.

### Request already contains region

- `en-US` stays `en-US`.

### Request is a base language only

The script tries to append the current region.

Region lookup order:

1. account `AppleLocale`
2. system `AppleLocale`
3. `LC_ALL`
4. `LC_MESSAGES`
5. `LANG`

Examples:

- with `cs_CZ`, requesting `ja` becomes `ja-CZ`
- without a detectable region, `ja` stays `ja`

## How `locale` And `startup` Choose Their Output Value

The effective language is chosen like this:

- if the resulting ordered language list is non-empty, use its first item
- otherwise use the first added language argument

Consequences:

- `locale` and `startup` require at least one added language argument
- a remove-only command is rejected for these targets

## Where The Supported macOS Language List Comes From

Verbose help does not use a hardcoded in-repo whitelist.

It reads Apple's renderable UI language list:

```text
/System/Library/PrivateFrameworks/IntlPreferences.framework/Resources/RenderableUILanguages.plist
```

The script preserves Apple's order, normalizes `_` to `-`, and prints the tags from that plist. This matches the language identifiers used by System Settings > Language & Region for addable UI languages.

For tests or investigation, `MACOS_LANGUAGE_RENDERABLE_UI_LANGUAGES_PATH` can point to another plist file with the same array format.

## Privilege Boundaries

The script escalates only where necessary.

No `sudo` required:

- reading user defaults
- writing account `AppleLanguages`
- writing account `AppleLocale`

`sudo` required:

- writing login-window `AppleLanguages`
- writing system `AppleLocale`
- refreshing APFS preboot data
- writing and syncing `prev-lang:kbd`

Note:

- The script uses `sudo` automatically unless it is already running as root.

## Dry Run Behavior

With `--dry-run`:

- the script computes and prints the new values
- it does not write defaults
- it does not write NVRAM
- it does not refresh preboot data

## Restart Behavior

With `--restart`:

- after evaluation, the script requests a restart via AppleScript:

```bash
osascript -e 'tell application "System Events" to restart'
```

This flag can be combined with `--dry-run`.

## Environment Variables Used For Testing Or Overrides

- `MACOS_LANGUAGE_LPROJ_DIRS` → override directories scanned for `.lproj`
- `MACOS_LANGUAGE_CATALOG_PATH` → override Perl locale catalog path

## Related Tests

- `./tests/test-manage-macos-languages.sh`

The test suite stubs `defaults` and `nvram` and verifies:

- verbose language discovery
- region expansion such as `ja` → `ja-CZ`
- anchor ordering behavior
- removal behavior
- derived locale and startup values
