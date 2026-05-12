# Anki Language Manager Technical Notes

This document describes how the Anki module behind `manage-app-language.sh` reads and writes Anki language settings on macOS, where the language is stored, and how locale identifiers are validated. `manage-anki-language.sh` remains as a compatibility wrapper.

## Scope

The Anki module manages the Anki interface language on macOS.

It does not modify macOS `AppleLanguages`, `AppleLocale`, or NVRAM settings.

## Storage Location

Default Anki base directory:

```text
$HOME/Library/Application Support/Anki2
```

Preferences database:

```text
$HOME/Library/Application Support/Anki2/prefs21.db
```

Override:

- `ANKI_BASE_DIR` can point to a different Anki base directory.
- The script then reads `prefs21.db` from that directory.

## What The Script Reads

### Preferences database existence

Before anything else, the script checks that this file exists:

```text
$ANKI_BASE_DIR/prefs21.db
```

If the file is missing, the script fails.

### Current language value

The script reads the current Anki language from the `_global` row in the `profiles` table.

Lookup steps:

1. open `prefs21.db` with SQLite
2. read `profiles.data` where `name = '_global'`
3. unpickle the stored Python dictionary
4. read the `defaultLang` key

If `_global` or `defaultLang` is missing, the script fails.

## File Format

Anki stores global preferences in a SQLite database.

Relevant table:

```sql
create table if not exists profiles
(name text primary key collate nocase, data blob not null);
```

Important characteristics:

- the `data` column is a Python pickle blob, not JSON
- the script does not attempt to rewrite unrelated keys
- only `_global.defaultLang` is changed

## Supported Language Values

The script uses a hardcoded allowlist of canonical Anki locale codes.

Source:

- Anki source, `pylib/anki/lang.py`, `langs`
- Anki FAQ, Changing the interface language: https://faqs.ankiweb.net/changing-the-interface-language.html

Examples of canonical values:

- `en_US`
- `en_GB`
- `cs_CZ`
- `ja_JP`
- `pt_BR`
- `pt_PT`
- `zh_CN`
- `zh_TW`
- `yi`
- `ug`

Short aliases are also accepted when they map cleanly to one canonical value.

Examples:

- `ja` → `ja_JP`
- `cs` → `cs_CZ`
- `en` → `en_US`
- `zh` → `zh_CN`
- `pt` → `pt_PT`

Validation rules:

- value must begin with ASCII letters and may include `_` or `-`
- `-` is normalized to `_`
- the normalized value must match the allowlist, or a supported short alias must map to one allowlist entry

Consequences:

- `ja` is valid and becomes `ja_JP`
- `ja-JP` is valid and becomes `ja_JP`
- `Japanese` is rejected
- unsupported values such as `klingon` are rejected

## What The Script Writes

When changing the language, the script does this:

1. copies `prefs21.db` to `prefs21.db.bak`
2. opens `prefs21.db` with SQLite
3. unpickles `_global` metadata
4. updates `defaultLang`
5. writes the pickle blob back
6. prints the old and new value
7. asks the user to restart Anki

Backup file:

```text
prefs21.db.bak
```

## Running Anki Detection

The script checks whether Anki appears to be running:

```bash
pgrep -x Anki
```

Default behavior:

- if Anki is running and `--force` is not used, the script aborts without modifying the database

With `--force`:

- the write proceeds even if Anki is running

## Read-Only Mode

If no language argument is provided:

- the script only prints the current Anki interface language
- no file is modified

## Dry Run Behavior

With `--dry-run`:

- the script validates and canonicalizes the requested language
- it prints the planned change
- it does not write `prefs21.db`
- it does not create the backup file

## Environment Variables Used For Testing Or Overrides

- `ANKI_BASE_DIR` → override Anki base directory location

## Related Tests

- `./tests/test-manage-anki-language.sh`
