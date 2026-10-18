import Foundation

/// settings.json → `SopranoTabSettings`. Every key is optional; a bad value keeps its
/// default and becomes a `.warning` naming its dotted path ("appearance.style",
/// "shortcuts[2].key"), the value found and what is allowed.
public enum SettingsResolver {
    /// JSONC (comments, trailing commas) → settings over the defaults. A document that is
    /// not a JSON object gives `settings == nil` and one `.error` issue with its line.
    /// Every bad value is a `.warning` and keeps its default; unknown keys warn.
    public static func resolve(text: String, knownThemeIDs: Set<String>) -> SettingsResolution {
        let root: [String: Any]
        do {
            let data = try JSONCText.strictJSONData(from: text)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dictionary = object as? [String: Any] else {
                let line = firstValueLine(in: String(decoding: data, as: UTF8.self))
                return failure("settings.json must be a JSON object", line: line)
            }
            root = dictionary
        } catch let error as JSONCText.ParseError {
            return failure(error.message, line: error.line)
        } catch {
            return failure("settings.json could not be read: \(error.localizedDescription)", line: 1)
        }

        var reader = Reader(knownThemeIDs: knownThemeIDs)
        let settings = reader.settings(from: root)
        return SettingsResolution(settings: settings, issues: reader.issues)
    }

    private static func failure(_ message: String, line: Int) -> SettingsResolution {
        SettingsResolution(settings: nil, issues: [ConfigIssue(severity: .error, message: message, line: line)])
    }

    /// The 1-based line of the first value in strict JSON text. Comment stripping keeps
    /// every newline, so lines match the original document.
    private static func firstValueLine(in text: String) -> Int {
        var line = 1
        for character in text {
            if character.isNewline {
                line += 1
            } else if !character.isWhitespace {
                break
            }
        }
        return line
    }
}

// MARK: - Reader

/// One resolution pass: reads sections over the defaults and collects issues.
private struct Reader {
    let knownThemeIDs: Set<String>
    var issues: [ConfigIssue] = []

    init(knownThemeIDs: Set<String>) {
        self.knownThemeIDs = knownThemeIDs
    }

    static let filterKeys: Set<String> = [
        "apps", "spaces", "screens", "minimized", "hidden", "fullscreen",
        "windowlessApps", "order", "grouping", "tabs",
    ]
    static let shortcutKeys: Set<String> = filterKeys.union([
        "hold", "key", "onRelease", "style", "size", "theme", "preview",
    ])
    static let gestureKeys: Set<String> = filterKeys.union(["type", "haptics"])
    static let actionControls = ["focus", "cancel", "close", "minimize", "fullscreen", "quit", "hide", "search"]
    static let vimLetters: Set<Character> = ["h", "j", "k", "l"]

    mutating func settings(from root: [String: Any]) -> SopranoTabSettings {
        var settings = SopranoTabSettings()
        warnUnknownKeys(
            in: root,
            path: nil,
            known: ["theme", "shortcuts", "gesture", "controls", "mouse", "appearance", "exceptions", "app"]
        )

        if let value = root["theme"] {
            settings.theme = theme(value, path: "theme", current: settings.theme) ?? settings.theme
        }
        if let value = root["shortcuts"] {
            settings.shortcuts = shortcuts(value)
        }
        if let gesture = section("gesture", in: root, path: nil) {
            settings.gesture = self.gesture(gesture)
        }
        if let controls = section("controls", in: root, path: nil) {
            settings.controls = self.controls(controls)
        }
        if let mouse = section("mouse", in: root, path: nil) {
            warnUnknownKeys(in: mouse, path: "mouse", known: ["hoverSelects", "cursorFollowsFocus"])
            bool("hoverSelects", in: mouse, path: "mouse", into: &settings.mouse.hoverSelects)
            choice("cursorFollowsFocus", in: mouse, path: "mouse", into: &settings.mouse.cursorFollowsFocus)
        }
        if let appearance = section("appearance", in: root, path: nil) {
            settings.appearance = self.appearance(appearance)
        }
        if let value = root["exceptions"] {
            settings.exceptions = exceptions(value)
        }
        if let app = section("app", in: root, path: nil) {
            warnUnknownKeys(in: app, path: "app", known: ["startAtLogin", "menuBarIcon"])
            bool("startAtLogin", in: app, path: "app", into: &settings.app.startAtLogin)
            choice("menuBarIcon", in: app, path: "app", into: &settings.app.menuBarIcon)
        }
        return settings
    }

