# Terraforming Mars Language Manager Technical Notes

This document describes how the Terraforming Mars module behind `manage-languages.sh` reads and writes Terraforming Mars language settings on macOS, where the language is stored, and how the supported values are validated.

## Storage Location

The module reads and writes the macOS preferences plist:

```text
~/Library/Preferences/Terraforming Mars.plist
```

The path can be overridden for tests or custom setups through:

```text
TERRAFORMING_MARS_PREFERENCES_FILE
```

## Stored Keys

The module keeps these plist keys in sync:

```text
I2 Language
OSXPlayerCurrentLanguage
```

Observed example:

```text
I2 Language = German
OSXPlayerCurrentLanguage = de_DE
```

`I2 Language` is the user-facing in-game language name. `OSXPlayerCurrentLanguage` is the Unity locale companion value stored alongside it.

## Read Flow

The module loads the plist through Python `plistlib` and reads the current value in this order:

1. `I2 Language`
2. `OSXPlayerCurrentLanguage`

If both are missing or empty, the runner reports that it could not detect the current Terraforming Mars language.

## Write Flow

The module updates the plist through Python `plistlib`:

1. load the full plist
2. replace `I2 Language`
3. replace `OSXPlayerCurrentLanguage` with the matching locale code
4. write the plist back while preserving the surrounding structure

The shared runner creates a `.bak` backup before writing.

## Supported Language Values

The module currently accepts these canonical values:

- `English`
- `French`
- `German`
- `Spanish`
- `Italian`
- `Swedish`

These values were derived from the installed game's Unity data and the active preference keys on this Mac.

## Accepted Aliases

The module also normalizes a small ISO-style alias set:

- `de` and `de-DE` → `German`
- `en` and `en-US` → `English`
- `es` and `es-ES` → `Spanish`
- `fr` and `fr-FR` → `French`
- `it` and `it-IT` → `Italian`
- `sv` and `sv-SE` → `Swedish`

Primary subtags are also accepted through macOS inheritance, for example `de-AT` → `German`.

## Running Detection

The module treats the game as running when:

```bash
pgrep -f '/TerraformingMars.app/Contents/MacOS/Terraforming Mars'
```

The match string can be overridden through `TERRAFORMING_MARS_PROCESS_MATCH`.

If the process appears to be running, the shared runner blocks writes unless `--force` was provided.

## Backup Scope

The module asks the shared runner to back up:

```text
~/Library/Preferences/Terraforming Mars.plist
```

Restore uses the same file and its matching `.bak`.

## Tests

- `./tests/test-manage-languages.sh`
