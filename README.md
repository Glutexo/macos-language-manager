# macos-language-manager

Simple shell tooling for managing the preferred language order on macOS.

## Overview

This repository currently provides one script:

- `manage-macos-languages.sh` reads the current `AppleLanguages` setting.
- It moves the requested languages to the front of the list.
- It adds a requested language if it is not already present.
- It removes requested languages from the list when prefixed with `-`.
- It accepts optional `+` prefixes for move/add operations.
- It uses the system locale region for missing base language tags such as `ja` -> `ja-CZ`.
- It keeps the remaining languages in their original order.
- It can preview the result with `--dry-run` or `-n` before writing changes.
- It can target `account`, `login-window`, `locale`, `startup`, or `all` via the first argument.
- It can restart the Mac with `--restart` or `-r`, even when used together with `--dry-run`.

The script is useful when you want to quickly change language priority for apps and system components that follow the global macOS language preference order.

## Requirements

- macOS
- `bash`
- The built-in `defaults` command
- `sudo` access for `login-window` and `all`

## Usage

```bash
./manage-macos-languages.sh account [--dry-run|-n] [--restart|-r] [language ...]
```

```bash
./manage-macos-languages.sh login-window [--dry-run|-n] [--restart|-r] [language ...]
```

```bash
./manage-macos-languages.sh locale [--dry-run|-n] [--restart|-r] [language ...]
```

```bash
./manage-macos-languages.sh startup [--dry-run|-n] [--restart|-r] [language ...]
```

```bash
./manage-macos-languages.sh all [--dry-run|-n] [--restart|-r] [language ...]
```

Manages the macOS preferred language list by moving selected languages to the front, adding missing ones when needed, and removing matching entries when requested.

## Targets

- `account`: reads or writes the current account language order
- `login-window`: reads or writes the login window language order
- `locale`: reads or writes locale settings derived from the first added language
- `startup`: reads or writes startup NVRAM language settings
- `all`: reads or writes account, login window, locale, and startup NVRAM settings together, using a merged language list from all relevant sources

## Options

- `--dry-run`, `-n`: prints the resulting values without writing changes
- `--restart`, `-r`: requests an immediate restart after evaluating the command
- `--help`, `-h`: prints the built-in help output

## Language Argument Syntax

- `xx`: move the language to the front or add it if missing
- `+xx`: same as `xx`; explicit move/add syntax
- `-xx`: remove matching language entries from the list

For `locale`, `startup`, and `all`, the locale/startup value is derived from the first added language argument. A command that only removes languages is therefore rejected for those targets.

## Examples

```bash
./manage-macos-languages.sh account
```

Prints the current account language order without making changes.

```bash
./manage-macos-languages.sh login-window
```

Prints the current login window language order.

```bash
./manage-macos-languages.sh locale
```

Prints the current account and system locale values.

```bash
./manage-macos-languages.sh startup
```

Prints the current startup NVRAM language setting.

```bash
./manage-macos-languages.sh all
```

Prints a merged language list from account languages, login window languages, locale-derived languages, and startup NVRAM language, followed by the individual source values.

```bash
./manage-macos-languages.sh account cs en
```

Moves Czech and English to the front of the current account language list.

```bash
./manage-macos-languages.sh account --dry-run +ko ja -en
```

Shows the reordered language list without saving it, explicitly adds or moves Korean and Japanese, and removes matching English entries.

```bash
./manage-macos-languages.sh login-window de ko
```

Writes the new language order only to the login window and refreshes APFS preboot data. This may prompt for administrator privileges.

```bash
./manage-macos-languages.sh locale ja
```

Sets account and system `AppleLocale` to `ja_CZ` if the available region is `CZ`.

```bash
./manage-macos-languages.sh startup ja
```

Sets NVRAM `prev-lang:kbd` to the requested startup language while preserving the current keyboard layout ID when available.

```bash
./manage-macos-languages.sh all ja ko -en
```

Writes account languages, login window languages, account locale, system locale, and startup NVRAM language in one command, starting from the merged language list of all relevant sources while also removing matching English entries.

```bash
./manage-macos-languages.sh account --restart ja ko
```

Requests a system restart after calculating the new order.

## How Matching Works

- An exact language tag such as `en-US` matches the same tag first.
- A base language such as `en` can match region-specific variants such as `en-US`.
- If you request a language that is not already in the list, the script adds it.
- For short tags such as `ja`, it also appends the current system locale region when available.
- Example: if the current locale is `cs_CZ`, requesting `ja` inserts `ja-CZ`.
- If no configured language matches a fully qualified tag such as `en-US`, that exact tag is inserted.
- Only the first matching configured language is moved for each added item.
- A removed base language such as `-en` removes matching region-specific variants such as `en-US`.
- Languages not removed stay in the list and preserve their relative order.

## Locale Behavior

- The `locale` and `all` targets derive `AppleLocale` from the first added language.
- Hyphens are converted to underscores, so `ja-CZ` becomes `ja_CZ`.
- This intentionally changes locale formatting behavior too.

## Notes

- The script prints its status messages in English.
- `login-window` and `all` update the system-wide language list and run `diskutil apfs updatePreboot /` to help FileVault and preboot screens pick up the change.
- `locale` and `all` update both the current account locale and the system locale.
- `startup` and `all` update NVRAM `prev-lang:kbd`, which appears to influence the startup / FileVault language on this Mac.
- `all` merges languages from account `AppleLanguages`, login window `AppleLanguages`, locale-derived language tags, and the startup NVRAM language before building the new order.
- The script suppresses noisy `updatePreboot` output and only prints it if the refresh actually fails.
- Use `--restart` or `-r` if you want the script to request an immediate restart, including together with `--dry-run`.
- Test with `--dry-run` or `-n` first if you want to confirm the final values.

## Repository Workflow

- Use `gh` for GitHub-related work when appropriate.
- Keep project-specific rules in English.
- Commit and push after every change.

## License

MIT. See the `LICENSE` file.
