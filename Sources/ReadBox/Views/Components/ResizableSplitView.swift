import SwiftUI
import AppKit

/// Overflow-proof horizontal split container with a main leading pane and a collapsible,
/// user-resizable trailing pane.
///
/// Unlike SwiftUI's `HSplitView` nested inside `NavigationSplitView` on macOS (which can
/// report oversized intrinsic widths and push both sidebar and detail edges off-screen),
/// this container strictly respects the exact width proposed by its parent via `GeometryReader`
/// and mathematically clamps both panes so neither can overflow or occlude child controls.
public struct ResizableTrailingSplitView<Leading: View, Trailing: View>: View {
    public let isTrailingVisible: Bool
    @Binding public var trailingWidth: Double
    public let minLeadingWidth: CGFloat
    public let minTrailingWidth: CGFloat
    public let maxTrailingWidth: CGFloat
    @ViewBuilder public let leading: () -> Leading
    @ViewBuilder public let trailing: () -> Trailing

    @State private var dragStartWidth: Double? = nil
    @State private var isHoveringDivider: Bool = false

    private let dividerThickness: CGFloat = 1

    public init(
        isTrailingVisible: Bool,
        trailingWidth: Binding<Double>,
        minLeadingWidth: CGFloat = 340,
        minTrailingWidth: CGFloat = 280,
        maxTrailingWidth: CGFloat = 540,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.isTrailingVisible = isTrailingVisible
        self._trailingWidth = trailingWidth
        self.minLeadingWidth = minLeadingWidth
        self.minTrailingWidth = minTrailingWidth
        self.maxTrailingWidth = maxTrailingWidth
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = max(0, proxy.size.width)
            let totalHeight = max(0, proxy.size.height)

            if isTrailingVisible && totalWidth > dividerThickness + 20 {
                let effectiveMinLeading = min(minLeadingWidth, totalWidth * 0.48)
                let effectiveMinTrailing = min(minTrailingWidth, totalWidth * 0.42)
                let effectiveMaxTrailing = max(
                    effectiveMinTrailing,
                    min(maxTrailingWidth, totalWidth - effectiveMinLeading - dividerThickness)
                )
                let clampedTrailing = min(max(CGFloat(trailingWidth), effectiveMinTrailing), effectiveMaxTrailing)
                let leadingWidth = max(0, totalWidth - clampedTrailing - dividerThickness)

                HStack(spacing: 0) {
                    leading()
                        .frame(width: leadingWidth, height: totalHeight)
                        .clipped()

                    splitDivider(
                        currentWidth: clampedTrailing,
                        minWidth: effectiveMinTrailing,
                        maxWidth: effectiveMaxTrailing,
                        height: totalHeight
                    )

                    trailing()
                        .frame(width: clampedTrailing, height: totalHeight)
                        .clipped()
                }
                .frame(width: totalWidth, height: totalHeight, alignment: .leading)
            } else {
                leading()
                    .frame(width: totalWidth, height: totalHeight)
                    .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func splitDivider(
        currentWidth: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(isHoveringDivider || dragStartWidth != nil ? Color.accentColor.opacity(0.45) : Color(nsColor: .separatorColor))
                .frame(width: isHoveringDivider || dragStartWidth != nil ? 2 : dividerThickness, height: height)

            Color.clear
                .frame(width: 9, height: height)
                .contentShape(Rectangle())
        }
        .frame(width: dividerThickness, height: height)
        .zIndex(10)
        .onHover { hovering in
            if hovering && !isHoveringDivider {
                isHoveringDivider = true
                NSCursor.resizeLeftRight.push()
            } else if !hovering && isHoveringDivider {
                isHoveringDivider = false
                if dragStartWidth == nil {
                    NSCursor.pop()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = Double(currentWidth)
                    }
                    let base = dragStartWidth ?? Double(currentWidth)
                    // Dragging left widens the trailing pane; dragging right narrows it.
                    let proposed = CGFloat(base) - value.translation.width
                    trailingWidth = Double(min(max(proposed, minWidth), maxWidth))
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    if !isHoveringDivider {
                        NSCursor.pop()
                    }
                }
        )
        .onDisappear {
            if isHoveringDivider || dragStartWidth != nil {
                isHoveringDivider = false
                dragStartWidth = nil
                NSCursor.pop()
            }
        }
    }
}

/// Overflow-proof horizontal split container with a user-resizable leading pane
/// and a flexible main trailing pane (e.g. KnowledgeBase document list + WYSIWYG editor).
public struct ResizableLeadingSplitView<Leading: View, Trailing: View>: View {
    @Binding public var leadingWidth: Double
    public let minLeadingWidth: CGFloat
    public let maxLeadingWidth: CGFloat
    public let minTrailingWidth: CGFloat
    @ViewBuilder public let leading: () -> Leading
    @ViewBuilder public let trailing: () -> Trailing

