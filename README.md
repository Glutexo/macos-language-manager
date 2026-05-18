# macos-language-manager

Simple shell tooling for macOS language management:

- managing the preferred macOS language order
- managing application interface languages for Steam, Anki, Factorio, Wingspan, and Terraforming Mars

## Scripts

### `manage-languages.sh`

Reads or changes macOS and application languages via dynamically loaded modules.

Usage:

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
```

Notes:

- The script discovers modules from `language-modules/`.
- You can target multiple application modules in one run, for example `./manage-languages.sh steam anki ja`.
- The pseudo-module `all` runs the shared application-language flow across every simple application module.
- The pseudo-module `everything` runs `all` and then `macos all` in one command.
- The `macos` module keeps its own target-based CLI under `./manage-languages.sh macos ...`, but it is still loaded through the same module lifecycle as the other modules.
- `macos`, `all`, and `everything` stay exclusive and cannot be combined with other module names.
- `--inherit-macos` uses the first tag from the current macOS `AppleLanguages` list and lets the selected module map it to its own language format.
- `--restore` restores the module's declared backup set from existing `.bak` files.
- `--self-test` verifies that every discovered module exposes the required shell hooks and metadata for CI or manual contract checks.

Technical details:

- [languages-manager.md](docs/languages-manager.md)

### `manage-languages.sh macos`

Changes macOS language-related settings for the current account, login window, locale, startup language, or all of them together.

Usage:

```bash
./manage-languages.sh macos account [--dry-run|-n] [--restart|-r] [language ...]
./manage-languages.sh macos login-window [--dry-run|-n] [--restart|-r] [language ...]
./manage-languages.sh macos locale [--dry-run|-n] [--restart|-r] [language ...]
./manage-languages.sh macos startup [--dry-run|-n] [--restart|-r] [language ...]
./manage-languages.sh macos all [--dry-run|-n] [--restart|-r] [language ...]
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
- [wingspan-language-manager.md](docs/wingspan-language-manager.md)
- [terraforming-mars-language-manager.md](docs/terraforming-mars-language-manager.md)

## Tests

- `./tests/test-manage-languages.sh`
- `./tests/test-manage-languages-macos.sh`

## Repository Workflow

- Use `gh` for GitHub-related work when appropriate.
- Keep project-specific rules in English.
- Commit and push after every change.

## License

MIT. See the `LICENSE.txt` file.
