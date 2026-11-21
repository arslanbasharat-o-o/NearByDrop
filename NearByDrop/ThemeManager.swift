import Cocoa
import SwiftUI

/// Shared type roles for the compact menu bar UI and its companion windows.
/// Keep the system face so text remains native to macOS in both appearances.
enum NearbyTypography {
    static let pageTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let screenTitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let sectionTitle = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let prominentBody = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 12, weight: .regular)
    static let supporting = Font.system(size: 11, weight: .regular)
    static let metadata = Font.system(size: 10, weight: .regular)
    static let emphasizedMetadata = Font.system(size: 10, weight: .medium)
    static let action = Font.system(size: 12, weight: .semibold)
}

enum PreviewRuntime {
    static var isSwiftUIPreviews: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
#else
        false
#endif
    }
}

struct NearbyCardSurface: ViewModifier {
    var cornerRadius: CGFloat = 12
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(theme.isViceNights ? ViceNightsPalette.card : (colorScheme == .light ? Color.white : Color(nsColor: .controlBackgroundColor)))
                    .overlay(shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.055 : 0)))
            }
            .overlay(shape.stroke(theme.isViceNights ? ViceNightsPalette.pink.opacity(0.20) : (colorScheme == .light ? Color(red: 0.85, green: 0.85, blue: 0.89) : Color.primary.opacity(0.08)), lineWidth: 1))
    }
}

struct NearbyControlSurface: ViewModifier {
    var cornerRadius: CGFloat = 10
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            shape
                .fill(theme.isViceNights ? ViceNightsPalette.card : Color(nsColor: .controlBackgroundColor))
                .overlay(shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.055 : 0)))
        }
    }
}

extension View {
    func nearbyCardSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(NearbyCardSurface(cornerRadius: cornerRadius))
    }

    func nearbyControlSurface(cornerRadius: CGFloat = 10) -> some View {
        modifier(NearbyControlSurface(cornerRadius: cornerRadius))
    }
}

enum NearbyButtonVariant: Equatable {
    case primary
    case secondary
    case quiet
    case destructive
}

enum NearbyButtonSize: Equatable {
    case regular
    case compact

    var minimumHeight: CGFloat { self == .regular ? 36 : 30 }
    var horizontalPadding: CGFloat { self == .regular ? 14 : 10 }
    var fontSize: CGFloat { self == .regular ? 12 : 11 }
}

struct NearbyButtonStyle: ButtonStyle {
    let variant: NearbyButtonVariant
    var size: NearbyButtonSize = .regular
    var expandsToFill = false

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    init(_ variant: NearbyButtonVariant, size: NearbyButtonSize = .regular, expandsToFill: Bool = false) {
        self.variant = variant
        self.size = size
        self.expandsToFill = expandsToFill
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: size == .regular ? 10 : 8, style: .continuous)
        configuration.label
            .frame(maxWidth: expandsToFill ? .infinity : nil)
            .font(size == .regular ? NearbyTypography.action : .system(size: size.fontSize, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.minimumHeight)
            .background {
                shape
                    .fill(fillColor(isPressed: configuration.isPressed))
                    .overlay(shape.stroke(borderColor, lineWidth: borderWidth))
            }
            .overlay {
                if isFocused {
                    shape.stroke(theme.presentationAccent.opacity(0.78), lineWidth: 2)
                }
            }
            .clipShape(shape)
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return .white
        case .secondary: return .primary
        case .quiet: return .secondary
        case .destructive: return .red
        }
    }

    private func fillColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return (theme.isViceNights ? ViceNightsPalette.button : theme.presentationAccent).opacity(isEnabled ? (isPressed ? 0.86 : 1) : 0.55)
        case .secondary:
            return Color.primary.opacity(colorScheme == .dark ? (isPressed ? 0.15 : 0.075) : (isPressed ? 0.12 : 0.045))
        case .quiet:
            return isPressed ? theme.presentationAccent.opacity(0.12) : .clear
        case .destructive:
            return Color.red.opacity(colorScheme == .dark ? (isPressed ? 0.26 : 0.18) : (isPressed ? 0.16 : 0.08))
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary, .quiet: return .clear
        case .secondary: return Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07)
        case .destructive: return Color.red.opacity(0.22)
        }
    }

    private var borderWidth: CGFloat { variant == .primary || variant == .quiet ? 0 : 1 }
}

