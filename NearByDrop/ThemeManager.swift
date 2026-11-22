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
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(theme.cardSurface)
                    .overlay {
                        if theme.isCustom {
                            shape.fill(LinearGradient(colors: [theme.signalColor.opacity(0.07), .clear], startPoint: .topTrailing, endPoint: .bottomLeading))
                        }
                    }
            }
            .overlay(shape.stroke(contrast == .increased ? theme.primaryText.opacity(0.65) : theme.surfaceBorder, lineWidth: 1))
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
                .fill(theme.cardSurface)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

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
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return .white
        case .secondary: return theme.primaryText
        case .quiet: return theme.secondaryText
        case .destructive: return theme.errorColor
        }
    }

    private func fillColor(isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return theme.buttonFill.opacity(isEnabled ? (isPressed ? 0.86 : (hovering ? 0.92 : 1)) : 0.55)
        case .secondary:
            return theme.presentationAccent.opacity(isPressed ? 0.20 : (hovering ? 0.14 : 0.08))
        case .quiet:
            return isPressed || hovering ? theme.presentationAccent.opacity(0.12) : .clear
        case .destructive:
            return theme.errorColor.opacity(colorScheme == .dark ? (isPressed ? 0.26 : 0.18) : (isPressed ? 0.16 : 0.08))
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
    case coastalSunrise = "Coastal Sunrise"
    case midnightRoute = "Midnight Route"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .viceNights: return "sun.horizon.fill"
        case .coastalSunrise: return "sun.max.fill"
        case .midnightRoute: return "road.lanes"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .coastalSunrise: return .light
        case .dark, .viceNights, .midnightRoute: return .dark
        }
    }

    func apply() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light, .coastalSunrise:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark, .viceNights, .midnightRoute:
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

    var resolvedTheme: AppTheme {
#if DEBUG
        screenshotTheme ?? currentTheme
#else
        currentTheme
#endif
    }
    var isViceNights: Bool { resolvedTheme == .viceNights }
    var palette: NearbyThemePalette? { resolvedTheme.palette }
    var isCustom: Bool { palette != nil }
    var presentationAccent: Color { palette?.accent ?? presentationAccentOption.color }
    var windowSurface: Color { palette?.background ?? Color(nsColor: .windowBackgroundColor) }
    var cardSurface: Color { palette?.surface ?? Color(nsColor: .controlBackgroundColor) }
    var primaryText: Color { palette?.text ?? .primary }
    var secondaryText: Color { palette?.secondaryText ?? .secondary }
    func navigationText(selected: Bool) -> Color {
        selected ? presentationAccent : secondaryText
    }
    var surfaceBorder: Color { palette?.border ?? Color.primary.opacity(0.12) }
    var buttonFill: Color { palette?.button ?? presentationAccent }
    var successColor: Color { palette?.success ?? .green }
    var errorColor: Color { palette?.error ?? .red }
    var signalColor: Color { palette?.signal ?? presentationAccent }

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
            Self.draw(in: &context, size: size)
        }
        .opacity(contrast == .increased ? 0.12 : 0.32)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Bound type inference for the older compiler used by the Intel runner.
    private static func draw(in context: inout GraphicsContext, size: CGSize) {
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
        let palms: [(CGFloat, CGFloat)] = [(0.92, 1.0), (0.63, 0.65)]
        let angles: [CGFloat] = [-2.9, -2.3, -1.6, -0.9, -0.25, 0.4]
        for (x, scale) in palms {
            let crown = CGPoint(x: size.width * x, y: size.height * (1 - 0.74 * scale))
            var trunk = Path()
            trunk.move(to: CGPoint(x: crown.x - 9 * scale, y: size.height))
            trunk.addQuadCurve(to: crown, control: CGPoint(x: crown.x + 2, y: size.height * 0.6))
            context.stroke(trunk, with: .color(ViceNightsPalette.cyan.opacity(0.55)), lineWidth: 3 * scale)
            for angle in angles {
                var frond = Path()
                frond.move(to: crown)
                let end = CGPoint(x: crown.x + cos(angle) * 28 * scale, y: crown.y + sin(angle) * 18 * scale + 10 * scale)
                frond.addQuadCurve(to: end, control: CGPoint(x: (crown.x + end.x) / 2, y: min(crown.y, end.y) - 13 * scale))
                context.stroke(frond, with: .color(ViceNightsPalette.cyan.opacity(0.55)), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
            }
        }
    }
}

