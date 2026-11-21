#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
# Exercise shipping theme code without touching the owner's appearance preferences.
python3 - "$root/NearByDrop/ThemeManager.swift" "$workspace/main.swift" <<'PY'
import sys
source = open(sys.argv[1]).read().replace('UserDefaults.standard', 'testDefaults')
pre = '''import Cocoa
import SwiftUI
let suite = "NearbyDrop.ThemeTest." + UUID().uuidString
let testDefaults = UserDefaults(suiteName: suite)!
'''
post = r'''
let app = NSApplication.shared
defer { testDefaults.removePersistentDomain(forName: suite) }
let theme = ThemeManager.shared
theme.currentAccent = .orange
theme.currentTheme = .viceNights
precondition(theme.isViceNights)
precondition(testDefaults.string(forKey: "appTheme") == "Vice Nights")
precondition(app.appearance?.name == .darkAqua)
precondition(theme.currentAccent == .orange)
theme.currentTheme = .light
precondition(!theme.isViceNights)
precondition(app.appearance?.name == .aqua)
precondition(theme.presentationAccentOption == .orange)
theme.currentTheme = .system
precondition(app.appearance == nil)
precondition(!theme.isViceNights)

theme.applyViceNightsEditionIfNeeded(false)
precondition(theme.currentTheme == .system)
theme.applyViceNightsEditionIfNeeded(true)
precondition(theme.isViceNights)
theme.currentTheme = .light
theme.applyViceNightsEditionIfNeeded(true)
precondition(theme.currentTheme == .light)
precondition(theme.currentAccent == .orange)

func luminance(_ color: Color) -> Double {
    let rgb = NSColor(color).usingColorSpace(.sRGB)!
    func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
}
for appearance in AppTheme.allCases {
    theme.currentTheme = appearance
    precondition(testDefaults.string(forKey: "appTheme") == appearance.rawValue)
    guard let palette = appearance.palette else { continue }
    func ratio(_ a: Color, _ b: Color) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    for surface in [palette.background, palette.surface] {
        precondition(ratio(palette.text, surface) >= 4.5, "Primary text contrast: \(appearance)")
        precondition(ratio(palette.secondaryText, surface) >= 4.5, "Secondary text contrast: \(appearance)")
        precondition(ratio(palette.accent, surface) >= 4.5, "Accent text contrast: \(appearance)")
        precondition(ratio(palette.error, surface) >= 4.5, "Error contrast: \(appearance)")
        precondition(ratio(palette.success, surface) >= 4.5, "Success contrast: \(appearance)")
    }
    precondition(ratio(.white, palette.button) >= 4.5, "Button contrast: \(appearance)")
    print("Appearance persistence and contrast passed: \(appearance.rawValue)")
}
print("Edition preset respects later user choices; standard appearances retained.")
'''
open(sys.argv[2], 'w').write(pre + source + post)
PY
swiftc "$workspace/main.swift" -o "$workspace/theme-check"
"$workspace/theme-check"
