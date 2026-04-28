# macos-language-manager

Simple shell tooling for two separate tasks on macOS:

- managing the preferred macOS language order
- managing the Steam interface language

## Scripts

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

### `manage-steam-language.sh`

Reads or changes the Steam client interface language on macOS.

Usage:

```bash
./manage-steam-language.sh [--dry-run|-n] [--force|-f] [language]
```

Technical details:

- [steam-language-manager.md](docs/steam-language-manager.md)

## Tests

- `./tests/test-manage-macos-languages.sh`
- `./tests/test-manage-steam-language.sh`

## Repository Workflow

- Use `gh` for GitHub-related work when appropriate.
- Keep project-specific rules in English.
- Commit and push after every change.

## License

MIT. See the `LICENSE` file.
