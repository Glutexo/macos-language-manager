#!/usr/bin/env swift
import ApplicationServices
import AppKit
import Foundation

enum ToolError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

struct LanguageEntry: Hashable, Encodable {
    let code: String?
    let primary: String
    let secondary: String
}

struct Output: Encodable {
    let preferred: [LanguageEntry]
    let available: [LanguageEntry]
}

struct LanguageCodeCandidate {
    let code: String
    let specificity: Int
}

let args = Array(CommandLine.arguments.dropFirst())
let wantsJSON = args.contains("--json")
if args.contains("--help") || args.contains("-h") {
    print("Extracts preferred and addable languages from System Settings > Language & Region.")
    print("")
    print("Usage: ./extract-system-settings-languages.swift [--json]")
    print("")
    print("Options:")
    print("  --json   Print machine-readable JSON output.")
    print("  --help   Show this help message.")
    exit(0)
}

func shell(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw ToolError.message("Command failed: \(launchPath) \(arguments.joined(separator: " "))")
    }
}

func attr<T>(_ element: AXUIElement, _ key: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
        return nil
    }
    return value as? T
}

func setAttr(_ element: AXUIElement, _ key: String, _ value: CFTypeRef) -> Bool {
    AXUIElementSetAttributeValue(element, key as CFString, value) == .success
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attr(element, kAXChildrenAttribute as String) ?? []
}

func child(_ element: AXUIElement, _ index: Int) -> AXUIElement? {
    let values = children(of: element)
    guard index >= 0 && index < values.count else { return nil }
    return values[index]
}

func role(of element: AXUIElement) -> String {
    attr(element, kAXRoleAttribute as String) ?? ""
}

func title(of element: AXUIElement) -> String {
    if let title: String = attr(element, kAXTitleAttribute as String), !title.isEmpty {
        return title
    }
    if let value: String = attr(element, kAXValueAttribute as String), !value.isEmpty {
        return value
    }
    return ""
}

func collectStaticTexts(from element: AXUIElement) -> [String] {
    var result: [String] = []
    if role(of: element) == kAXStaticTextRole as String {
        let value = title(of: element)
        if !value.isEmpty {
            result.append(value)
        }
    }
    for kid in children(of: element) {
        result.append(contentsOf: collectStaticTexts(from: kid))
    }
    return result
}

func firstDescendant(of element: AXUIElement, where predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    if predicate(element) {
        return element
    }
    for kid in children(of: element) {
        if let found = firstDescendant(of: kid, where: predicate) {
            return found
        }
    }
    return nil
}

func descendants(of element: AXUIElement, where predicate: (AXUIElement) -> Bool) -> [AXUIElement] {
    var result: [AXUIElement] = []
    if predicate(element) {
        result.append(element)
    }
    for kid in children(of: element) {
        result.append(contentsOf: descendants(of: kid, where: predicate))
    }
    return result
}

func normalizeLanguageName(_ value: String) -> String {
    let normalized = value
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let aliases = [
        "(uk)": "(united kingdom)",
        "(ee. uu.)": "(estados unidos)",
        "(британия)": "(великобритания)"
    ]

    return aliases.reduce(normalized) { partial, alias in
        partial.replacingOccurrences(of: alias.key, with: alias.value)
    }
}

func sentenceCase(_ value: String, locale: Locale) -> String {
    guard let first = value.first else {
        return value
    }
    return String(first).uppercased(with: locale) + value.dropFirst()
}

func uniquePreferred<T>(_ values: [T?]) -> [T] {
    var seen: Set<String> = []
    var result: [T] = []

    for value in values {
        guard let value else { continue }
        let key = String(describing: value)
        if seen.insert(key).inserted {
            result.append(value)
        }
    }
    return result
}