/// Complete palettes share native controls; only the content treatment changes.
struct NearbyThemePalette {
    let background: Color
    let surface: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let signal: Color
    let button: Color
    let border: Color
    let success: Color
    let error: Color

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }

    init(background: UInt32, surface: UInt32, text: UInt32, secondary: UInt32,
         accent: UInt32, signal: UInt32, button: UInt32, border: UInt32, success: UInt32, error: UInt32) {
        self.background = Self.color(background); self.surface = Self.color(surface)
        self.text = Self.color(text); self.secondaryText = Self.color(secondary)
        self.accent = Self.color(accent); self.signal = Self.color(signal)
        self.button = Self.color(button); self.border = Self.color(border)
        self.success = Self.color(success); self.error = Self.color(error)
    }
}

extension AppTheme {
    var palette: NearbyThemePalette? {
        switch self {
        case .system, .light, .dark: return nil
        case .viceNights:
            return NearbyThemePalette(background: 0x120D21, surface: 0x20162D, text: 0xF9F6FE, secondary: 0xCDBEDB,
                                      accent: 0xFF93BF, signal: 0x6AE4EC, button: 0xAC1957, border: 0x78506B, success: 0x8CE4BD, error: 0xFFABA9)
        case .coastalSunrise:
            return NearbyThemePalette(background: 0xFFF0DF, surface: 0xFFFAF3, text: 0x352835, secondary: 0x68505D,
                                      accent: 0x9A3455, signal: 0x226778, button: 0x226778, border: 0xBE9197, success: 0x226544, error: 0xA22432)
        case .midnightRoute:
            return NearbyThemePalette(background: 0x0B1724, surface: 0x162838, text: 0xF3F7FC, secondary: 0xB6CBDA,
                                      accent: 0x70DADD, signal: 0xF5A66F, button: 0x17626C, border: 0x456B80, success: 0x85D8AF, error: 0xFFAAA5)
        }
    }

    var subtitle: String {
        switch self {
        case .viceNights: return "Sunset pink. Ocean cyan. After-dark palms."
        case .coastalSunrise: return "Warm cream. Tropical teal. A softer morning."
        case .midnightRoute: return "Midnight navy. Cyan signals. Clear passage."
        default: return "Familiar macOS appearance."
        }
    }
}

struct NearbyThemeArtwork: View {
    let appearance: AppTheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if appearance == .viceNights { ViceNightsHeader() }
            else if let palette = appearance.palette {
                Canvas { context, size in
                    if appearance == .coastalSunrise {
                        let sun = CGRect(x: size.width * 0.77, y: -10, width: 70, height: 70)
                        context.fill(Path(ellipseIn: sun), with: .color(Color(red: 0.97, green: 0.65, blue: 0.42)))
                        for row in 0..<3 {
                            var wave = Path(); let y = size.height * 0.55 + Double(row) * 12
                            wave.move(to: CGPoint(x: size.width * 0.5, y: y))
                            wave.addCurve(to: CGPoint(x: size.width, y: y), control1: CGPoint(x: size.width * 0.65, y: y - 22), control2: CGPoint(x: size.width * 0.82, y: y + 22))
                            context.stroke(wave, with: .color(palette.signal), lineWidth: 2)
                        }
                    } else {
                        for row in 0..<4 {
                            var route = Path()
                            route.move(to: CGPoint(x: size.width * (0.55 + Double(row) * 0.12), y: size.height))
                            route.addLine(to: CGPoint(x: size.width * 0.86, y: 0))
                            context.stroke(route, with: .color(row == 2 ? palette.signal : palette.accent), style: StrokeStyle(lineWidth: 1.5, dash: row == 2 ? [4, 5] : []))
                        }
                    }
                }
                .opacity(contrast == .increased ? 0.08 : 0.19)
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct NearbyWindowSurface: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var inheritedScheme
    func body(content: Content) -> some View {
        content.foregroundStyle(theme.primaryText)
            .tint(theme.presentationAccent)
            .background(theme.windowSurface)
            .environment(\.colorScheme, theme.resolvedTheme.colorScheme ?? inheritedScheme)
            .preferredColorScheme(theme.resolvedTheme.colorScheme)
    }
}

extension View {
    func nearbyThemedWindow() -> some View { modifier(NearbyWindowSurface()) }
}

struct NearbyCardFocus: ViewModifier {
    @FocusState private var focused: Bool
    @ObservedObject private var theme = ThemeManager.shared
    func body(content: Content) -> some View {
        content.focused($focused).overlay {
            if focused { RoundedRectangle(cornerRadius: 10).stroke(theme.presentationAccent, lineWidth: 2).allowsHitTesting(false) }
        }
    }
}
extension View {
    func nearbyCardFocus() -> some View { modifier(NearbyCardFocus()) }
}
