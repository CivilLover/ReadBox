import SwiftUI

/// Native Apple macOS 26+ Liquid Glass modifiers with clean translucent fallbacks for macOS 14–15.
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
                if let tint {
                    self.buttonStyle(.glass).tint(tint)
                } else {
                    self.buttonStyle(.glass)
                }
            }
        } else {
            if prominent {
                if let tint {
                    self.buttonStyle(.borderedProminent).tint(tint)
                } else {
                    self.buttonStyle(.borderedProminent)
                }
            } else {
                if let tint {
                    self.buttonStyle(.bordered).tint(tint)
                } else {
                    self.buttonStyle(.bordered)
                }
            }
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
                        Color(red: 0.09, green: 0.08, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.blue.opacity(0.14), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [Color.purple.opacity(0.11), Color.clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 460
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.99),
                        Color(red: 0.96, green: 0.96, blue: 0.98),
                        Color(red: 0.94, green: 0.95, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.blue.opacity(0.08), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [Color.purple.opacity(0.06), Color.clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 460
                )
            }
        }
        .ignoresSafeArea()
    }
}