    @State private var dragStartWidth: Double? = nil
    @State private var isHoveringDivider: Bool = false

    private let dividerThickness: CGFloat = 1

    public init(
        leadingWidth: Binding<Double>,
        minLeadingWidth: CGFloat = 220,
        maxLeadingWidth: CGFloat = 340,
        minTrailingWidth: CGFloat = 300,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self._leadingWidth = leadingWidth
        self.minLeadingWidth = minLeadingWidth
        self.maxLeadingWidth = maxLeadingWidth
        self.minTrailingWidth = minTrailingWidth
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = max(0, proxy.size.width)
            let totalHeight = max(0, proxy.size.height)

            let effectiveMinLeading = min(minLeadingWidth, totalWidth * 0.42)
            let effectiveMinTrailing = min(minTrailingWidth, totalWidth * 0.48)
            let effectiveMaxLeading = max(
                effectiveMinLeading,
                min(maxLeadingWidth, totalWidth - effectiveMinTrailing - dividerThickness)
            )
            let clampedLeading = min(max(CGFloat(leadingWidth), effectiveMinLeading), effectiveMaxLeading)
            let trailingWidth = max(0, totalWidth - clampedLeading - dividerThickness)

            HStack(spacing: 0) {
                leading()
                    .frame(width: clampedLeading, height: totalHeight)
                    .clipped()

                splitDivider(
                    currentWidth: clampedLeading,
                    minWidth: effectiveMinLeading,
                    maxWidth: effectiveMaxLeading,
                    height: totalHeight
                )

                trailing()
                    .frame(width: trailingWidth, height: totalHeight)
                    .clipped()
            }
            .frame(width: totalWidth, height: totalHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func splitDivider(
        currentWidth: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(isHoveringDivider || dragStartWidth != nil ? Color.accentColor.opacity(0.45) : Color(nsColor: .separatorColor))
                .frame(width: isHoveringDivider || dragStartWidth != nil ? 2 : dividerThickness, height: height)

            Color.clear
                .frame(width: 9, height: height)
                .contentShape(Rectangle())
        }
        .frame(width: dividerThickness, height: height)
        .zIndex(10)
        .onHover { hovering in
            if hovering && !isHoveringDivider {
                isHoveringDivider = true
                NSCursor.resizeLeftRight.push()
            } else if !hovering && isHoveringDivider {
                isHoveringDivider = false
                if dragStartWidth == nil {
                    NSCursor.pop()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = Double(currentWidth)
                    }
                    let base = dragStartWidth ?? Double(currentWidth)
                    // Dragging right widens the leading pane; dragging left narrows it.
                    let proposed = CGFloat(base) + value.translation.width
                    leadingWidth = Double(min(max(proposed, minWidth), maxWidth))
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    if !isHoveringDivider {
                        NSCursor.pop()
                    }
                }
        )
        .onDisappear {
            if isHoveringDivider || dragStartWidth != nil {
                isHoveringDivider = false
                dragStartWidth = nil
                NSCursor.pop()
            }
        }
    }
}
