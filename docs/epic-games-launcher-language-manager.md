# Epic Games Launcher Language Manager Technical Notes

This document describes how the Epic Games Launcher module behind `manage-languages.sh` reads and writes the Epic Games Launcher interface language on macOS, including the native `Use system setting` mode.

## Scope

The module manages the Epic Games Launcher interface language on macOS.

It does not modify macOS `AppleLanguages`, `AppleLocale`, or NVRAM settings.

## Storage Location

Default preferences directory:

```text
$HOME/Library/Preferences/Unreal Engine/EpicGamesLauncher
```

Preferences file:

```text
$HOME/Library/Preferences/Unreal Engine/EpicGamesLauncher/Mac/GameUserSettings.ini
```

Override:

- `EPIC_GAMES_LAUNCHER_PREFERENCES_DIR` can point to a different Epic Games Launcher preferences directory.
- The script then reads `Mac/GameUserSettings.ini` under that directory.

## What The Script Reads

### Preferences file existence

Unlike the other simple application modules, the Epic Games Launcher module does not require `GameUserSettings.ini` to exist before a read.

Reason:

- Epic's native `Use system setting` mode can exist without any launcher-specific language override file.
- When the file is absent, the module treats the current launcher language as `system`.

### Current language value

If the preferences file exists, the script reads the `[Internationalization]` section and looks for:

```text
Culture=VALUE
```

Behavior:

- if `Culture` exists and has a value, the module reports that value
- if the section exists but `Culture` is missing, the module reports `system`
- if the file is missing, the module reports `system`

The module does not currently depend on any other Epic settings sections.

## File Format

The launcher stores user settings in a UE-style INI file.

Minimal system-mode example:

```text
[Internationalization]
```

Explicit language example:

```text
[Internationalization]
Culture=cs
```

Important characteristics:

- it is a plain text INI file
- the module only edits the `[Internationalization]` section
- the module removes explicit `Culture=` and `Language=` keys when switching back to `system`

## Supported Language Values

The module uses a hardcoded allowlist that mirrors the currently shipped Epic Games Launcher localization resources found in the installed macOS app bundle under:

```text
/Applications/Epic Games Launcher.app/Contents/UE/EpicGamesLauncher/Content/Localization/App
```

Supported values:

- `system`
- `ar`
- `bg`
- `cs`
- `da`
- `de`
- `el`
- `en`
- `es`
- `es-ES`
- `es-MX`
- `fi`
- `fil`
- `fr`
- `hi`
- `hu`
- `id`
- `it`
- `ja`
- `ko`
- `ms`
- `nl`
- `no`
- `pl`
- `pt`
- `pt-BR`
- `ro`
- `ru`
- `sv`
- `th`
- `tr`
- `uk`
- `vi`
- `zh-CN`
- `zh-Hans`
- `zh-Hant`

Accepted aliases include:

- `default`, `os`, `use-system` → `system`
- `en-US`, `en-GB` → `en`
- `es-419`, `es-LATAM` → `es-MX`
- `nb` → `no`
- `pt-PT` → `pt`
- `zh` → `zh-Hans`
- `zh-TW`, `zh-HK` → `zh-Hant`

Primary-language fallbacks are also supported during macOS inheritance, for example:

- `ja-CZ` → `ja`
- `de-AT` → `de`
- `pt-AO` → `pt`

## What The Script Writes

When changing the language, the script does this:

1. ensures the `Mac` preferences directory exists
2. creates a minimal `GameUserSettings.ini` only when a write needs one
3. copies `GameUserSettings.ini` to `GameUserSettings.ini.bak`
4. updates only the `[Internationalization]` section
5. prints the old and new value
6. asks the user to restart Epic Games Launcher

Backup file:

```text
GameUserSettings.ini.bak
```

## Native `Use system setting` Mode

The module exposes Epic's native launcher mode as the synthetic language value:

```text
system
```

Behavior:

- reading `system` means the launcher has no explicit language override
- writing `system` removes the explicit `Culture=` override from `[Internationalization]`
- `--inherit-macos` is different: it resolves the current macOS preferred language to one explicit Epic language value and writes that explicit value

That distinction matters because Epic's native system-following mode continues to follow later macOS changes, while `--inherit-macos` is a point-in-time copy.

## Running-App Detection

The module checks whether the main Epic Games Launcher process appears to be running by looking for:

```text
/Applications/Epic Games Launcher.app/Contents/MacOS/EpicGamesLauncher-Mac-Shipping
```

Default behavior:

- if the launcher is running and `--force` is not used, the script aborts without modifying the file

With `--force`:

- the write proceeds even if the launcher appears to be running

Override:

- `EPIC_GAMES_LAUNCHER_PROCESS_MATCH` can replace the default process-match string used by the running-app check

## Read-Only Mode

If no language argument is provided:

- the script prints the current Epic Games Launcher interface language
- it reports `system` when there is no explicit override file or no `Culture=` key
- no file is modified

## Dry Run Behavior

With `--dry-run`:

- the script validates and canonicalizes the requested language
- it prints the planned change
- it does not write `GameUserSettings.ini`
- it does not create the backup file

## Verbose Help Source

Unlike the macOS script, Epic Games Launcher language values do not come from the system.

They come from the in-script supported-language array, which mirrors the launcher resources shipped in the installed macOS app bundle.

`--verbose` prints that array together with the accepted aliases, including the synthetic `system` mode.

## Environment Variables Used For Testing Or Overrides

- `EPIC_GAMES_LAUNCHER_PREFERENCES_DIR` → override the Epic Games Launcher preferences directory
- `EPIC_GAMES_LAUNCHER_PROCESS_MATCH` → override the process-match string used by the running-app check

## Related Tests

- `./tests/test-manage-languages.sh`
