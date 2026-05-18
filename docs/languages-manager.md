# Languages Manager Technical Notes

This document describes the shared architecture behind `manage-languages.sh` and the dynamically loaded application modules in `language-modules/`.

## Scope

The runner manages application interface languages for supported macOS applications and loads the macOS target-based workflow through the same module lifecycle as the application modules.
It also supports external modules whose implementation lives behind a module-specific CLI, such as `macos` and `google-account`.

## Entry Points

Primary runner:

```text
./manage-languages.sh
```

## Module Discovery

The runner loads modules from:

```text
./language-modules
```

Each `*.sh` file in that directory becomes one available module id, except helper files that are not meant for direct discovery.

Examples:

- `all` → pseudo-module that runs the selected operation for every simple application module
- `language-modules/steam.sh` → `steam`
- `language-modules/anki.sh` → `anki`
- `language-modules/factorio.sh` → `factorio`
- `language-modules/wingspan.sh` → `wingspan`
- `language-modules/terraforming-mars.sh` → `terraforming-mars`
- `language-modules/macos.sh` → `macos`
- `language-modules/google-account.sh` → `google-account`

`--list-apps` and `--list-modules` print the discovered ids.

`--self-test` loads each discovered module and verifies that the required shell functions and metadata are present.

## Command-Line Interface

Unified usage:

```bash
./manage-languages.sh <module> [<module> ...] [--dry-run|-n] [--force|-f] [language]
./manage-languages.sh <module> [<module> ...] --inherit-macos [--dry-run|-n] [--force|-f]
./manage-languages.sh <module> [<module> ...] --restore [--dry-run|-n] [--force|-f]
./manage-languages.sh all [--dry-run|-n] [--force|-f] [language]
./manage-languages.sh all --inherit-macos [--dry-run|-n] [--force|-f]
./manage-languages.sh all --restore [--dry-run|-n] [--force|-f]
./manage-languages.sh everything [--dry-run|-n] [language ...]
./manage-languages.sh --list-apps|--list-modules
./manage-languages.sh --self-test
./manage-languages.sh macos ...
```

The runner handles:

- option parsing
- module contract self-tests
- global help
- module-specific help
- verbose supported-language output
- read-only mode when no language argument is provided
- dry-run mode
- inheriting the current macOS preferred language through `AppleLanguages`
- running-application protection
- backup creation before writing, based on file paths reported by the module
- restore from `.bak` files for the same module-declared backup set
- generic status output
- shared ordered-language token parsing is implemented once in `language-modules/ordered-language-list-helper.sh` and reused by modules that manage ordered language lists

## Module Contract

Each module is sourced by the runner and must define:

- `module_init`
- `module_parse_arguments`
- `module_show_usage`
- `module_run`

Modules that use the shared application-language flow must also define:

- `module_primary_path`
- `module_ensure_storage_exists`
- `module_print_supported_languages`
- `module_print_aliases`
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
- optional `module_supports_bulk`
- optional `module_flow_kind`

## Shared Control Flow

For a read:

1. parse options and select a module
2. ensure the module storage exists
3. ask the module to read the current language
4. print the current value

For `all`:

1. discover all simple application modules
2. run the selected read, write, inherit, or restore flow for each module in order
3. when `all` is changing a language, unsupported target languages are skipped per module and those modules remain unchanged
4. stop on the first remaining module error

For `everything`:

1. run the existing application pseudo-module flow: `all`
2. then run the existing macOS command flow: `macos all`
3. pass the same argument vector to both flows
4. stop on the first error

For an explicit multi-module selection such as `steam anki ja`:

1. collect the consecutive module names at the beginning of the command line
2. treat the remaining arguments as one shared argument vector
3. run the same parsed operation for each selected module in the order requested
4. stop on the first module error

For every module:

1. parse global options until the module name is known
2. pass the remaining module argument vector into `module_parse_arguments`
3. show usage through `module_show_usage` when the module requests help
4. execute the selected operation through `module_run`

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

For macOS inheritance:

1. read the first tag from the current macOS `AppleLanguages` list
2. pass that tag through the selected module's canonicalization logic
3. continue through the normal write flow with the module-specific target value

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
- unknown module
- invalid combination of the exclusive pseudo-modules `all` or `everything` with other module names
- invalid combination of exclusive modules such as `all` or `macos` with other module names
- missing module name
- multiple language arguments
- inherit mode combined with a language argument
- restore mode combined with inherit mode
- restore mode combined with a language argument
- read-only mode without a detectable current language
- running-application protection

Modules own application-specific errors, and shared-flow modules additionally own primary-path reporting, backup scope declarations, and backup-set validation, for example:

- missing storage file
- invalid or unsupported language identifiers
- malformed or missing app-specific data structures
- failed in-place rewrites

## Related Modules

- [macos-language-manager.md](macos-language-manager.md)
- [steam-language-manager.md](steam-language-manager.md)
- [anki-language-manager.md](anki-language-manager.md)
- [factorio-language-manager.md](factorio-language-manager.md)
- [wingspan-language-manager.md](wingspan-language-manager.md)
- [terraforming-mars-language-manager.md](terraforming-mars-language-manager.md)
- [google-account-language-manager.md](google-account-language-manager.md)
