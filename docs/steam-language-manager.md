# Steam Language Manager Technical Notes

This document describes what `manage-steam-language.sh` reads and writes, where the Steam language is stored, and how the file format is handled.

## Scope

The script manages the Steam client interface language on macOS.

It does not modify macOS `AppleLanguages`, `AppleLocale`, or NVRAM settings.

## Storage Location

Default Steam directory:

```text
$HOME/Library/Application Support/Steam
```

Registry file:

```text
$HOME/Library/Application Support/Steam/registry.vdf
```

Override:

- `STEAM_DIR` can point to a different Steam directory.
- The script then reads `registry.vdf` from that directory.

## What The Script Reads

### Registry file existence

Before anything else, the script checks that this file exists:

```text
$STEAM_DIR/registry.vdf
```

If the file is missing, the script fails.

### Current language value

The script reads the current Steam language from `registry.vdf` using Perl regex matching.

Primary lookup:

- look for `"steamglobal" { "language" "..." }`

Fallback lookup:

- look for the first standalone `"language" "..."` entry

## File Format

Steam stores the value in a VDF-like text file.

The tests use this structure:

```text
"Steam"
{
  "steamglobal"
  {
    "language"    "english"
  }
  "language"    "english"
}
```

Important characteristics:

- it is a text file, not JSON or XML
- the script does not parse it as a full VDF AST
- it updates matching language fields with multiline Perl regex replacements

## Supported Language Values

The script uses a hardcoded allowlist.

Supported values:

- `bulgarian`
- `schinese`
- `tchinese`
- `czech`
- `danish`
- `dutch`
- `english`
- `finnish`
- `french`
- `german`
- `greek`
- `hungarian`
- `indonesian`
- `italian`
- `japanese`
- `koreana`
- `norwegian`
- `polish`
- `portuguese`
- `brazilian`
- `romanian`
- `russian`
- `spanish`
- `latam`
- `swedish`
- `thai`
- `turkish`
- `ukrainian`
- `vietnamese`

Validation rules:

- value must begin with lowercase ASCII letters
- value must exactly match one item from the allowlist

Consequences:

- `japanese` is valid
- `Japanese` is rejected
- unsupported values such as `klingon` are rejected

## What The Script Writes

When changing the language, the script does this:

1. copies `registry.vdf` to `registry.vdf.bak`
2. edits `registry.vdf` in place with Perl
3. prints the old and new value
4. asks the user to restart Steam

Backup file:

```text
registry.vdf.bak
```

## Replacement Strategy

The script updates multiple possible patterns in the registry file.

It attempts replacements for:

- `"steamglobal" { "language" "..." }`
- `"Steamsteamglobal" { "language" "..." }`
- a broader nested `"Steam" ... "steamglobal" ... "language" ...` pattern

Behavior:

- replacements are done with `perl -0pi`, so the file is read as a single string
- the script counts how many replacements happened
- if none matched, the script fails with `No Steam language entries were updated`

## Running Steam Detection

The script checks whether Steam appears to be running:

```bash
pgrep -x Steam
```

Default behavior:

- if Steam is running and `--force` is not used, the script aborts without modifying the file

With `--force`:

- the write proceeds even if Steam is running

## Read-Only Mode

If no language argument is provided:

- the script only prints the current Steam interface language
- no file is modified

## Dry Run Behavior

With `--dry-run`:

- the script validates the requested language
- it prints the planned change
- it does not write `registry.vdf`
- it does not create the backup file

## Verbose Help Source

Unlike the macOS script, Steam language values do not come from the system.

They come from the in-script `supported_languages` array.

`--verbose` prints that array.

## Environment Variables Used For Testing Or Overrides

- `STEAM_DIR` → override Steam directory location

## Related Tests

- `./tests/test-manage-steam-language.sh`

The test suite verifies:

- help and verbose help output
- dry-run behavior
- language validation
- running-Steam protection
- forced writes
- backup creation
- in-place registry updates