extension ButtonStyle where Self == NearbyButtonStyle {
    static var nearbyPrimary: Self { NearbyButtonStyle(.primary) }
    static var nearbyCompactPrimary: Self { NearbyButtonStyle(.primary, size: .compact) }
    static var nearbySecondary: Self { NearbyButtonStyle(.secondary) }
    static var nearbyCompactSecondary: Self { NearbyButtonStyle(.secondary, size: .compact) }
    static var nearbyQuiet: Self { NearbyButtonStyle(.quiet) }
    static var nearbyCompactQuiet: Self { NearbyButtonStyle(.quiet, size: .compact) }
    static var nearbyDestructive: Self { NearbyButtonStyle(.destructive) }
    static var nearbyCompactDestructive: Self { NearbyButtonStyle(.destructive, size: .compact) }
    static var nearbyFullWidthPrimary: Self { NearbyButtonStyle(.primary, expandsToFill: true) }
    static var nearbyFullWidthSecondary: Self { NearbyButtonStyle(.secondary, expandsToFill: true) }
    static var nearbyCompactFullWidthPrimary: Self { NearbyButtonStyle(.primary, size: .compact, expandsToFill: true) }
    static var nearbyCompactFullWidthSecondary: Self { NearbyButtonStyle(.secondary, size: .compact, expandsToFill: true) }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case viceNights = "Vice Nights"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .viceNights: return "sun.horizon.fill"
        }
    }

    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark, .viceNights:
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
        case .blue: return Color(red: 0.16, green: 0.36, blue: 0.78)
        case .cyan: return Color(nsColor: .systemCyan)
        case .green: return Color(nsColor: .systemGreen)
        case .purple: return Color(red: 0.36, green: 0.32, blue: 0.86)
        case .orange: return Color(nsColor: .systemOrange)
        case .pink: return Color(nsColor: .systemPink)
        case .graphite: return Color(nsColor: .systemGray)
        }
    }

    var nsColor: NSColor {
        switch self {
        case .blue: return NSColor(red: 0.16, green: 0.36, blue: 0.78, alpha: 1)
        case .cyan: return .systemCyan
        case .green: return .systemGreen
        case .purple: return NSColor(red: 0.36, green: 0.32, blue: 0.86, alpha: 1)
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
    case send = "Send"
    case download = "Download"
    case share = "Share"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .quickShare: return "arrow.up.arrow.down"
        case .antenna: return "dot.radiowaves.left.and.right"
        case .paperplane: return "arrow.down.circle"
        case .send: return "paperplane"
        case .download: return "tray.and.arrow.down"
        case .share: return "square.and.arrow.up"
        }
    }

    var displayName: String {
        switch self {
        case .quickShare: return "Arrows"
        case .antenna: return "Signal"
        case .paperplane: return "Circle"
        case .send: return "Send"
        case .download: return "Download"
        case .share: return "Share"
        }
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme {
        didSet {
            guard !PreviewRuntime.isSwiftUIPreviews else { return }
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "appTheme")
            currentTheme.apply()
        }
    }

    @Published var currentAccent: AccentOption {
        didSet {
            guard !PreviewRuntime.isSwiftUIPreviews else { return }
            UserDefaults.standard.set(currentAccent.rawValue, forKey: "appAccent")
        }
    }

    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet {
            guard !PreviewRuntime.isSwiftUIPreviews else { return }
            UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: "menuBarIconStyle")
            onMenuBarIconChanged?()
        }
    }

#if DEBUG
    @Published private(set) var figmaPreviewAccent: AccentOption?
    @Published var screenshotTheme: AppTheme?
#endif

    var onMenuBarIconChanged: (() -> Void)?

    var presentationAccentOption: AccentOption {
#if DEBUG
        figmaPreviewAccent ?? currentAccent
#else
        currentAccent
#endif
    }

    var isViceNights: Bool {
#if DEBUG
        (screenshotTheme ?? currentTheme) == .viceNights
#else
        currentTheme == .viceNights
#endif
    }

    var presentationAccent: Color { isViceNights ? ViceNightsPalette.pink : presentationAccentOption.color }
    var windowSurface: Color { isViceNights ? ViceNightsPalette.background : Color(nsColor: .windowBackgroundColor) }

    func applyViceNightsEditionIfNeeded(_ isEdition: Bool) {
        guard isEdition, !PreviewRuntime.isSwiftUIPreviews,
              !UserDefaults.standard.bool(forKey: "hasOpenedViceNightsEdition") else { return }
        currentTheme = .viceNights
        UserDefaults.standard.set(true, forKey: "hasOpenedViceNightsEdition")
    }

