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
    let primary: String
    let secondary: String
}

struct Output: Encodable {
    let preferred: [LanguageEntry]
    let available: [LanguageEntry]
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
          let outerScroll = child(wrapper, 0),
          let content = child(outerScroll, 0) else {
        throw ToolError.message("Could not locate the Language & Region content panel.")
    }
    return content
}

func waitForPreferredLanguages(in window: AXUIElement) {
    _ = waitUntil(timeout: 5.0, condition: {
        guard let content = try? contentRoot(in: window),
              let preferredGroup = child(content, 0),
              let scrollArea = child(preferredGroup, 1),
              let outline = child(scrollArea, 0) else {
            return false
        }
        return children(of: outline).contains(where: { role(of: $0) == kAXRowRole as String })
    })
}

func preferredLanguages(from window: AXUIElement) -> [LanguageEntry] {
    guard let content = try? contentRoot(in: window),
          let preferredGroup = child(content, 0),
          let scrollArea = child(preferredGroup, 1),
          let outline = child(scrollArea, 0) else {
        return []
    }

    return children(of: outline).compactMap { row in
        guard role(of: row) == kAXRowRole as String else { return nil }
        let texts = collectStaticTexts(from: row).filter { !$0.isEmpty }
        guard let primary = texts.first else { return nil }
        let secondary = texts.dropFirst().joined(separator: " | ")
        return LanguageEntry(primary: primary, secondary: secondary)
    }
}

func openAddDialogIfNeeded(window: AXUIElement, content: AXUIElement) throws -> Bool {
    if firstDescendant(of: window, where: { role(of: $0) == kAXTableRole as String }) != nil {
        return false
    }
    guard let preferredGroup = child(content, 0), let addButton = child(preferredGroup, 2) else {
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

func availableLanguages(from window: AXUIElement) -> [LanguageEntry] {
    guard let table = firstDescendant(of: window, where: { role(of: $0) == kAXTableRole as String }) else {
        return []
    }

    var ordered: [LanguageEntry] = []
    var seen: Set<LanguageEntry> = []

    for row in children(of: table) where role(of: row) == kAXRowRole as String {
        let texts = collectStaticTexts(from: row).filter { !$0.isEmpty && $0 != "—" }
        guard texts.count >= 2 else { continue }
        let entry = LanguageEntry(primary: texts[0], secondary: texts[1])
        if !seen.contains(entry) {
            seen.insert(entry)
            ordered.append(entry)
        }
    }
    return ordered
}

func closeAddDialogIfPresent(window: AXUIElement) {
    guard let sheet = firstDescendant(of: window, where: { role(of: $0) == kAXSheetRole as String }) else {
        return
    }
    let buttons = descendants(of: sheet, where: { role(of: $0) == kAXButtonRole as String })
    if let firstButton = buttons.first {
        _ = AXUIElementPerformAction(firstButton, kAXPressAction as CFString)
    } else {
        _ = try? shell("/usr/bin/osascript", [
            "-e", "tell application \"System Events\" to key code 53"
        ])
    }
    _ = waitUntil(timeout: 3.0, condition: {
        firstDescendant(of: window, where: { role(of: $0) == kAXSheetRole as String }) == nil
    })
}

func preferredLanguagesFromDefaults() -> [LanguageEntry] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["read", "-g", "AppleLanguages"]
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return []
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else {
        return []
    }
    let tags = text
        .split(whereSeparator: { $0.isNewline })
        .map { String($0).replacingOccurrences(of: "[()\", ]", with: "", options: .regularExpression) }
        .filter { !$0.isEmpty }
    return tags.map { LanguageEntry(primary: $0, secondary: "AppleLanguages tag") }
}

func printText(preferred: [LanguageEntry], available: [LanguageEntry]) {
    print("Preferred Languages:")
    for entry in preferred {
        if entry.secondary.isEmpty {
            print("  \(entry.primary)")
        } else {
            print("  \(entry.primary) | \(entry.secondary)")
        }
    }
    print("")
    print("Available To Add:")
    for entry in available {
        print("  \(entry.primary) | \(entry.secondary)")
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
    let preferredFromUI = preferredLanguages(from: window)
    let preferred = preferredFromUI.isEmpty ? preferredLanguagesFromDefaults() : preferredFromUI
    let openedNow = try openAddDialogIfNeeded(window: window, content: content)
    let available = availableLanguages(from: window)
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
