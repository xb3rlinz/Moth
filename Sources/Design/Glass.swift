import SwiftUI

// MARK: - Glass surfaces
//
// Liquid Glass is used only for small floating controls (filter chips, photo controls,
// secondary buttons) and never for content rows or forms.
//
// - iOS 26 and later, built with the iOS 26 SDK (Xcode 26 / Swift 6.2): native `glassEffect`.
// - Everything else (iOS 17 to 25, or a build made with an older SDK): a system material or a
//   quiet neutral fill, so nothing depends on a newer SDK to compile or to stay legible.
// - Reduce Transparency always gets the opaque-leaning fallback.
//
// The `#if compiler(>=6.2)` guard matters: the iOS 26 symbols do not exist in older SDKs, so
// without it the project would fail to compile on an older Xcode. Raising the deployment
// target is not needed and was deliberately avoided.

/// How a glass surface looks where native Liquid Glass is unavailable.
enum GlassFallback {
    /// A translucent blur with a hairline edge, for controls floating over content.
    case material
    /// A quiet neutral (or tinted) fill, for controls resting on the plain background.
    case fill
}

struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let fallback: GlassFallback

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(shape: S, tint: Color?, interactive: Bool, fallback: GlassFallback) {
        self.shape = shape
        self.tint = tint
        self.interactive = interactive
        self.fallback = fallback
    }

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if reduceTransparency {
                fallbackSurface(content)
            } else {
                nativeGlass(content)
            }
        } else {
            fallbackSurface(content)
        }
        #else
        fallbackSurface(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    @ViewBuilder
    private func nativeGlass(_ content: Content) -> some View {
        content.glassEffect(glassStyle, in: shape)
    }

    @available(iOS 26.0, *)
    private var glassStyle: Glass {
        var style = Glass.regular
        if let tint { style = style.tint(tint) }
        if interactive { style = style.interactive() }
        return style
    }
    #endif

    @ViewBuilder
    private func fallbackSurface(_ content: Content) -> some View {
        switch fallback {
        case .material:
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 0.5) }
        case .fill:
            content
                .background(fillColor, in: shape)
        }
    }

    private var fillColor: Color {
        if let tint { return tint.opacity(0.14) }
        return Theme.muted
    }
}

extension View {
    /// Gives a small floating control a glass surface. See `GlassSurface`.
    func glassSurface<S: InsettableShape>(in shape: S,
                                          tint: Color? = nil,
                                          interactive: Bool = false,
                                          fallback: GlassFallback = .material) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive, fallback: fallback))
    }
}

// MARK: - Bar background

private struct ScrollingBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Native glass chips float over the list; no bar is needed behind them.
            content
        } else {
            content.background(.bar)
        }
        #else
        content.background(.bar)
        #endif
    }
}

extension View {
    /// The backing for a control bar that sits above scrolling content: transparent where
    /// glass controls float on their own, the standard bar material elsewhere.
    func scrollingBarBackground() -> some View {
        modifier(ScrollingBarBackground())
    }
}

// MARK: - Buttons

/// The app's button style. `.prominent` is a solid accent capsule for the one main action on a
/// screen; `.quiet` is a glass capsule for secondary actions.
struct MothButtonStyle: ButtonStyle {
    enum Kind { case prominent, quiet }

    let kind: Kind

    init(kind: Kind = .prominent) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.m)
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Capsule())

        switch kind {
        case .prominent:
            label
                .foregroundStyle(Theme.onAccent)
                .background(Capsule().fill(Theme.accent))
                .opacity(configuration.isPressed ? 0.82 : 1)
        case .quiet:
            label
                .foregroundStyle(Theme.accent)
                .glassSurface(in: Capsule(), interactive: true, fallback: .fill)
                .opacity(configuration.isPressed ? 0.82 : 1)
        }
    }
}