#if DEBUG
    func useFigmaPreviewPalette() {
        figmaPreviewAccent = .blue
    }
#endif

    private init() {
        if PreviewRuntime.isSwiftUIPreviews {
            self.currentTheme = .system
            self.currentAccent = .blue
            self.menuBarIconStyle = .quickShare
            return
        }

        let savedTheme = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue
        self.currentTheme = AppTheme(rawValue: savedTheme) ?? .system

        let savedAccent = UserDefaults.standard.string(forKey: "appAccent") ?? AccentOption.blue.rawValue
        self.currentAccent = AccentOption(rawValue: savedAccent) ?? .blue

        let savedIcon = UserDefaults.standard.string(forKey: "menuBarIconStyle") ?? MenuBarIconStyle.quickShare.rawValue
        self.menuBarIconStyle = MenuBarIconStyle(rawValue: savedIcon) ?? .quickShare

        currentTheme.apply()
    }

    func menuBarImage() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: menuBarIconStyle.sfSymbol, accessibilityDescription: "Nearby Drop")?
            .withSymbolConfiguration(config)
    }
}

#if DEBUG
struct FigmaCanvasPreview<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        ThemeManager.shared.useFigmaPreviewPalette()
        self.content = content()
    }

    var body: some View {
        content
    }
}
#endif

final class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()

    @Published var soundEnabled: Bool {
        didSet {
            guard !PreviewRuntime.isSwiftUIPreviews else { return }
            UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
        }
    }

    @Published var hapticsEnabled: Bool {
        didSet {
            guard !PreviewRuntime.isSwiftUIPreviews else { return }
            UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
        }
    }

    init() {
        if PreviewRuntime.isSwiftUIPreviews {
            self.soundEnabled = true
            self.hapticsEnabled = true
            return
        }

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

// Original sunset palette and vector artwork; no third-party game assets.
enum ViceNightsPalette {
    static let background = Color(red: 0.075, green: 0.045, blue: 0.12)
    static let card = Color(red: 0.14, green: 0.09, blue: 0.20)
    static let pink = Color(red: 1.0, green: 0.60, blue: 0.77)
    static let cyan = Color(red: 0.39, green: 0.89, blue: 0.91)
    static let button = Color(red: 0.68, green: 0.10, blue: 0.34)
}

struct ViceNightsHeader: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            // Keep the left side quiet behind the app name and device name.
            let horizon = CGPoint(x: size.width * 0.78, y: size.height * 0.45)
            let sun = CGRect(x: horizon.x - 25, y: horizon.y - 25, width: 50, height: 50)
            context.fill(Path(ellipseIn: sun), with: .linearGradient(
                Gradient(colors: [ViceNightsPalette.pink, Color(red: 1, green: 0.48, blue: 0.30)]),
                startPoint: CGPoint(x: sun.midX, y: sun.minY), endPoint: CGPoint(x: sun.midX, y: sun.maxY)))
            for offset in [0.0, 7.0, 15.0] {
                let stripe = CGRect(x: sun.minX, y: sun.midY + offset, width: sun.width, height: 3)
                context.fill(Path(stripe), with: .color(ViceNightsPalette.background))
            }
            for (x, scale) in [(0.92, 1.0), (0.63, 0.65)] {
                let crown = CGPoint(x: size.width * x, y: size.height * (1 - 0.74 * scale))
                var trunk = Path()
                trunk.move(to: CGPoint(x: crown.x - 9 * scale, y: size.height))
                trunk.addQuadCurve(to: crown, control: CGPoint(x: crown.x + 2, y: size.height * 0.6))
                context.stroke(trunk, with: .color(ViceNightsPalette.cyan.opacity(0.55)), lineWidth: 3 * scale)
                for angle in [-2.9, -2.3, -1.6, -0.9, -0.25, 0.4] {
                    var frond = Path()
                    frond.move(to: crown)
                    let end = CGPoint(x: crown.x + cos(angle) * 28 * scale, y: crown.y + sin(angle) * 18 * scale + 10 * scale)
                    frond.addQuadCurve(to: end, control: CGPoint(x: (crown.x + end.x) / 2, y: min(crown.y, end.y) - 13 * scale))
                    context.stroke(frond, with: .color(ViceNightsPalette.cyan.opacity(0.55)), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                }
            }
        }
        .opacity(contrast == .increased ? 0.12 : 0.32)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