func buildLanguageCodeLookup() -> [String: [LanguageCodeCandidate]] {
    var lookup: [String: [LanguageCodeCandidate]] = [:]
    let userLocale = Locale.current

    func register(name: String?, code: String, specificity: Int) {
        guard let name else { return }
        let normalized = normalizeLanguageName(name)
        guard !normalized.isEmpty else { return }
        let candidate = LanguageCodeCandidate(code: code, specificity: specificity)
        var candidates = lookup[normalized] ?? []
        if !candidates.contains(where: { $0.code == code }) {
            candidates.append(candidate)
            lookup[normalized] = candidates
        }
    }

    for rawIdentifier in Locale.availableIdentifiers {
        let components = NSLocale.components(fromLocaleIdentifier: rawIdentifier)
        guard let languageCode = components[NSLocale.Key.languageCode.rawValue], !languageCode.isEmpty else {
            continue
        }

        let scriptCode = components[NSLocale.Key.scriptCode.rawValue]
        let countryCode = components[NSLocale.Key.countryCode.rawValue]

        let codeParts = [languageCode, scriptCode, countryCode].compactMap { $0 }.filter { !$0.isEmpty }
        let canonicalCode = codeParts.joined(separator: "-")
        guard !canonicalCode.isEmpty else { continue }
        let specificity = codeParts.count - 1

        let locale = Locale(identifier: rawIdentifier)
        let candidateNames = uniquePreferred([
            locale.localizedString(forIdentifier: rawIdentifier),
            locale.localizedString(forIdentifier: canonicalCode),
            locale.localizedString(forIdentifier: rawIdentifier.replacingOccurrences(of: "_", with: "-")),
            userLocale.localizedString(forIdentifier: rawIdentifier),
            userLocale.localizedString(forIdentifier: canonicalCode),
            userLocale.localizedString(forIdentifier: rawIdentifier.replacingOccurrences(of: "_", with: "-")),
            locale.localizedString(forLanguageCode: languageCode),
            userLocale.localizedString(forLanguageCode: languageCode)
        ])

        for candidate in candidateNames {
            register(name: candidate, code: canonicalCode, specificity: specificity)
            register(name: sentenceCase(candidate, locale: locale), code: canonicalCode, specificity: specificity)
            register(name: sentenceCase(candidate, locale: userLocale), code: canonicalCode, specificity: specificity)
        }

        if specificity == 0 {
            let languageNames = uniquePreferred([
                locale.localizedString(forLanguageCode: languageCode),
                userLocale.localizedString(forLanguageCode: languageCode)
            ])

            for candidate in languageNames {
                register(name: candidate, code: canonicalCode, specificity: specificity)
                register(name: sentenceCase(candidate, locale: locale), code: canonicalCode, specificity: specificity)
                register(name: sentenceCase(candidate, locale: userLocale), code: canonicalCode, specificity: specificity)
            }
        }
    }

    for language in Locale.LanguageCode.isoLanguageCodes {
        let languageCode = language.identifier
        let locale = Locale(identifier: languageCode)
        let candidateNames = uniquePreferred([
            locale.localizedString(forIdentifier: languageCode),
            userLocale.localizedString(forIdentifier: languageCode),
            locale.localizedString(forLanguageCode: languageCode),
            userLocale.localizedString(forLanguageCode: languageCode)
        ])

        for candidate in candidateNames {
            register(name: candidate, code: languageCode, specificity: 0)
            register(name: sentenceCase(candidate, locale: locale), code: languageCode, specificity: 0)
            register(name: sentenceCase(candidate, locale: userLocale), code: languageCode, specificity: 0)
        }
    }

    return lookup
}

func preferredCode(for normalizedName: String, from candidates: [LanguageCodeCandidate]) -> String? {
    let wantsSpecificCode = normalizedName.contains("(") || normalizedName.contains("（")
    let sorted = candidates.sorted { lhs, rhs in
        if wantsSpecificCode {
            if lhs.specificity != rhs.specificity {
                return lhs.specificity > rhs.specificity
            }
        } else if lhs.specificity != rhs.specificity {
            return lhs.specificity < rhs.specificity
        }

        if lhs.code.count != rhs.code.count {
            return lhs.code.count < rhs.code.count
        }

        return lhs.code < rhs.code
    }

    return sorted.first?.code
}

