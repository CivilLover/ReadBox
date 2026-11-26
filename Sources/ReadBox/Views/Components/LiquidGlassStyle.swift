import SwiftUI

// MARK: - Environment & Theme Helpers

private struct ReadBoxGlassPreferencesKey: EnvironmentKey {
    static let defaultValue = LiquidGlassPreferences.standard
}

public extension EnvironmentValues {
    var readBoxGlassPreferences: LiquidGlassPreferences {
        get { self[ReadBoxGlassPreferencesKey.self] }
        set { self[ReadBoxGlassPreferencesKey.self] = newValue }
    }
}

public extension AppAppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public extension LiquidGlassAmbientTheme {
    var accentColor: Color {
        switch self {
        case .ocean: return .blue
        case .graphite: return Color(red: 0.48, green: 0.52, blue: 0.58)
        case .aurora: return .purple
        case .forest: return .teal
        case .warmPaper: return .orange
        }
    }

    var secondaryColor: Color {
        switch self {
        case .ocean: return .indigo
        case .graphite: return Color(red: 0.36, green: 0.40, blue: 0.46)
        case .aurora: return .pink
        case .forest: return .mint
        case .warmPaper: return Color(red: 0.88, green: 0.64, blue: 0.34)
        }
    }

    func baseGradientColors(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            switch self {
            case .ocean:
                return [
                    Color(red: 0.08, green: 0.09, blue: 0.13),
                    Color(red: 0.07, green: 0.08, blue: 0.11),
                    Color(red: 0.09, green: 0.09, blue: 0.14)
                ]
            case .graphite:
                return [
                    Color(red: 0.09, green: 0.09, blue: 0.10),
                    Color(red: 0.08, green: 0.08, blue: 0.09),
                    Color(red: 0.10, green: 0.10, blue: 0.11)
                ]
            case .aurora:
                return [
                    Color(red: 0.10, green: 0.08, blue: 0.14),
                    Color(red: 0.08, green: 0.07, blue: 0.12),
                    Color(red: 0.12, green: 0.08, blue: 0.13)
                ]
            case .forest:
                return [
                    Color(red: 0.07, green: 0.10, blue: 0.10),
                    Color(red: 0.06, green: 0.09, blue: 0.09),
                    Color(red: 0.08, green: 0.11, blue: 0.10)
                ]
            case .warmPaper:
                return [
                    Color(red: 0.12, green: 0.10, blue: 0.09),
                    Color(red: 0.10, green: 0.09, blue: 0.08),
                    Color(red: 0.13, green: 0.11, blue: 0.09)
                ]
            }
        } else {
            switch self {
            case .ocean:
                return [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.93, green: 0.95, blue: 0.99)
                ]
            case .graphite:
                return [
                    Color(red: 0.95, green: 0.95, blue: 0.96),
                    Color(red: 0.96, green: 0.96, blue: 0.97),
                    Color(red: 0.94, green: 0.94, blue: 0.95)
                ]
            case .aurora:
                return [
                    Color(red: 0.96, green: 0.94, blue: 0.99),
                    Color(red: 0.97, green: 0.95, blue: 0.98),
                    Color(red: 0.95, green: 0.93, blue: 0.99)
                ]
            case .forest:
                return [
                    Color(red: 0.93, green: 0.97, blue: 0.96),
                    Color(red: 0.95, green: 0.98, blue: 0.97),
                    Color(red: 0.92, green: 0.96, blue: 0.95)
                ]
            case .warmPaper:
                return [
                    Color(red: 0.98, green: 0.96, blue: 0.93),
                    Color(red: 0.99, green: 0.97, blue: 0.94),
                    Color(red: 0.97, green: 0.95, blue: 0.91)
                ]
            }
        }
    }
}

// MARK: - Configurable Liquid Glass Surface Modifier

