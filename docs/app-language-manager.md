# App Language Manager Technical Notes

This document describes the shared architecture behind `manage-app-language.sh` and the dynamically loaded application modules in `language-modules/`.

## Scope

The runner manages application interface languages for supported macOS applications.

It does not modify macOS `AppleLanguages`, `AppleLocale`, or NVRAM settings.

## Entry Points

Primary runner:

```text
./manage-app-language.sh
```

## Module Discovery

The runner loads modules from:

```text
./language-modules
```

Each `*.sh` file in that directory becomes one available application id.

Examples:

- `language-modules/steam.sh` → `steam`
- `language-modules/anki.sh` → `anki`
- `language-modules/factorio.sh` → `factorio`

`--list-apps` prints the discovered ids.

`--self-test` loads each discovered module and verifies that the required shell functions and metadata are present.

## Command-Line Interface

Unified usage:

```bash
./manage-app-language.sh <app> [--dry-run|-n] [--force|-f] [language]
./manage-app-language.sh <app> --restore [--dry-run|-n] [--force|-f]
./manage-app-language.sh --list-apps
./manage-app-language.sh --self-test
```

The runner handles:

- option parsing
- module contract self-tests
- global help
- app-specific help
- verbose supported-language output
- read-only mode when no language argument is provided
- dry-run mode
- running-application protection
- backup creation before writing, based on file paths reported by the module
- restore from `.bak` files for the same module-declared backup set
- generic status output

## Module Contract

Each module is sourced by the runner and must define `module_init` plus these functions:

- `module_primary_path`
- `module_ensure_storage_exists`
- `module_print_supported_languages`
- `module_backup_paths`
- `module_validate_backup_paths`
- `module_canonicalize_language`
- `module_is_running`
- `module_read_current_language`
- `module_write_language`

`module_primary_path` returns the canonical file path the runner should mention in diagnostics for that module.

`module_init` must also populate these variables:

- `module_key`
- `module_display_name`
- `module_storage_label`
- `module_example_language`
- `module_example_dry_run_language`
- optional `module_alias_help`

## Shared Control Flow

For a read:

1. parse options and select a module
2. ensure the module storage exists
3. ask the module to read the current language
4. print the current value

For a write:

1. parse options and select a module
2. ensure the module storage exists
3. read the current value when possible
4. canonicalize and validate the requested language through the module
5. block the write if the app appears to be running unless `--force` was provided
6. ask the module for the files that must be backed up
7. ask the module to validate that full backup set
8. create `.bak` copies of those files
9. ask the module to write the new value
10. print the old and new value and ask the user to restart the app

For a restore:

1. parse options and select a module
2. ask the module for the files that belong to its backup set
3. verify that the matching `.bak` files exist and are readable
4. block the restore if the app appears to be running unless `--force` was provided
5. in `--dry-run`, print the planned restore without copying files
6. copy each `.bak` file back over its original path
7. print the restored language when it can be detected and ask the user to restart the app

## Error Handling

The runner owns generic argument and flow errors, for example:

- unknown option
- unknown application
- missing application name
- multiple language arguments
- restore mode combined with a language argument
- read-only mode without a detectable current language
- running-application protection

Modules own application-specific errors, primary-path reporting, backup scope declarations, and backup-set validation, for example:

- missing storage file
- invalid or unsupported language identifiers
- malformed or missing app-specific data structures
- failed in-place rewrites

## Related Modules

- [steam-language-manager.md](steam-language-manager.md)
- [anki-language-manager.md](anki-language-manager.md)
- [factorio-language-manager.md](factorio-language-manager.md)