func generalizedLanguageName(_ value: String) -> String {
    value
        .replacingOccurrences(of: #"\s*[\(（].*?[\)）]\s*"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func languageCode(for primary: String, secondary: String, lookup: [String: [LanguageCodeCandidate]]) -> String? {
    let candidates = [primary, secondary]
        .map(normalizeLanguageName)
        .filter { !$0.isEmpty }

    for candidate in candidates {
        if let matches = lookup[candidate], let code = preferredCode(for: candidate, from: matches) {
            return code
        }
    }

    let generalizedCandidates = candidates
        .map(generalizedLanguageName)
        .filter { !$0.isEmpty }

    for candidate in generalizedCandidates {
        if let matches = lookup[candidate], let code = preferredCode(for: candidate, from: matches) {
            return code
        }
    }

    return nil
}

func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.2, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        usleep(useconds_t(poll * 1_000_000))
    }
    return condition()
}

func openLanguagePane() throws {
    try shell("/usr/bin/osascript", [
        "-e", "tell application \"System Settings\" to activate",
        "-e", "try",
        "-e", "  tell application \"System Settings\" to reveal pane id \"com.apple.Localization-Settings.extension\"",
        "-e", "end try"
    ])
}

func systemSettingsWindow() throws -> AXUIElement {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
        throw ToolError.message("System Settings is not running.")
    }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard waitUntil(timeout: 5.0, condition: {
        let windows: [AXUIElement] = attr(appElement, kAXWindowsAttribute as String) ?? []
        return !windows.isEmpty
    }) else {
        throw ToolError.message("System Settings window did not appear.")
    }
    let windows: [AXUIElement] = attr(appElement, kAXWindowsAttribute as String) ?? []
    guard let window = windows.first else {
        throw ToolError.message("System Settings window is unavailable.")
    }
    return window
}

func contentRoot(in window: AXUIElement) throws -> AXUIElement {
    guard let rootGroup = child(window, 0),
          let splitGroup = child(rootGroup, 0),
          let rightGroup = child(splitGroup, 3),
          let wrapper = child(rightGroup, 0),
          let outerScroll = child(wrapper, 0) else {
        throw ToolError.message("Could not locate the Language & Region content panel.")
    }
    return outerScroll
}

func rowCount(in outline: AXUIElement) -> Int {
    children(of: outline).filter { role(of: $0) == kAXRowRole as String }.count
}

func preferredLanguagesOutline(in content: AXUIElement) -> AXUIElement? {
    firstDescendant(of: content, where: {
        role(of: $0) == kAXOutlineRole as String && rowCount(in: $0) > 0
    })
}

func preferredLanguagesGroup(in content: AXUIElement) -> AXUIElement? {
    firstDescendant(of: content, where: { element in
        guard role(of: element) == kAXGroupRole as String else { return false }
        let hasOutline = descendants(of: element, where: {
            role(of: $0) == kAXOutlineRole as String && rowCount(in: $0) > 0
        }).isEmpty == false
        let hasButton = children(of: element).contains(where: { role(of: $0) == kAXButtonRole as String })
        return hasOutline && hasButton
    })
}

func waitForPreferredLanguages(in window: AXUIElement) {
    _ = waitUntil(timeout: 5.0, condition: {
        guard let content = try? contentRoot(in: window) else {
            return false
        }
        return preferredLanguagesOutline(in: content) != nil
    })
}

func preferredLanguages(from window: AXUIElement, lookup: [String: [LanguageCodeCandidate]]) -> [LanguageEntry] {
    guard let content = try? contentRoot(in: window),
          let outline = preferredLanguagesOutline(in: content) else {
        return []
    }

    return children(of: outline).compactMap { row in
        guard role(of: row) == kAXRowRole as String else { return nil }
        let texts = collectStaticTexts(from: row).filter { !$0.isEmpty }
        guard let primary = texts.first else { return nil }
        let secondary = texts.dropFirst().joined(separator: " | ")
        return LanguageEntry(
            code: languageCode(for: primary, secondary: secondary, lookup: lookup),
            primary: primary,
            secondary: secondary
        )
    }
}

