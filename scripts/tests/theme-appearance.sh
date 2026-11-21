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
post = '''
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
let pinkContrast = (luminance(ViceNightsPalette.pink) + 0.05) / (luminance(ViceNightsPalette.card) + 0.05)
let buttonContrast = 1.05 / (luminance(ViceNightsPalette.button) + 0.05)
precondition(pinkContrast >= 4.5)
precondition(buttonContrast >= 4.5)
print(String(format: "Theme persistence/restoration passed; pink text %.2f:1, button text %.2f:1", pinkContrast, buttonContrast))
'''
open(sys.argv[2], 'w').write(pre + source + post)
PY
swiftc "$workspace/main.swift" -o "$workspace/theme-check"
"$workspace/theme-check"
