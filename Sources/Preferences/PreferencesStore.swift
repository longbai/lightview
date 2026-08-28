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

public enum AppearancePreference: String, Sendable, CaseIterable {
    case followSystem
    case light
    case dark
}

public enum ViewerBackgroundPreference: String, Sendable, CaseIterable {
    case black
    case darkGray
    case white
    case customColor
    case customImage
}

public final class PreferencesStore {
    public enum Key: String {
        case preloadLevel = "viewer.preloadLevel"
        case navigationWraps = "viewer.navigationWraps"
        case zoomStep = "viewer.zoomStep"
        case initialZoomMode = "viewer.initialZoomMode"
        case showsWelcomeGuide = "interface.showsWelcomeGuide"
        case appearance = "interface.appearance"
        case viewerBackground = "viewer.background"
        case customBackgroundColorHex = "viewer.customBackgroundColorHex"
        case backgroundImagePath = "viewer.backgroundImagePath"
        case catalogSort = "catalog.sort"
        case autoResizesWindow = "viewer.autoResizesWindow"
        case slideshowInterval = "playback.slideshowInterval"
        case animationEnergySaving = "playback.animationEnergySaving"
    }

    public static let defaultZoomStep = 1.2
    public static let defaultSlideshowInterval = 5.0
    private static let zoomStepRange = 1.01...3.0
    private static let slideshowIntervalRange = 1.0...3_600.0

    private let defaults: UserDefaults
    private let fileManager: FileManager

    public init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
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

    public var appearance: AppearancePreference {
        get {
            guard let raw = defaults.string(forKey: Key.appearance.rawValue),
                  let value = AppearancePreference(rawValue: raw) else { return .followSystem }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance.rawValue) }
    }

    public var viewerBackground: ViewerBackgroundPreference {
        get {
            guard let raw = defaults.string(forKey: Key.viewerBackground.rawValue),
                  let value = ViewerBackgroundPreference(rawValue: raw) else { return .black }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.viewerBackground.rawValue) }
    }

    public var customBackgroundColorHex: String? {
        get { defaults.string(forKey: Key.customBackgroundColorHex.rawValue) }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.customBackgroundColorHex.rawValue)
                return
            }
            guard Self.isValidColorHex(newValue) else { return }
            defaults.set(newValue.uppercased(), forKey: Key.customBackgroundColorHex.rawValue)
        }
    }

    public var backgroundImageURL: URL? {
        guard let path = defaults.string(forKey: Key.backgroundImagePath.rawValue) else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return fileManager.isReadableFile(atPath: url.path) ? url : nil
    }

    public var catalogSort: CatalogSort {
        get {
            guard let raw = defaults.string(forKey: Key.catalogSort.rawValue),
                  let value = CatalogSort(rawValue: raw) else { return .nameAscending }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.catalogSort.rawValue) }
    }

    public var autoResizesWindow: Bool {
        get { defaults.bool(forKey: Key.autoResizesWindow.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoResizesWindow.rawValue) }
    }

    public var slideshowInterval: Double {
        get {
            let value = defaults.double(forKey: Key.slideshowInterval.rawValue)
            return Self.slideshowIntervalRange.contains(value) ? value : Self.defaultSlideshowInterval
        }
        set {
            defaults.set(
                Self.slideshowIntervalRange.contains(newValue) ? newValue : Self.defaultSlideshowInterval,
                forKey: Key.slideshowInterval.rawValue
            )
        }
    }

    public var animationEnergySaving: Bool {
        get {
            guard defaults.object(forKey: Key.animationEnergySaving.rawValue) != nil else { return true }
            return defaults.bool(forKey: Key.animationEnergySaving.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.animationEnergySaving.rawValue) }
    }

    @discardableResult
    public func setBackgroundImageURL(_ url: URL?) -> Bool {
        guard let url else {
            defaults.removeObject(forKey: Key.backgroundImagePath.rawValue)
            return true
        }
        let standardizedURL = url.standardizedFileURL
        guard fileManager.isReadableFile(atPath: standardizedURL.path) else { return false }
        defaults.set(standardizedURL.path, forKey: Key.backgroundImagePath.rawValue)
        return true
    }

    private static func isValidColorHex(_ value: String) -> Bool {
        guard value.count == 9, value.first == "#" else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }
}
