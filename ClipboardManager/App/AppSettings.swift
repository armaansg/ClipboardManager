import AppKit
import Combine

/// User-adjustable settings, persisted in UserDefaults. `AppConfig` holds the defaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let retentionDays = "retentionDays"
        static let storeCapMB = "storeCapMB"
        static let panelHeightFraction = "panelHeightFraction"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let copyAsPlainTextByDefault = "copyAsPlainTextByDefault"
        static let hasShownWelcome = "hasShownWelcome"
    }

    static let retentionRange = 1...365
    static let storeCapRange = 50...5_000
    static let panelHeightRange = 0.15...0.5

    private let defaults = UserDefaults.standard

    @Published var hotKey: HotKeyDefinition {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
            defaults.set(Int(hotKey.modifiers.rawValue), forKey: Keys.hotKeyModifiers)
        }
    }
    /// Set by the app when registering the shortcut fails (for example, another app already owns it).
    @Published var hotKeyError: String?

    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }
    @Published var storeCapMB: Int {
        didSet { defaults.set(storeCapMB, forKey: Keys.storeCapMB) }
    }
    @Published var panelHeightFraction: Double {
        didSet { defaults.set(panelHeightFraction, forKey: Keys.panelHeightFraction) }
    }
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs) }
    }
    @Published var copyAsPlainTextByDefault: Bool {
        didSet { defaults.set(copyAsPlainTextByDefault, forKey: Keys.copyAsPlainTextByDefault) }
    }

    var hasShownWelcome: Bool {
        get { defaults.bool(forKey: Keys.hasShownWelcome) }
        set { defaults.set(newValue, forKey: Keys.hasShownWelcome) }
    }

    var retentionInterval: TimeInterval { Double(retentionDays) * 86_400 }
    var storeCapBytes: Int64 { Int64(storeCapMB) * 1024 * 1024 }

    private init() {
        if defaults.object(forKey: Keys.hotKeyCode) != nil, defaults.object(forKey: Keys.hotKeyModifiers) != nil {
            hotKey = HotKeyDefinition(keyCode: UInt32(defaults.integer(forKey: Keys.hotKeyCode)),
                                      modifiers: NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Keys.hotKeyModifiers))))
        } else {
            hotKey = AppConfig.toggleHotKey
        }
        let days = defaults.integer(forKey: Keys.retentionDays)
        retentionDays = Self.retentionRange.contains(days) ? days : AppConfig.retentionDays
        let cap = defaults.integer(forKey: Keys.storeCapMB)
        storeCapMB = Self.storeCapRange.contains(cap) ? cap : Int(AppConfig.storeCapBytes / (1024 * 1024))
        let fraction = defaults.double(forKey: Keys.panelHeightFraction)
        panelHeightFraction = Self.panelHeightRange.contains(fraction) ? fraction : Double(AppConfig.panelHeightFraction)
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []
        copyAsPlainTextByDefault = defaults.bool(forKey: Keys.copyAsPlainTextByDefault)
    }

    func resetHotKey() {
        hotKey = AppConfig.toggleHotKey
    }

    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    func addExclusion(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !excludedBundleIDs.contains(trimmed) else { return }
        excludedBundleIDs.append(trimmed)
        excludedBundleIDs.sort()
    }

    func removeExclusion(_ bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }
}