    // MARK: Shortcuts

    private mutating func shortcuts(_ value: Any) -> [ShortcutSettings] {
        let defaults = ShortcutSettings.defaults
        guard let entries = value as? [Any] else {
            warn("shortcuts: \(describe(value)) is not an array of shortcuts; kept the default shortcuts.")
            return defaults
        }
        guard !entries.isEmpty else {
            warn("shortcuts is empty; kept the default shortcuts.")
            return defaults
        }
        let limit = SopranoTabSettings.maxShortcuts
        if entries.count > limit {
            warn("shortcuts has \(entries.count) entries; only the first \(limit) are used.")
        }

        var result: [(index: Int, shortcut: ShortcutSettings)] = []
        for (index, entry) in entries.prefix(limit).enumerated() {
            let path = "shortcuts[\(index)]"
            guard let object = entry as? [String: Any] else {
                warn("\(path): \(describe(entry)) is not an object; dropped.")
                continue
            }
            guard let shortcut = self.shortcut(object, index: index, path: path) else { continue }
            if let earlier = result.first(where: { $0.shortcut.hold == shortcut.hold && $0.shortcut.key == shortcut.key }) {
                let chord = "\(shortcut.hold.settingsText)+\(shortcut.key.settingsText)"
                warn("\(path) repeats \(chord) of shortcuts[\(earlier.index)]; dropped.")
                continue
            }
            result.append((index, shortcut))
        }

        guard !result.isEmpty else {
            warn("shortcuts has no usable entry; kept the default shortcuts.")
            return defaults
        }
        return result.map(\.shortcut)
    }

    /// One entry over `defaultFilters(forIndex:)`; nil (with a warning) when it has no key.
    private mutating func shortcut(_ object: [String: Any], index: Int, path: String) -> ShortcutSettings? {
        warnUnknownKeys(in: object, path: path, known: Self.shortcutKeys)

        let defaultKey: KeySpec? = switch index {
        case 0: .named(.tab)
        case 1: .named(.keyAboveTab)
        default: nil
        }
        var chosenKey = defaultKey
        if let value = object["key"] {
            if let text = value as? String, let parsed = KeySpec(settingsText: text) {
                chosenKey = parsed
            } else if let defaultKey {
                warn("\(path).key: \(describe(value)) is not a key; kept \"\(defaultKey.settingsText)\".")
            } else {
                warn("\(path).key: \(describe(value)) is not a key; shortcut dropped.")
                return nil
            }
        }
        guard let key = chosenKey else {
            warn("\(path) has no \"key\"; shortcut dropped.")
            return nil
        }

        var hold = ModifierSet.option
        if let value = object["hold"] {
            if let text = value as? String, let parsed = ModifierSet(settingsText: text) {
                hold = parsed
            } else {
                warn("\(path).hold: \(describe(value)) is not a modifier combination like \"option\" or \"command+shift\"; kept \"option\".")
            }
        }

        var shortcut = ShortcutSettings(hold: hold, key: key, filters: filters(object, path: path, over: ShortcutSettings.defaultFilters(forIndex: index)))
        choice("onRelease", in: object, path: path, into: &shortcut.onRelease)
        shortcut.overrides.style = override("style", in: object, path: path)
        shortcut.overrides.size = override("size", in: object, path: path)
        if let value = object["theme"] {
            shortcut.overrides.theme = theme(value, path: "\(path).theme", current: nil)
        }
        if let value = object["preview"] {
            if let flag = boolean(value) {
                shortcut.overrides.previewSelectedWindow = flag
            } else {
                warn("\(path).preview: \(describe(value)) is not true or false; kept the appearance value.")
            }
        }
        return shortcut
    }

