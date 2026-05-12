# macos-language-manager

Simple shell tooling for macOS language management:

- managing the preferred macOS language order
- managing application interface languages for Steam, Anki, and Factorio

## Scripts

### `manage-app-language.sh`

Reads or changes the interface language for supported macOS applications via dynamically loaded modules.

Usage:

```bash
./manage-app-language.sh <app> [--dry-run|-n] [--force|-f] [language]
./manage-app-language.sh <app> --restore [--dry-run|-n] [--force|-f]
./manage-app-language.sh --list-apps
./manage-app-language.sh --self-test
```

Notes:

- The script discovers application modules from `language-modules/`.
- `--restore` restores the module's declared backup set from existing `.bak` files.
- `--self-test` verifies that every discovered module exposes the required shell hooks and metadata for CI or manual contract checks.

Technical details:

- [app-language-manager.md](docs/app-language-manager.md)

### `manage-macos-languages.sh`

Changes macOS language-related settings for the current account, login window, locale, startup language, or all of them together.

Usage:

```bash
./manage-macos-languages.sh account [--dry-run|-n] [--restart|-r] [language ...]
./manage-macos-languages.sh login-window [--dry-run|-n] [--restart|-r] [language ...]
./manage-macos-languages.sh locale [--dry-run|-n] [--restart|-r] [language ...]
./manage-macos-languages.sh startup [--dry-run|-n] [--restart|-r] [language ...]
./manage-macos-languages.sh all [--dry-run|-n] [--restart|-r] [language ...]
```

Common token examples:

| Token | Meaning |
| --- | --- |
| `ja` or `+ja` | Move or add Japanese at the front |
| `ja:cs` or `+ja:cs` | Move or add Japanese immediately before Czech |
| `ja:` or `+ja:` | Move or add Japanese at the end |
| `-ja` | Remove matching Japanese entries after ordering |
| `+-ja` | Invalid |
| `ja:-cs` | Invalid |
| `ja:+cs` | Invalid |

Technical details:

- [macos-language-manager.md](docs/macos-language-manager.md)

Verbose supported-language help uses Apple's renderable UI language list from `IntlPreferences.framework`.

### `extract-system-settings-languages.swift`

Extracts the preferred language list and the full addable-language list from System Settings > Language & Region via Accessibility.

Usage:

```bash
./extract-system-settings-languages.swift
./extract-system-settings-languages.swift --json
```

Notes:

- Requires Accessibility permission for the terminal or app that runs it.
- The addable-language list comes from the `+` dialog in System Settings.
- Preferred languages are read only from the visible System Settings UI.

Technical details:

- [extract-system-settings-languages.md](docs/extract-system-settings-languages.md)

### Application Technical Details

- [steam-language-manager.md](docs/steam-language-manager.md)
- [anki-language-manager.md](docs/anki-language-manager.md)
- [factorio-language-manager.md](docs/factorio-language-manager.md)

## Tests

- `./tests/test-manage-macos-languages.sh`
- `./tests/test-manage-app-language.sh`

## Repository Workflow

- Use `gh` for GitHub-related work when appropriate.
- Keep project-specific rules in English.
- Commit and push after every change.

## License

MIT. See the `LICENSE.txt` file.
