import SwiftUI

/// Native Apple macOS 26+ Liquid Glass modifiers with clean translucent fallbacks for macOS 14–15.
/// Follows Apple's Liquid Glass HIG: crisp neutral refractive glass surfaces with restrained icon tints (no harsh neon fills).
public extension View {
    @ViewBuilder
    func readBoxGlassSurface<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                if interactive {
                    self.glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    self.glassEffect(.regular.tint(tint), in: shape)
                }
            } else {
                if interactive {
                    self.glassEffect(.regular.interactive(), in: shape)
                } else {
                    self.glassEffect(.regular, in: shape)
                }
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
    }

    /// Clean Liquid Glass capsule button: clear refractive glass by default, restrained accent only when prominent.
    @ViewBuilder
    func readBoxGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                if let tint {
                    self.buttonStyle(.glassProminent).tint(tint)
                } else {
                    self.buttonStyle(.glassProminent)
                }
            } else {
                // Keep non-prominent glass buttons neutral & crystal-clear (avoid neon tinted blocks)
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
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// Subtle ambient backdrop canvas that gives Liquid Glass surfaces rich depth and soft light refraction.
public struct LiquidGlassCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.09, blue: 0.13),
                        Color(red: 0.07, green: 0.08, blue: 0.11),
                        Color(red: 0.09, green: 0.09, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.blue.opacity(0.16), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 560
                )
                RadialGradient(
                    colors: [Color.indigo.opacity(0.14), Color.clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 480
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.96, blue: 0.99),
                        Color(red: 0.96, green: 0.97, blue: 0.99),
                        Color(red: 0.93, green: 0.95, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.blue.opacity(0.09), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 560
                )
                RadialGradient(
                    colors: [Color.indigo.opacity(0.07), Color.clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 480
                )
            }
        }
        .ignoresSafeArea()
    }
}