private struct ReadBoxGlassSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.readBoxGlassPreferences) private var prefs
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let interactive: Bool
    let explicitTint: Color?

    private var resolvedTint: Color? {
        if let explicitTint { return explicitTint }
        if prefs.glassTintOpacity > 0.005 {
            return prefs.ambientTheme.accentColor.opacity(prefs.glassTintOpacity)
        }
        return nil
    }

    private var rimStroke: some View {
        let strength = prefs.rimHighlightOpacity
        let topOpacity = (colorScheme == .dark ? 0.34 : 0.65) * strength
        let bottomOpacity = (colorScheme == .dark ? 0.08 : 0.16) * strength
        return shape.stroke(
            LinearGradient(
                colors: [.white.opacity(topOpacity), .white.opacity(bottomOpacity)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: strength > 0.02 ? 1 : 0
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch prefs.materialStyle {
        case .regular:
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                applyNativeGlass(to: content, base: .regular)
                    .overlay(rimStroke.allowsHitTesting(false))
            } else {
                frostedFallback(content)
            }
            #else
            frostedFallback(content)
            #endif
        case .clear:
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                applyNativeGlass(to: content, base: .clear)
                    .overlay(rimStroke.allowsHitTesting(false))
            } else {
                frostedFallback(content, clear: true)
            }
            #else
            frostedFallback(content, clear: true)
            #endif
        case .frosted:
            frostedFallback(content)
        case .solid:
            content
                .background(
                    ZStack {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                        if let tint = resolvedTint {
                            shape.fill(tint.opacity(0.45))
                        }
                    }
                )
                .overlay(
                    shape.stroke(Color.primary.opacity(0.09 + 0.08 * prefs.rimHighlightOpacity), lineWidth: 1)
                        .allowsHitTesting(false)
                )
        }
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    @ViewBuilder
    private func applyNativeGlass(to content: Content, base: Glass) -> some View {
        if let tint = resolvedTint {
            if interactive {
                content.glassEffect(base.tint(tint).interactive(), in: shape)
            } else {
                content.glassEffect(base.tint(tint), in: shape)
            }
        } else {
            if interactive {
                content.glassEffect(base.interactive(), in: shape)
            } else {
                content.glassEffect(base, in: shape)
            }
        }
    }
    #endif

    @ViewBuilder
    private func frostedFallback(_ content: Content, clear: Bool = false) -> some View {
        content
            .background {
                ZStack {
                    if clear {
                        shape.fill(.ultraThinMaterial)
                            .opacity(0.75)
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                    if let tint = resolvedTint {
                        shape.fill(tint)
                    }
                }
            }
            .overlay(rimStroke.allowsHitTesting(false))
    }
}

private struct ReadBoxGlassCardModifier: ViewModifier {
    @Environment(\.readBoxGlassPreferences) private var prefs
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let rimStrength = prefs.rimHighlightOpacity
        let useGlass = prefs.cardTranslucent && prefs.materialStyle != .solid

        content
            .background {
                if useGlass {
                    ZStack {
                        if prefs.materialStyle == .clear {
                            shape.fill(.ultraThinMaterial).opacity(0.68)
                        } else if prefs.materialStyle == .frosted {
                            shape.fill(.regularMaterial)
                        } else {
                            shape.fill(.ultraThinMaterial)
                        }
                        if isSelected {
                            shape.fill(Color.accentColor.opacity(0.14))
                        } else if prefs.glassTintOpacity > 0.005 {
                            shape.fill(prefs.ambientTheme.accentColor.opacity(prefs.glassTintOpacity * 0.55))
                        }
                    }
                } else {
                    ZStack {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                        if isSelected {
                            shape.fill(Color.accentColor.opacity(0.12))
                        }
                    }
                }
            }
            .overlay(
                shape.stroke(
                    isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(LinearGradient(
                        colors: [
                            (colorScheme == .dark ? Color.white : Color.white)
                                .opacity((isHovered ? 0.44 : 0.24) * max(0.15, rimStrength)),
                            Color.primary.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )),
                    lineWidth: isSelected ? 2 : 1
                )
                .allowsHitTesting(false)
            )
            .clipShape(shape)
            .shadow(
                color: .black.opacity(isHovered ? 0.14 : (useGlass ? 0.05 : 0.03)),
                radius: isHovered ? 12 : 4,
                y: isHovered ? 4 : 2
            )
    }
}

/// Native Apple macOS 26+ Liquid Glass modifiers with user-configurable presets, tints, and clean fallbacks for macOS 14–15.
public extension View {
    @ViewBuilder
    func readBoxGlassSurface<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        self.modifier(ReadBoxGlassSurfaceModifier(shape: shape, interactive: interactive, explicitTint: tint))
    }

    @ViewBuilder
    func readBoxGlassCard(cornerRadius: CGFloat = 16, isSelected: Bool = false, isHovered: Bool = false) -> some View {
        self.modifier(ReadBoxGlassCardModifier(cornerRadius: cornerRadius, isSelected: isSelected, isHovered: isHovered))
    }

    /// Clean Liquid Glass capsule button: clear refractive glass by default, restrained accent only when prominent.
    @ViewBuilder
    func readBoxGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                if let tint {
                    self.buttonStyle(.glassProminent).tint(tint)
                } else {
                    self.buttonStyle(.glassProminent)
                }
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                if let tint {
                    self.buttonStyle(.borderedProminent).tint(tint)
                } else {
                    self.buttonStyle(.borderedProminent)
                }
            } else {
                self.buttonStyle(.bordered)
            }
        }
        #else
        if prominent {
            if let tint {
                self.buttonStyle(.borderedProminent).tint(tint)
            } else {
                self.buttonStyle(.borderedProminent)
            }
        } else {
            self.buttonStyle(.bordered)
        }
        #endif
    }

    @ViewBuilder
    func readBoxSeamlessToolbar() -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }
}

