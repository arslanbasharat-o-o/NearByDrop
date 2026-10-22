import Cocoa
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum AccentOption: String, CaseIterable, Identifiable {
    case blue = "QuickShare Blue"
    case cyan = "AirDrop Cyan"
    case green = "Android Green"
    case purple = "Royal Purple"
    case orange = "Sunset Orange"
    case pink = "Neon Pink"
    case graphite = "Graphite"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return Color(nsColor: .systemBlue)
        case .cyan: return Color(nsColor: .systemCyan)
        case .green: return Color(nsColor: .systemGreen)
        case .purple: return Color(nsColor: .systemPurple)
        case .orange: return Color(nsColor: .systemOrange)
        case .pink: return Color(nsColor: .systemPink)
        case .graphite: return Color(nsColor: .systemGray)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .cyan: return .systemCyan
        case .green: return .systemGreen
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        case .pink: return .systemPink
        case .graphite: return .systemGray
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case quickShare = "Quick Share"
    case antenna = "AirDrop Waves"
    case paperplane = "Paperplane"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .quickShare: return "antenna.radiowaves.left.and.right"
        case .antenna: return "dot.radiowaves.left.and.right"
        case .paperplane: return "paperplane.fill"
        }
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "appTheme")
            currentTheme.apply()
        }
    }

    @Published var currentAccent: AccentOption {
        didSet {
            UserDefaults.standard.set(currentAccent.rawValue, forKey: "appAccent")
        }
    }

    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet {
            UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: "menuBarIconStyle")
            onMenuBarIconChanged?()
        }
    }

    var onMenuBarIconChanged: (() -> Void)?

    private init() {
        let savedTheme = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue
        self.currentTheme = AppTheme(rawValue: savedTheme) ?? .system

        let savedAccent = UserDefaults.standard.string(forKey: "appAccent") ?? AccentOption.blue.rawValue
        self.currentAccent = AccentOption(rawValue: savedAccent) ?? .blue

        let savedIcon = UserDefaults.standard.string(forKey: "menuBarIconStyle") ?? MenuBarIconStyle.quickShare.rawValue
        self.menuBarIconStyle = MenuBarIconStyle(rawValue: savedIcon) ?? .quickShare

        currentTheme.apply()
    }

    func menuBarImage() -> NSImage? {
        switch menuBarIconStyle {
        case .quickShare:
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = true
                return img
            }
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            return NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "Nearbydrop")?.withSymbolConfiguration(config)
        case .antenna:
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            return NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "Nearbydrop")?.withSymbolConfiguration(config)
        case .paperplane:
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            return NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Nearbydrop")?.withSymbolConfiguration(config)
        }
    }
}

final class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()

    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
        }
    }

    @Published var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
        }
    }

    init() {
        if UserDefaults.standard.object(forKey: "soundEnabled") == nil {
            self.soundEnabled = true
        } else {
            self.soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
        }

        if UserDefaults.standard.object(forKey: "hapticsEnabled") == nil {
            self.hapticsEnabled = true
        } else {
            self.hapticsEnabled = UserDefaults.standard.bool(forKey: "hapticsEnabled")
        }
    }

    // MARK: - Audio Artifacts
    func playSuccess() {
        guard soundEnabled else { return }
        NSSound(named: "Glass")?.play()
    }

    func playIncoming() {
        guard soundEnabled else { return }
        (NSSound(named: "Bottle") ?? NSSound(named: "Ping"))?.play()
    }

    func playStart() {
        guard soundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    func playError() {
        guard soundEnabled else { return }
        NSSound(named: "Basso")?.play()
    }

    // MARK: - Trackpad Vibration / Haptics
    func vibrateSuccess() {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func vibrateClick() {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    func vibrateTap() {
        guard hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