    private mutating func filters(_ object: [String: Any], path: String, over defaults: WindowFilters) -> WindowFilters {
        var filters = defaults
        choice("apps", in: object, path: path, into: &filters.apps)
        choice("spaces", in: object, path: path, into: &filters.spaces)
        choice("screens", in: object, path: path, into: &filters.screens)
        choice("minimized", in: object, path: path, into: &filters.minimized)
        choice("hidden", in: object, path: path, into: &filters.hidden)
        choice("fullscreen", in: object, path: path, into: &filters.fullscreen)
        choice("windowlessApps", in: object, path: path, into: &filters.windowlessApps)
        choice("order", in: object, path: path, into: &filters.order)
        choice("grouping", in: object, path: path, into: &filters.grouping)
        choice("tabs", in: object, path: path, into: &filters.tabs)
        return filters
    }

    // MARK: Sections

    private mutating func gesture(_ object: [String: Any]) -> GestureSettings {
        warnUnknownKeys(in: object, path: "gesture", known: Self.gestureKeys)
        var gesture = GestureSettings(filters: filters(object, path: "gesture", over: WindowFilters()))
        choice("type", in: object, path: "gesture", into: &gesture.kind)
        bool("haptics", in: object, path: "gesture", into: &gesture.hapticFeedback)
        return gesture
    }

    private mutating func controls(_ object: [String: Any]) -> ControlSettings {
        let path = "controls"
        warnUnknownKeys(in: object, path: path, known: Set(Self.actionControls + ["previous", "arrowKeys", "vimKeys"]))
        var controls = ControlSettings()

        let actionPaths: [(name: String, keyPath: WritableKeyPath<ControlSettings, KeySpec?>)] = [
            ("focus", \.focus), ("cancel", \.cancel), ("close", \.close), ("minimize", \.minimize),
            ("fullscreen", \.fullscreen), ("quit", \.quit), ("hide", \.hide), ("search", \.search),
        ]
        for (name, keyPath) in actionPaths {
            guard let value = object[name] else { continue }
            if value is NSNull {
                controls[keyPath: keyPath] = nil
            } else if let text = value as? String, let key = KeySpec(settingsText: text) {
                controls[keyPath: keyPath] = key
            } else {
                warn("\(path).\(name): \(describe(value)) is not a key or null; kept \(describeKey(controls[keyPath: keyPath])).")
            }
        }

        if let value = object["previous"] {
            if value is NSNull {
                controls.previous = []
            } else if let text = value as? String, let modifier = ModifierSet(settingsText: text), modifier.rawValue.nonzeroBitCount == 1 {
                controls.previous = modifier
            } else {
                warn("\(path).previous: \(describe(value)) is not one modifier (\"shift\", \"option\", \"control\", \"command\", \"fn\") or null; kept \"\(controls.previous.settingsText)\".")
            }
        }
        bool("arrowKeys", in: object, path: path, into: &controls.arrowKeys)
        bool("vimKeys", in: object, path: path, into: &controls.vimKeys)

        // The earlier control in `actionPaths` order keeps a shared key.
        for (laterIndex, later) in actionPaths.enumerated() {
            guard let key = controls[keyPath: later.keyPath] else { continue }
            if let earlier = actionPaths.prefix(laterIndex).first(where: { controls[keyPath: $0.keyPath] == key }) {
                warn("\(path).\(later.name) uses \"\(key.settingsText)\" like \(path).\(earlier.name); \(path).\(later.name) is disabled.")
                controls[keyPath: later.keyPath] = nil
            }
        }

        if controls.vimKeys {
            for (name, keyPath) in actionPaths {
                if case .character(let letter)? = controls[keyPath: keyPath], Self.vimLetters.contains(letter) {
                    warn("\(path).\(name) is \"\(letter)\", which vimKeys uses to move the selection; movement wins.")
                }
            }
        }
        return controls
    }