/// Container that groups adjacent Liquid Glass controls so they refract & morph smoothly on macOS 26+.
public struct ReadBoxGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Subtle ambient backdrop canvas that gives Liquid Glass surfaces rich depth and soft light refraction.
public struct LiquidGlassCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readBoxGlassPreferences) private var envPrefs

    private let overridePreferences: LiquidGlassPreferences?

    public init(preferences: LiquidGlassPreferences? = nil) {
        self.overridePreferences = preferences
    }

    public var body: some View {
        let prefs = overridePreferences ?? envPrefs
        let intensity = max(0, min(1.5, prefs.ambientIntensity))
        let baseColors = prefs.ambientTheme.baseGradientColors(for: colorScheme)
        let darkFactor = colorScheme == .dark ? 1.0 : 0.56

        ZStack {
            if prefs.materialStyle == .solid && intensity < 0.05 {
                Color(nsColor: .windowBackgroundColor)
            } else {
                LinearGradient(
                    colors: baseColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if intensity > 0.01 {
                    RadialGradient(
                        colors: [prefs.ambientTheme.accentColor.opacity(0.18 * darkFactor * intensity), Color.clear],
                        center: .topTrailing,
                        startRadius: 16,
                        endRadius: 520
                    )
                    RadialGradient(
                        colors: [prefs.ambientTheme.secondaryColor.opacity(0.15 * darkFactor * intensity), Color.clear],
                        center: .bottomLeading,
                        startRadius: 16,
                        endRadius: 460
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Compact interactive preview widget shown inside Settings -> 外观与液态玻璃 so users can inspect
/// material refraction, ambient glow, tint, rim light, and card translucency in real time.
public struct LiquidGlassLivePreviewCard: View {
    let preferences: LiquidGlassPreferences
    @State private var hoverDemoCard = false

    public init(preferences: LiquidGlassPreferences) {
        self.preferences = preferences
    }

    public var body: some View {
        ZStack {
            LiquidGlassCanvasBackground(preferences: preferences)

            // Decorative soft orbs behind glass so refraction differences are immediately obvious
            Circle()
                .fill(preferences.ambientTheme.accentColor.opacity(0.28 * max(0.15, preferences.ambientIntensity)))
                .frame(width: 110, height: 110)
                .blur(radius: 26)
                .offset(x: -140, y: -32)

            Circle()
                .fill(preferences.ambientTheme.secondaryColor.opacity(0.24 * max(0.15, preferences.ambientIntensity)))
                .frame(width: 120, height: 120)
                .blur(radius: 30)
                .offset(x: 150, y: 38)

            VStack(spacing: 10) {
                // Mini Header Bar Preview
                ReadBoxGlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 10.5, weight: .bold))
                                .frame(width: 24, height: 24)
                                .readBoxGlassSurface(in: Circle(), interactive: true)
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10.5, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .readBoxGlassSurface(in: Circle(), interactive: true)
                        }

                        Text("收集箱")
                            .font(.system(size: 13.5, weight: .bold))
                        Text("12")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .readBoxGlassSurface(in: Capsule())

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .indigo, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("提问 AI")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .readBoxGlassSurface(in: Capsule(), interactive: true)
                    }
                }

                // Mini Cards Row Preview
                HStack(spacing: 10) {
                    miniClipCard(
                        title: "液态玻璃交互设计指南",
                        excerpt: "原生折射光影、通透层级与沉浸阅读体验的平衡之道…",
                        tag: "设计",
                        domain: "apple.com",
                        starred: true,
                        hovered: hoverDemoCard
                    )
                    .onHover { hoverDemoCard = $0 }

                    miniClipCard(
                        title: "个人知识库 AI 检索实践",
                        excerpt: "结合本地全文检索与大模型问答，让每篇收藏都能随时被唤醒。",
                        tag: "AI",
                        domain: "readbox.local",
                        starred: false,
                        hovered: false
                    )
                }

                // Mini Floating Glass Pill Preview
                HStack(spacing: 10) {
                    Text("已选 2 篇")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1, height: 11)
                    Label("AI 沉淀", systemImage: "sparkles")
                        .font(.system(size: 10.5, weight: .semibold))
                    Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1, height: 11)
                    Label("归档", systemImage: "archivebox")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .readBoxGlassSurface(in: Capsule(), interactive: true)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            }
            .padding(14)
        }
        .frame(height: 186)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .environment(\.readBoxGlassPreferences, preferences)
        .preferredColorScheme(preferences.appearance.colorScheme)
    }

    private func miniClipCard(
        title: String,
        excerpt: String,
        tag: String,
        domain: String,
        starred: Bool,
        hovered: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.orange)
                }
            }
            Text(excerpt)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Text(tag)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
                Text(domain)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)
        .readBoxGlassCard(cornerRadius: 11, isSelected: false, isHovered: hovered)
    }
}
