# Factorio Language Manager Technical Notes

This document describes how the Factorio module behind `manage-app-language.sh` reads and writes Factorio language settings on macOS, where the language is stored, and how locale identifiers are validated. `manage-factorio-language.sh` remains as a compatibility wrapper.

## Scope

The Factorio module manages the Factorio interface language on macOS.

It does not modify macOS `AppleLanguages`, `AppleLocale`, or NVRAM settings.

## Storage Location

Default Factorio user data directory:

```text
$HOME/Library/Application Support/factorio
```

Config file:

```text
$HOME/Library/Application Support/factorio/config/config.ini
```

Override:

- `FACTORIO_DIR` can point to a different Factorio user data directory.
- The script then reads `config/config.ini` from that directory.

## What The Script Reads

### Config file existence

Before anything else, the script checks that this file exists:

```text
$FACTORIO_DIR/config/config.ini
```

If the file is missing, the script fails.

### Current language value

The script reads the current Factorio language from the `[general]` section in `config.ini`.

It looks for the first uncommented `locale=` entry inside `[general]`.

If no such entry exists and no new language was requested, the script fails.

## File Format

Factorio stores the setting in a plain INI file.

The typical layout looks like this:

```text
[path]
read-data=__PATH__system-read-data__
write-data=__PATH__system-write-data__

[general]
locale=en
```

Important characteristics:

- it is a text file, not JSON or XML
- comments begin with `;`
- the script only touches the `[general]` section
- if `[general]` exists but `locale=` is missing, the script inserts a new `locale=` line at the top of that section

## Supported Language Values

The script uses a hardcoded allowlist.

Source:

- Factorio 2.0 macOS app bundle locale directories under `Contents/data/core/locale`
- the list mirrors the directory names currently shipped with the game data

Supported values:

- `af`
- `ar`
- `be`
- `bg`
- `ca`
- `cs`
- `da`
- `de`
- `el`
- `en`
- `eo`
- `es-ES`
- `et`
- `eu`
- `fa`
- `fi`
- `fil`
- `fr`
- `fy-NL`
- `ga-IE`
- `he`
- `hr`
- `hu`
- `id`
- `is`
- `it`
- `ja`
- `ka`
- `kk`
- `ko`
- `lt`
- `lv`
- `nl`
- `no`
- `pl`
- `pt-BR`
- `pt-PT`
- `ro`
- `ru`
- `sk`
- `sl`
- `sq`
- `sr`
- `sv-SE`
- `th`
- `tr`
- `uk`
- `vi`
- `zh-CN`
- `zh-TW`

Validation rules:

- the value may contain ASCII letters, `_`, and `-`
- `_` is normalized to `-`
- matching is case-insensitive before canonicalization
- aliases such as `es`, `fy`, `ga`, `pt`, `sv`, `zh`, and `zh-tw` map to one canonical supported value

Consequences:

- `ja` is valid
- `zh-cn` is normalized to `zh-CN`
- `pt` is normalized to `pt-PT`
- unsupported values such as `klingon` are rejected

## What The Script Writes

When changing the language, the script does this:

1. copies `config.ini` to `config.ini.bak`
2. updates or inserts `locale=` inside `[general]`
3. prints the old and new value
4. asks the user to restart Factorio

Backup file:

```text
config.ini.bak
```

## Replacement Strategy

The script rewrites only the `[general]` section.

Behavior:

- if `locale=` already exists in `[general]`, that first uncommented entry is replaced
- if `[general]` exists but has no `locale=`, a new `locale=` line is inserted at the top of the section
- if `[general]` is missing, the script fails

## Running Factorio Detection

The script checks whether Factorio appears to be running:

```bash
pgrep -x factorio || pgrep -x Factorio
```

Default behavior:

- if Factorio is running and `--force` is not used, the script aborts without modifying the file

With `--force`:

- the write proceeds even if Factorio is running

## Read-Only Mode

If no language argument is provided:

- the script only prints the current Factorio interface language
- no file is modified
- if `[general]` has no uncommented `locale=`, the script fails

## Dry Run Behavior

With `--dry-run`:

- the script validates the requested language
- it prints the planned change
- it does not write `config.ini`
- it does not create the backup file

## Verbose Help Source

Unlike the macOS script, Factorio language values do not come from the system.

They come from the in-script `supported_languages` array.

`--verbose` prints that array.

## Environment Variables Used For Testing Or Overrides

- `FACTORIO_DIR` → override Factorio user data directory

## Related Tests

- `./tests/test-manage-factorio-language.sh`

The test suite verifies:

- help and verbose help output
- dry-run behavior
- language validation and alias mapping
- running-Factorio protection
- forced writes
- backup creation
- in-place `config.ini` updates
