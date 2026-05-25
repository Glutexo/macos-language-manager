# macos-language-manager

Simple shell tooling for macOS language management:

- managing the preferred macOS language order
- changing the Atlassian account language preference used by Jira and other Atlassian Cloud apps through Safari automation
- reading or reordering the preferred language list in a Google account through Safari automation
- managing the shared Safari browser-profile cache used by browser-automation modules
- managing application interface languages for Steam, Anki, Epic Games Launcher, Factorio, Wingspan, and Terraforming Mars

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
- The `google` module keeps its own browser-automation CLI and is not part of `all` or `everything`.
- The `atlassian` module keeps its own browser-automation CLI and is not part of `all` or `everything`.
- The `safari-profiles` module manages the shared Safari browser-profile cache and is not part of `all` or `everything`.
- The pseudo-module `all` runs the shared application-language flow across every simple application module.
- In `all` mode, a requested language may be applied only to the modules that support it; unsupported modules are skipped and left unchanged.
- The pseudo-module `everything` runs `all` and then `macos all` in one command.
- The `macos` module keeps its own target-based CLI under `./manage-languages.sh macos ...`, but it is still loaded through the same module lifecycle as the other modules.
- `macos`, `all`, and `everything` stay exclusive and cannot be combined with other module names.
- `--inherit-macos` uses the first tag from the current macOS `AppleLanguages` list and lets the selected module map it to its own language format.
- `--restore` restores the module's declared backup set from existing `.bak` files.
- `--self-test` verifies that every discovered module exposes the required shell hooks and metadata for CI or manual contract checks.
- Shell completion files are available in `completions/` for Bash and Zsh.

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

### `manage-languages.sh google`

Reads or reorders the preferred language list in the signed-in Google account through Safari automation.

Usage:

```bash
./manage-languages.sh google
./manage-languages.sh google --all-browser-profiles --dry-run "English"
./manage-languages.sh google --browser-profile work --browser-profile personal
./manage-languages.sh google --disable-auto-add
./manage-languages.sh google --enable-auto-add
./manage-languages.sh google --inherit-macos
./manage-languages.sh google --dry-run "English:Czech"
./manage-languages.sh google "English" "-Czech"
```

Notes:

- The command-line token syntax matches the macOS module: `xx`, `+xx`, `-xx`, `xx:yy`, and `xx:`.
- `--inherit-macos` replaces the Google Account language list with the full current macOS preferred language order.
- `--browser-profile NAME` can be repeated to target one or more browser profiles.
- `--all-browser-profiles` applies the same operation to every valid browser profile.
- Use `./manage-languages.sh safari-profiles` to inspect or refresh the shared Safari profile cache.
- `--disable-auto-add` turns off Google's `Automatically add languages` setting before writing, and it can be used on its own without language arguments.
- `--enable-auto-add` turns Google's `Automatically add languages` setting back on, and it can also be used on its own.
- Version 1 reorders, removes, or adds languages through Safari automation.
- Arguments are the visible labels from the Google Account page, not a separate ISO-tag mapping layer.
- If Google still shows a language as `Added for you`, the command warns about it after reading or writing.
- Safari may prompt for sign-in or 2-step verification.
- There is no public Google API in this repository for preferred-language ordering.

Technical details:

- [google-language-manager.md](docs/google-language-manager.md)

### `manage-languages.sh atlassian`

Reads or changes the Atlassian account language preference through Safari automation.

Usage:

```bash
./manage-languages.sh atlassian
./manage-languages.sh atlassian Czech
./manage-languages.sh atlassian "English (US)"
./manage-languages.sh atlassian --inherit-macos
./manage-languages.sh atlassian --browser-profile work Czech
./manage-languages.sh atlassian --all-browser-profiles --dry-run Japanese
```

Notes:

- This targets the Atlassian account preference that Jira and other Atlassian Cloud apps inherit for the signed-in account.
- The module uses Safari automation because the locally available `acli` does not expose an account-language command.
- `--inherit-macos` maps the first current macOS `AppleLanguages` tag to a supported Atlassian account language.
- `--browser-profile NAME` can be repeated to target one or more browser profiles.
- `--all-browser-profiles` applies the same operation to every valid browser profile.
- Use `./manage-languages.sh safari-profiles` to inspect or refresh the shared Safari profile cache.
- Safari may prompt for sign-in or additional verification.

Technical details:

- [atlassian-language-manager.md](docs/atlassian-language-manager.md)

### `manage-languages.sh safari-profiles`

Inspects or refreshes the shared Safari browser-profile cache used by browser-automation modules.

Usage:

```bash
./manage-languages.sh safari-profiles
./manage-languages.sh safari-profiles --refresh
./manage-languages.sh safari-profiles --clear-cache
./manage-languages.sh safari-profiles --list-cache
./manage-languages.sh safari-profiles --list-effective
./manage-languages.sh safari-profiles --show-cache-path
```

Notes:

- The module does not change languages.
- `--refresh` updates the shared Safari profile cache through Safari UI automation.
- `--clear-cache` removes the stored cache file.
- `--list-cache` prints only cached names.
- `--list-effective` prints the current effective names using cache first, then local Safari data, then `default`.

Technical details:

- [safari-profiles-manager.md](docs/safari-profiles-manager.md)

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

### Shell Completion

Installer:

```bash
./install-manage-languages-completion.sh
```

The installer does two things:

- links the completion file into a per-shell completion directory
- adds one loader block to the shell rc file that sources every completion from that directory

Default completion directories:

- Zsh → `~/.config/zsh/completions`
- Bash → `~/.config/bash/completions`

Explicit shell selection:

```bash
./install-manage-languages-completion.sh --shell zsh
./install-manage-languages-completion.sh --shell bash
```

Bash:

```bash
source ./completions/manage-languages.bash
```

Zsh:

```zsh
source ./completions/manage-languages.zsh
```

Both completion files register completions for `manage-languages` and `./manage-languages.sh`.

### Application Technical Details

- [steam-language-manager.md](docs/steam-language-manager.md)
- [anki-language-manager.md](docs/anki-language-manager.md)
- [epic-games-launcher-language-manager.md](docs/epic-games-launcher-language-manager.md)
- [factorio-language-manager.md](docs/factorio-language-manager.md)
- [wingspan-language-manager.md](docs/wingspan-language-manager.md)
- [terraforming-mars-language-manager.md](docs/terraforming-mars-language-manager.md)
- [google-language-manager.md](docs/google-language-manager.md)
- [atlassian-language-manager.md](docs/atlassian-language-manager.md)
- [safari-profiles-manager.md](docs/safari-profiles-manager.md)

## Tests

- `./tests/test-manage-languages.sh`
- `./tests/test-manage-languages-macos.sh`
- `./tests/test-manage-languages-completion.sh`
- `./tests/test-install-manage-languages-completion.sh`

## Repository Workflow

- Use `gh` for GitHub-related work when appropriate.
- Keep project-specific rules in English.
- Commit and push after every change.

## License

MIT. See the `LICENSE.txt` file.
