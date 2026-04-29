# System Settings Language Extractor Technical Notes

This document describes what `extract-system-settings-languages.swift` reads from macOS, where its language codes come from, and how name-to-code matching works.

## Scope

The script extracts two lists from System Settings → Language & Region:

- `preferred`
- `available`

It does not change any system settings.

## What The Script Reads

### Preferred languages

Source:

- the visible preferred-languages outline inside System Settings

Method:

- uses the macOS Accessibility API
- walks the `AXOutline` rows in the Language & Region pane
- collects visible `AXStaticText` content from each row

Important detail:

- these entries come only from the visible UI
- the script does not get hidden locale codes from the Accessibility tree because System Settings does not expose them there

### Addable languages

Source:

- the `+` add-language sheet inside System Settings

Method:

- opens the add-language dialog through Accessibility
- finds the `AXTable` in the sheet
- reads visible `AXStaticText` content from each row

## Where Language Codes Come From

The UI rows do not expose language codes directly, so the script resolves them from Apple and Foundation language data.

It builds a lookup table from three sources, in this order:

1. `Locale.availableIdentifiers`
2. `Locale.LanguageCode.isoLanguageCodes`
3. `/System/Library/PrivateFrameworks/IntlPreferences.framework/Resources/RenderableUILanguages.plist`

Why all three are needed:

- `Locale.availableIdentifiers` covers most locale and region variants such as `en-GB`, `es-US`, or `zh-Hant-HK`
- `Locale.LanguageCode.isoLanguageCodes` adds base language codes that are known to Foundation but not present as full locale identifiers, such as `ab`
- `RenderableUILanguages.plist` adds Apple-renderable UI language codes that may be missing from the Foundation language-code list, such as `lou`

## How Name Matching Works

For every candidate code, the script collects names from Foundation with:

- `Locale(identifier: code).localizedString(forIdentifier: ...)`
- `Locale.current.localizedString(forIdentifier: ...)`
- `Locale(identifier: code).localizedString(forLanguageCode: ...)`
- `Locale.current.localizedString(forLanguageCode: ...)`

The resulting names are normalized before matching:

- case-insensitive
- diacritic-insensitive
- width-insensitive
- non-breaking spaces normalized to plain spaces
- selected UI aliases normalized, for example `UK` → `United Kingdom`

The script then matches the extracted row against:

1. the primary visible language name
2. the secondary visible localized language name
3. a generalized fallback without a parenthesized variant label

Example:

- `Билин (эфиопская)` falls back to `Билин` and resolves to `byn`

## Resolution Priority

If a row includes an explicit variant, the script prefers a more specific code:

- `English (UK)` → `en-GB`
- `繁體中文（香港）` → `zh-Hant-HK`

If a row is a base language name, the script prefers the base code:

- `Русский` → `ru`
- `Čeština` → `cs`

## Verification

A complete verification run can be done with:

```bash
./extract-system-settings-languages.swift --json
```

To list unresolved rows:

```bash
./extract-system-settings-languages.swift --json | jq '[.preferred[], .available[]] | map(select((.code // "") == ""))'
```
