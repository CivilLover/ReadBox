import Foundation
import AppKit

/// Gently watches macOS pasteboard for newly copied web / WeChat article URLs so the user can clip with 1 click.
@MainActor
public final class ClipboardMonitor: ObservableObject {
    @Published public var detectedURL: String?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var dismissedURLs = Set<String>()
    private var timer: Timer?

    public init() {}

    public func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func dismissCurrent() {
        if let url = detectedURL {
            dismissedURLs.insert(url)
        }
        detectedURL = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty,
              !str.contains("\n"),
              (str.hasPrefix("https://") || str.hasPrefix("http://")),
              URL(string: str)?.host != nil,
              !dismissedURLs.contains(str) else {
            return
        }
        detectedURL = str
    }
}