    private mutating func appearance(_ object: [String: Any]) -> AppearanceSettings {
        let path = "appearance"
        warnUnknownKeys(in: object, path: path, known: [
            "style", "size", "screen", "titles", "titleTruncation", "windowControls", "spaceLabels",
            "statusIcons", "showDelayMs", "fadeOut", "previewSelectedWindow", "previewFadeIn",
            "searchHint", "captureInBackground",
        ])
        var appearance = AppearanceSettings()
        choice("style", in: object, path: path, into: &appearance.style)
        choice("size", in: object, path: path, into: &appearance.size)
        choice("screen", in: object, path: path, into: &appearance.screen)
        choice("titles", in: object, path: path, into: &appearance.titles)
        choice("titleTruncation", in: object, path: path, into: &appearance.titleTruncation)
        bool("windowControls", in: object, path: path, into: &appearance.windowControls)
        bool("spaceLabels", in: object, path: path, into: &appearance.spaceLabels)
        bool("statusIcons", in: object, path: path, into: &appearance.statusIcons)
        bool("fadeOut", in: object, path: path, into: &appearance.fadeOut)
        bool("previewSelectedWindow", in: object, path: path, into: &appearance.previewSelectedWindow)
        bool("previewFadeIn", in: object, path: path, into: &appearance.previewFadeIn)
        bool("searchHint", in: object, path: path, into: &appearance.searchHint)
        bool("captureInBackground", in: object, path: path, into: &appearance.captureInBackground)

        if let value = object["showDelayMs"] {
            let range = AppearanceSettings.showDelayRange
            if let delay = integer(value) {
                let clamped = min(max(range.lowerBound, delay), range.upperBound)
                if clamped != delay {
                    warn("\(path).showDelayMs: \(delay) is outside \(range.lowerBound)–\(range.upperBound); clamped to \(clamped).")
                }
                appearance.showDelayMs = clamped
            } else {
                warn("\(path).showDelayMs: \(describe(value)) is not a whole number of milliseconds; kept \(appearance.showDelayMs).")
            }
        }
        return appearance
    }

    // MARK: Exceptions

