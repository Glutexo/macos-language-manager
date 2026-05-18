# Wingspan Language Manager Technical Notes

This document describes how the Wingspan module behind `manage-languages.sh` reads and writes Wingspan language settings on macOS, where the language is stored, and how the supported values are validated.

## Storage Location

The module reads and writes the macOS preferences plist:

```text
~/Library/Preferences/com.Monster-Couch.Wingspan.plist
```

The path can be overridden for tests or custom setups through:

```text
WINGSPAN_PREFERENCES_FILE
```

## Stored Key

The module manages this plist key:

```text
I2 Language
```

This is a string value used by the game's localization layer.

Observed example:

```text
I2 Language = Deutsch
```

## Read Flow

The module tries to read the current value in this order:

1. `defaults read <plist-path> "I2 Language"`
2. `/usr/libexec/PlistBuddy -c 'Print :"I2 Language"' <plist-path>`

If both fail, the runner reports that it could not detect the current Wingspan language.

## Write Flow

The module updates the plist through Python `plistlib`:

1. load the full plist
2. replace `I2 Language`
3. write the plist back while preserving the surrounding structure

The shared runner creates a `.bak` backup before writing.

## Supported Language Values

The module currently accepts these canonical values:

- `English`
- `Polski`
- `Deutsch`
- `Français`
- `Español`
- `Português (BR)`
- `日本語`
- `Русский`
- `简体中文`
- `繁體中文`
- `Italiano`
- `한국어`
- `Українська`

These values were derived from the installed game's Unity data and the active preference key on this Mac.

## Accepted Aliases

The module also normalizes a small ISO-style alias set:

- `de` → `Deutsch`
- `en` → `English`
- `es` → `Español`
- `fr` → `Français`
- `it` → `Italiano`
- `ja` → `日本語`
- `ko` → `한국어`
- `pl` → `Polski`
- `pt` and `pt-BR` → `Português (BR)`
- `ru` → `Русский`
- `uk` → `Українська`
- `zh`, `zh-CN`, and `zh-Hans` → `简体中文`
- `zh-TW` and `zh-Hant` → `繁體中文`

## Running Detection

The module treats the game as running when:

```bash
pgrep -x Wingspan
```

If the process appears to be running, the shared runner blocks writes unless `--force` was provided.

## Backup Scope

The module asks the shared runner to back up:

```text
~/Library/Preferences/com.Monster-Couch.Wingspan.plist
```

Restore uses the same file and its matching `.bak`.

## Tests

- `./tests/test-manage-languages.sh`
