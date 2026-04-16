# macos-language-manager

Simple shell tooling for managing the preferred language order on macOS.

## Overview

This repository currently provides one script:

- `manage-macos-languages.sh` reads the current `AppleLanguages` setting.
- It moves the requested languages to the front of the list.
- It adds a requested language if it is not already present.
- It uses the system locale region for missing base language tags such as `ja` -> `ja-CZ`.
- It keeps the remaining languages in their original order.
- It can preview the result with `--dry-run` or `-n` before writing changes.
- It can restart the Mac with `--restart` or `-r`, even when used together with `--dry-run`.

The script is useful when you want to quickly change language priority for apps and system components that follow the global macOS language preference order.

## Requirements

- macOS
- `bash`
- The built-in `defaults` command

## Usage

```bash
./manage-macos-languages.sh [--dry-run|-n] [--restart|-r] language [language...]
```

```bash
./manage-macos-languages.sh
```

Manages the macOS preferred language list by moving selected languages to the front and adding missing ones when needed.

Options:

- `--dry-run`, `-n`: prints the resulting language order without writing `AppleLanguages`
- `--restart`, `-r`: requests an immediate restart after evaluating the command
- `--help`, `-h`: prints the built-in help output

Examples:

```bash
./manage-macos-languages.sh
```

Prints the current macOS language order without making changes.

```bash
./manage-macos-languages.sh cs en
```

Moves Czech and English to the front of the current macOS language list.

```bash
./manage-macos-languages.sh --dry-run ko ja
```

Shows the reordered list for Korean and Japanese without saving it. If `ja` is missing and the system locale is `cs_CZ`, the inserted value becomes `ja-CZ`.

```bash
./manage-macos-languages.sh -n ko ja
```

Short form of `--dry-run`.

```bash
./manage-macos-languages.sh en-US de
```

Prioritizes `en-US` and German, then keeps the rest of the configured languages in their previous order.

```bash
./manage-macos-languages.sh fr cs
```

Moves French and Czech to the front and adds either language if it is missing from the current macOS list.

```bash
./manage-macos-languages.sh --restart ja ko
```

Requests a system restart after calculating the new order.

```bash
./manage-macos-languages.sh ja ko -r
```

Short form of `--restart`.

## How Matching Works

- An exact language tag such as `en-US` matches the same tag first.
- A base language such as `en` can match region-specific variants such as `en-US`.
- If you request a language that is not already in the list, the script adds it.
- For short tags such as `ja`, it also appends the current system locale region when available.
- Example: if the system locale is `cs_CZ`, requesting `ja` inserts `ja-CZ`.
- If no configured language matches a fully qualified tag such as `en-US`, that exact tag is inserted.
- Only the first matching configured language is moved for each requested item.
- Languages not requested stay in the list and preserve their relative order.

## Notes

- The script prints its status messages in English.
- macOS may require logging out and back in before the change is fully reflected everywhere.
- Use `--restart` or `-r` if you want the script to request an immediate restart, including together with `--dry-run`.
- Test with `--dry-run` or `-n` first if you want to confirm the final order.

## Repository Workflow

- Use `gh` for GitHub-related work when appropriate.
- Keep project-specific rules in English.
- Commit and push after every change.

## License

MIT. See the `LICENSE` file.
