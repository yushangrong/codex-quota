import Foundation

enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case dark
    case light
}

@MainActor
final class AppSettings {
    private enum Key {
        static let horizontalOffset = "horizontalOffset"
        static let verticalOffset = "verticalOffset"
        static let overlayEnabled = "overlayEnabled"
        static let appearance = "appearance"
        static let onboardingVersion = "onboardingVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var horizontalOffset: Double {
        get { defaults.double(forKey: Key.horizontalOffset) }
        set { defaults.set(newValue, forKey: Key.horizontalOffset) }
    }

    var verticalOffset: Double {
        get { defaults.double(forKey: Key.verticalOffset) }
        set { defaults.set(newValue, forKey: Key.verticalOffset) }
    }

    var overlayEnabled: Bool {
        get {
            defaults.object(forKey: Key.overlayEnabled) == nil
                ? true
                : defaults.bool(forKey: Key.overlayEnabled)
        }
        set { defaults.set(newValue, forKey: Key.overlayEnabled) }
    }

    var appearance: AppAppearance {
        get {
            guard let rawValue = defaults.string(forKey: Key.appearance) else { return .system }
            return AppAppearance(rawValue: rawValue) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    var onboardingVersion: Int {
        get { defaults.integer(forKey: Key.onboardingVersion) }
        set { defaults.set(newValue, forKey: Key.onboardingVersion) }
    }

    var snapshot: AppSettingsSnapshot {
        .init(
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            overlayEnabled: overlayEnabled
        )
    }

    func resetPosition() {
        horizontalOffset = 0
        verticalOffset = 0
    }
}