func openAddDialogIfNeeded(window: AXUIElement, content: AXUIElement) throws -> Bool {
    if firstDescendant(of: window, where: { role(of: $0) == kAXTableRole as String }) != nil {
        return false
    }
    guard let preferredGroup = preferredLanguagesGroup(in: content),
          let addButton = children(of: preferredGroup).first(where: { role(of: $0) == kAXButtonRole as String }) else {
        throw ToolError.message("Could not locate the add-language button.")
    }
    guard AXUIElementPerformAction(addButton, kAXPressAction as CFString) == .success else {
        throw ToolError.message("Could not open the add-language dialog.")
    }
    guard waitUntil(timeout: 5.0, condition: {
        firstDescendant(of: window, where: { role(of: $0) == kAXTableRole as String }) != nil
    }) else {
        throw ToolError.message("The add-language dialog did not appear.")
    }
    return true
}

func availableLanguages(from window: AXUIElement, lookup: [String: [LanguageCodeCandidate]]) -> [LanguageEntry] {
    guard let table = firstDescendant(of: window, where: { role(of: $0) == kAXTableRole as String }) else {
        return []
    }

    var ordered: [LanguageEntry] = []
    var seen: Set<LanguageEntry> = []

    for row in children(of: table) where role(of: row) == kAXRowRole as String {
        let texts = collectStaticTexts(from: row).filter { !$0.isEmpty && $0 != "—" }
        guard texts.count >= 2 else { continue }
        let entry = LanguageEntry(
            code: languageCode(for: texts[0], secondary: texts[1], lookup: lookup),
            primary: texts[0],
            secondary: texts[1]
        )
        if !seen.contains(entry) {
            seen.insert(entry)
            ordered.append(entry)
        }
    }
    return ordered
}

func closeAddDialogIfPresent(window: AXUIElement) {
    guard firstDescendant(of: window, where: { role(of: $0) == kAXSheetRole as String }) != nil else {
        return
    }
    _ = try? shell("/usr/bin/osascript", [
        "-e", "tell application \"System Events\" to key code 53"
    ])
    _ = waitUntil(timeout: 3.0, condition: {
        firstDescendant(of: window, where: { role(of: $0) == kAXSheetRole as String }) == nil
    })
}

func printText(preferred: [LanguageEntry], available: [LanguageEntry]) {
    print("Preferred Languages:")
    for entry in preferred {
        let prefix = entry.code.map { "\($0) | " } ?? ""
        if entry.secondary.isEmpty {
            print("  \(prefix)\(entry.primary)")
        } else {
            print("  \(prefix)\(entry.primary) | \(entry.secondary)")
        }
    }
    print("")
    print("Available To Add:")
    for entry in available {
        let prefix = entry.code.map { "\($0) | " } ?? ""
        print("  \(prefix)\(entry.primary) | \(entry.secondary)")
    }
}

do {
    guard AXIsProcessTrusted() else {
        throw ToolError.message("Accessibility access is required. Enable it for your terminal or OpenAI app in Privacy & Security > Accessibility.")
    }

    try openLanguagePane()
    let window = try systemSettingsWindow()
    closeAddDialogIfPresent(window: window)
    let content = try contentRoot(in: window)
    waitForPreferredLanguages(in: window)
    let languageLookup = buildLanguageCodeLookup()
    let preferred = preferredLanguages(from: window, lookup: languageLookup)
    let openedNow = try openAddDialogIfNeeded(window: window, content: content)
    let available = availableLanguages(from: window, lookup: languageLookup)
    if openedNow {
        closeAddDialogIfPresent(window: window)
    }

    if wantsJSON {
        let output = Output(preferred: preferred, available: available)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(output)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
        printText(preferred: preferred, available: available)
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
