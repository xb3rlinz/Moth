import SwiftUI
import UIKit

// MARK: - Design tokens
//
// Every colour, spacing value, radius and animation used by the app lives here, so the
// interface is styled in one place instead of screen by screen. The palette is defined in
// code (not an asset catalog) so the project keeps building exactly as before.

enum Theme {

    // MARK: Palette
    //
    // A warm neutral base with one accent ("moonlight indigo"), plus a red reserved for
    // overdue work. Both appearances are defined together and adapt automatically.

    static let accentUI = UIColor.adaptive(
        light: UIColor(red: 0.314, green: 0.329, blue: 0.800, alpha: 1),     // #5054CC, 6.0:1 on white
        dark: UIColor(red: 0.565, green: 0.588, blue: 1.000, alpha: 1))      // #9096FF, 7.0:1 on the dark base

    /// Text and glyphs drawn on top of a solid accent fill.
    static let onAccentUI = UIColor.adaptive(
        light: .white,
        dark: UIColor(red: 0.055, green: 0.055, blue: 0.067, alpha: 1))

    static let dangerUI = UIColor.adaptive(
        light: UIColor(red: 0.757, green: 0.149, blue: 0.129, alpha: 1),     // #C12621, 5.9:1 on white
        dark: UIColor(red: 1.000, green: 0.420, blue: 0.388, alpha: 1))

    static let backgroundUI = UIColor.adaptive(
        light: UIColor(red: 0.961, green: 0.957, blue: 0.941, alpha: 1),     // warm paper
        dark: UIColor(red: 0.055, green: 0.055, blue: 0.067, alpha: 1))      // ink

    static let surfaceUI = UIColor.adaptive(
        light: .white,
        dark: UIColor(red: 0.102, green: 0.102, blue: 0.122, alpha: 1))

    static let mutedUI = UIColor.adaptive(
        light: UIColor(white: 0, alpha: 0.06),
        dark: UIColor(white: 1, alpha: 0.10))

    static let accent = Color(uiColor: accentUI)
    static let onAccent = Color(uiColor: onAccentUI)
    static let danger = Color(uiColor: dangerUI)
    static let background = Color(uiColor: backgroundUI)
    static let surface = Color(uiColor: surfaceUI)
    /// Quiet neutral fill for chips and image placeholders.
    static let muted = Color(uiColor: mutedUI)
    static let hairline = Color(uiColor: .separator)

    // MARK: Spacing

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radii

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 14
        static let large: CGFloat = 22
    }

    // MARK: Sizes

    enum Size {
        /// Minimum size of anything the user taps.
        static let tapTarget: CGFloat = 44
        static let chipHeight: CGFloat = 36
        static let rowInset: CGFloat = 20
        /// Leading inset of rows that start with the 44pt completion control. The circle glyph
        /// sits about 10pt inside its tap target, so this lines the glyph up with `rowInset`.
        static let checkRowInset: CGFloat = 10
    }
}

private extension UIColor {
    static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }
}

// MARK: - Typography
//
// Native system text styles only, so everything scales with Dynamic Type.

extension Font {
    static let mothRowTitle = Font.body.weight(.medium)
    static let mothRowMeta = Font.subheadline
    static let mothSectionTitle = Font.subheadline.weight(.semibold)
    static let mothCaption = Font.footnote
}

// MARK: - Motion

enum Motion {
    /// Used for state changes: completing, filtering, expanding.
    static let standard = Animation.snappy(duration: 0.30)
    /// Used for larger layout changes.
    static let gentle = Animation.smooth(duration: 0.40)
}

/// `withAnimation` that does nothing when the user has asked for reduced motion.
func withMotion<Result>(_ reduceMotion: Bool,
                        _ animation: Animation = Motion.standard,
                        _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(reduceMotion ? nil : animation, body)
}

// MARK: - Layout helpers

private struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let maxWidth: CGFloat

    init(maxWidth: CGFloat) { self.maxWidth = maxWidth }

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Keeps lists and forms at a comfortable reading width on iPad and other wide layouts.
    func readableWidth(_ maxWidth: CGFloat = 760) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }

    /// The warm base colour behind every screen.
    func mothBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