    private mutating func exceptions(_ value: Any) -> [ExceptionRule] {
        guard let entries = value as? [Any] else {
            warn("exceptions: \(describe(value)) is not an array of exceptions; kept the default exceptions.")
            return ExceptionRule.defaults
        }
        var rules: [ExceptionRule] = []
        for (index, entry) in entries.enumerated() {
            let path = "exceptions[\(index)]"
            guard let object = entry as? [String: Any] else {
                warn("\(path): \(describe(entry)) is not an object; dropped.")
                continue
            }
            warnUnknownKeys(in: object, path: path, known: ["bundleId", "hide", "titleContains", "ignoreShortcuts"])
            guard let bundleID = (object["bundleId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleID.isEmpty
            else {
                let found = object["bundleId"].map { describe($0) } ?? "missing"
                warn("\(path).bundleId: \(found) is not a bundle identifier; exception dropped.")
                continue
            }

            var rule = ExceptionRule(bundleID: bundleID)
            choice("hide", in: object, path: path, into: &rule.hide)
            choice("ignoreShortcuts", in: object, path: path, into: &rule.ignoreShortcuts)
            if let value = object["titleContains"] {
                if let text = value as? String {
                    rule.titleContains = [text]
                } else if let list = value as? [Any], list.allSatisfy({ $0 is String }) {
                    rule.titleContains = list.compactMap { $0 as? String }
                } else {
                    warn("\(path).titleContains: \(describe(value)) is not a string or an array of strings; ignored.")
                }
                if rule.titleContains.contains(where: \.isEmpty) {
                    warn("\(path).titleContains: an empty string would match every title; ignored it.")
                    rule.titleContains.removeAll(where: \.isEmpty)
                }
            }
            if rule.hide == .whenTitleContains, rule.titleContains.isEmpty {
                warn("\(path).hide is \"whenTitleContains\" without titleContains; it hides no window.")
            }
            rules.append(rule)
        }
        return rules
    }

    // MARK: Helpers

    private mutating func warn(_ message: String) {
        issues.append(ConfigIssue(severity: .warning, message: message))
    }

    private func join(_ path: String?, _ key: String) -> String {
        path.map { "\($0).\(key)" } ?? key
    }

    private mutating func warnUnknownKeys(in object: [String: Any], path: String?, known: Set<String>) {
        for key in object.keys.sorted() where !known.contains(key) {
            warn("Unknown setting \"\(join(path, key))\".")
        }
    }

    /// The object at `key`, or nil (with a warning when present but not an object).
    private mutating func section(_ key: String, in object: [String: Any], path: String?) -> [String: Any]? {
        guard let value = object[key] else { return nil }
        guard let section = value as? [String: Any] else {
            warn("\(join(path, key)): \(describe(value)) is not an object; ignored.")
            return nil
        }
        return section
    }

    private mutating func bool(_ key: String, in object: [String: Any], path: String, into target: inout Bool) {
        guard let value = object[key] else { return }
        if let flag = boolean(value) {
            target = flag
        } else {
            warn("\(path).\(key): \(describe(value)) is not true or false; kept \(target).")
        }
    }

    /// An enum value by its rawValue; a bad value warns with the allowed values.
    private mutating func choice<Value: RawRepresentable & CaseIterable>(
        _ key: String,
        in object: [String: Any],
        path: String,
        into target: inout Value
    ) where Value.RawValue == String {
        guard let value = object[key] else { return }
        if let raw = value as? String, let parsed = Value(rawValue: raw) {
            target = parsed
        } else {
            warn("\(path).\(key): \(describe(value)) is not one of \(allowed(Value.self)); kept \"\(target.rawValue)\".")
        }
    }

    /// A per-shortcut appearance override; nil when absent or bad.
    private mutating func override<Value: RawRepresentable & CaseIterable>(
        _ key: String,
        in object: [String: Any],
        path: String
    ) -> Value? where Value.RawValue == String {
        guard let value = object[key] else { return nil }
        if let raw = value as? String, let parsed = Value(rawValue: raw) {
            return parsed
        }
        warn("\(path).\(key): \(describe(value)) is not one of \(allowed(Value.self)); kept the appearance value.")
        return nil
    }

    /// A known theme id, or nil with a warning naming the known ids.
    private mutating func theme(_ value: Any, path: String, current: String?) -> String? {
        if let id = value as? String, id == "soprano" || knownThemeIDs.contains(id) {
            return id
        }
        let known = (["soprano"] + knownThemeIDs.subtracting(["soprano"]).sorted()).map { "\"\($0)\"" }.joined(separator: ", ")
        let kept = current.map { "kept \"\($0)\"" } ?? "kept the global theme"
        warn("\(path): \(describe(value)) is not a known theme; \(kept). Known themes: \(known).")
        return nil
    }

    private func allowed<Value: RawRepresentable & CaseIterable>(_: Value.Type) -> String where Value.RawValue == String {
        Value.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
    }

    /// JSON booleans only (JSONSerialization gives NSNumber for both numbers and booleans).
    private func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// JSON numbers without a fractional part.
    private func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double == double.rounded(), abs(double) < 1e9 else { return nil }
        return Int(double)
    }

    private func describe(_ value: Any) -> String {
        switch value {
        case is NSNull:
            return "null"
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case is [Any]:
            return "an array"
        case is [String: Any]:
            return "an object"
        default:
            return String(describing: value)
        }
    }

    private func describeKey(_ key: KeySpec?) -> String {
        key.map { "\"\($0.settingsText)\"" } ?? "null"
    }
}
