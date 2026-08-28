import Foundation

public enum PreloadLevel: Int, Sendable, CaseIterable {
    case off = 0
    case one = 1
    case two = 2

    public var neighborCount: Int { rawValue }
}

public enum InitialZoomMode: String, Sendable, CaseIterable {
    case fit
    case fill
    case actualSize
}

public final class PreferencesStore {
    public enum Key: String {
        case preloadLevel = "viewer.preloadLevel"
        case navigationWraps = "viewer.navigationWraps"
        case zoomStep = "viewer.zoomStep"
        case initialZoomMode = "viewer.initialZoomMode"
        case showsWelcomeGuide = "interface.showsWelcomeGuide"
    }

    public static let defaultZoomStep = 1.2
    private static let zoomStepRange = 1.01...3.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var preloadLevel: PreloadLevel {
        get {
            guard let value = PreloadLevel(rawValue: defaults.integer(forKey: Key.preloadLevel.rawValue)) else {
                defaults.set(PreloadLevel.one.rawValue, forKey: Key.preloadLevel.rawValue)
                return .one
            }
            if defaults.object(forKey: Key.preloadLevel.rawValue) == nil {
                return .one
            }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.preloadLevel.rawValue) }
    }

    public var navigationWraps: Bool {
        get { defaults.bool(forKey: Key.navigationWraps.rawValue) }
        set { defaults.set(newValue, forKey: Key.navigationWraps.rawValue) }
    }

    public var zoomStep: Double {
        get {
            let value = defaults.double(forKey: Key.zoomStep.rawValue)
            guard Self.zoomStepRange.contains(value) else {
                defaults.set(Self.defaultZoomStep, forKey: Key.zoomStep.rawValue)
                return Self.defaultZoomStep
            }
            return value
        }
        set {
            let value = Self.zoomStepRange.contains(newValue) ? newValue : Self.defaultZoomStep
            defaults.set(value, forKey: Key.zoomStep.rawValue)
        }
    }

    public var initialZoomMode: InitialZoomMode {
        get {
            guard let raw = defaults.string(forKey: Key.initialZoomMode.rawValue),
                  let mode = InitialZoomMode(rawValue: raw) else { return .fit }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.initialZoomMode.rawValue) }
    }

    public var showsWelcomeGuide: Bool {
        get {
            guard defaults.object(forKey: Key.showsWelcomeGuide.rawValue) != nil else { return true }
            return defaults.bool(forKey: Key.showsWelcomeGuide.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.showsWelcomeGuide.rawValue) }
    }
}
