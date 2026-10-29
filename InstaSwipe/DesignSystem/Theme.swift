import SwiftUI
import UIKit

/// "Aura" design tokens: brand colors are the same in light and dark, neutrals adapt.
enum Theme {
    // MARK: Brand

    static let purple = Color(hex: 0x8A2BE8)
    static let pink = Color(hex: 0xE8307A)
    static let orange = Color(hex: 0xFF8F2E)
    static let red = Color(hex: 0xEE3B4F)
    static let green = Color(hex: 0x0E9F7A)
    static let greenLight = Color(hex: 0x12B88D)
    static let warningText = Color(hex: 0xE07A00)
    static let warningFill = Color(hex: 0xF59E0B)

    // MARK: Neutrals

    static let bg = Color(light: 0xFAF8FC, dark: 0x0F0C14)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1722)
    static let surface2 = Color(light: 0xF1EEF5, dark: 0x272130)
    static let ink = Color(light: 0x1E1528, dark: 0xF5F2F8)
    static let ink2 = Color(light: 0x6F6780, dark: 0xA39BB0)
    static let line = Color(uiColor: .dynamic(
        light: UIColor(hex: 0x1E1528, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.09)
    ))
    static let shadow = Color(uiColor: .dynamic(
        light: UIColor(hex: 0x3C145A, alpha: 0.10), dark: UIColor(white: 0, alpha: 0.45)
    ))
    static let tabBarBackground = UIColor.dynamic(
        light: UIColor(hex: 0xFAF8FC, alpha: 0.86), dark: UIColor(hex: 0x0F0C14, alpha: 0.86)
    )

    // MARK: Gradients

    /// CSS `linear-gradient(120deg, purple, pink 55%, orange)`.
    static let brandGradient = LinearGradient(
        stops: [.init(color: purple, location: 0), .init(color: pink, location: 0.55), .init(color: orange, location: 1)],
        startPoint: UnitPoint(x: 0.07, y: 0.25),
        endPoint: UnitPoint(x: 0.93, y: 0.75)
    )
    static let wordmarkGradient = LinearGradient(colors: [pink, orange], startPoint: .leading, endPoint: .trailing)
    static let offlineCardGradient = LinearGradient(
        colors: [Color(hex: 0x5B5566), Color(hex: 0x8D8698)], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Stable per-account gradient for avatars and photo placeholders (Swift's `hashValue` changes per launch).
    static func accountGradient(for username: String) -> LinearGradient {
        let seed = username.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(seed % 360) / 360
        let second = (hue + 40.0 / 360).truncatingRemainder(dividingBy: 1)
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.62, brightness: 0.78),
                Color(hue: second, saturation: 0.48, brightness: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography

enum OutfitWeight: String {
    case regular = "Regular"
    case medium = "Medium"
    case semibold = "SemiBold"
    case bold = "Bold"
    case extraBold = "ExtraBold"

    var postScriptName: String { "Outfit-\(rawValue)" }
}

extension Font {
    static func outfit(_ size: CGFloat, _ weight: OutfitWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }
}

extension UIFont {
    static func outfit(_ size: CGFloat, _ weight: OutfitWeight = .regular) -> UIFont {
        UIFont(name: weight.postScriptName, size: size) ?? .systemFont(ofSize: size)
    }
}

extension View {
    /// CSS-style letter spacing expressed as a fraction of the font size (e.g. -0.02 = -2%).
    func tracking(_ fraction: CGFloat, size: CGFloat) -> some View {
        tracking(fraction * size)
    }

    /// The shared "shadow" token: `0 10 28` in CSS.
    func themeShadow() -> some View {
        shadow(color: Theme.shadow, radius: 14, y: 10)
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: .dynamic(light: UIColor(hex: light), dark: UIColor(hex: dark)))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

// MARK: - UIKit chrome

enum AppAppearance {
    /// Tab bar and navigation bars are UIKit: style them once at launch.
    @MainActor static func configure() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithTransparentBackground()
        tabBar.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        tabBar.backgroundColor = Theme.tabBarBackground
        tabBar.shadowColor = UIColor(Theme.line)
        for layout in [tabBar.stackedLayoutAppearance, tabBar.inlineLayoutAppearance, tabBar.compactInlineLayoutAppearance] {
            layout.normal.iconColor = UIColor(Theme.ink2)
            layout.normal.titleTextAttributes = [.font: UIFont.outfit(10.5, .medium), .foregroundColor: UIColor(Theme.ink2)]
            layout.selected.iconColor = UIColor(Theme.pink)
            layout.selected.titleTextAttributes = [.font: UIFont.outfit(10.5, .medium), .foregroundColor: UIColor(Theme.pink)]
            layout.normal.badgeBackgroundColor = UIColor(Theme.red)
            layout.normal.badgeTextAttributes = [.font: UIFont.outfit(11, .bold), .foregroundColor: UIColor.white]
        }
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navBar = UINavigationBarAppearance()
        navBar.configureWithDefaultBackground()
        navBar.titleTextAttributes = [.font: UIFont.outfit(17, .semibold)]
        navBar.largeTitleTextAttributes = [.font: UIFont.outfit(32, .bold)]
        let barButton = UIBarButtonItemAppearance()
        barButton.normal.titleTextAttributes = [.font: UIFont.outfit(17, .medium)]
        navBar.buttonAppearance = barButton
        navBar.doneButtonAppearance = barButton
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
    }
}
