import AppKit
import Combine
import Foundation
import Sparkle

/// Thin wrapper around Sparkle so the rest of the app never imports it. Automatic checks are off unless
/// the user turns them on; nothing else in the app touches the network.
///
/// The updater only starts when Info.plist carries a real `SUPublicEDKey` (and `SUFeedURL`). Without them
/// Sparkle would refuse to start and raise a modal alert, so unconfigured builds simply report that updates
/// are not set up.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    private let controller: SPUStandardUpdaterController
    private var observers: [NSKeyValueObservation] = []

    /// True when the build ships a public key and feed URL and the updater started successfully.
    let isConfigured: Bool
    private(set) var configurationProblem: String?

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            guard isConfigured, controller.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    @Published private(set) var canCheckForUpdates = false

    override init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let feed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        var configured = false
        var problem: String?
        if key.isEmpty || key.count < 32 {
            problem = "This build has no update signing key (SUPublicEDKey), so it cannot check for updates."
        } else if feed.isEmpty || URL(string: feed)?.host == nil {
            problem = "This build has no update feed URL (SUFeedURL), so it cannot check for updates."
        } else {
            do {
                try controller.updater.start()
                configured = true
            } catch {
                problem = "The updater could not start: \(error.localizedDescription)"
            }
        }
        isConfigured = configured
        configurationProblem = problem
        automaticallyChecksForUpdates = configured ? controller.updater.automaticallyChecksForUpdates : false
        super.init()

        if configured {
            canCheckForUpdates = controller.updater.canCheckForUpdates
            observers.append(controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
                Task { @MainActor in self?.canCheckForUpdates = updater.canCheckForUpdates }
            })
        }
    }

    func checkForUpdates() {
        guard isConfigured else {
            let alert = NSAlert()
            alert.messageText = "Updates aren't set up for this build"
            alert.informativeText = (configurationProblem ?? "") + "\n\nIf you built the app yourself, pull the latest source and rebuild to update."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }

    var versionDescription: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var statusDescription: String {
        guard isConfigured else { return configurationProblem ?? "Updates not configured" }
        if let last = controller.updater.lastUpdateCheckDate {
            return "Last checked \(Formatters.relative(last))"
        }
        return "Never checked"
    }
}
