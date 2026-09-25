import AppKit
import Foundation
import BillboardShared

@MainActor
final class BillboardViewModel: ObservableObject {
    let config: BillboardConfig
    let resultFIFO: String?

    @Published var inputText: String
    @Published var validationMessage: String?
    @Published var artwork: NSImage?
    @Published var logo: NSImage?

    private var hasStarted = false
    private var hasCompleted = false

    init(request: BillboardLaunchRequest) {
        config = request.config
        resultFIFO = request.resultFIFO
        inputText = request.config.input?.defaultValue ?? ""
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        loadImages()

        let timeout = config.effectiveTimeout
        if timeout > 0 {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.complete(BillboardResult(dismissed: true, timeout: true))
            }
        }
    }

    func select(_ button: ButtonDefinition, index: Int) {
        if config.input?.required == true && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "A response is required."
            return
        }
        complete(BillboardResult(
            button: button.label,
            value: button.value,
            index: index,
            deferSeconds: button.deferSeconds,
            input: config.input == nil ? nil : inputText))
    }

    func dismiss() {
        complete(BillboardResult(dismissed: true, input: config.input == nil ? nil : inputText))
    }

    func enforceInputLimit() {
        guard let maximum = config.input?.maxLength, inputText.count > maximum else { return }
        inputText = String(inputText.prefix(maximum))
    }

    func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = config.modal
        window.level = config.modal ? .modalPanel : .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovable = false

        if config.modal, let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
            window.center()
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else if let screen = NSScreen.main {
            let size = NSSize(width: 560, height: 390)
            window.setContentSize(size)
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 24,
                y: visible.minY + 24))
            window.orderFrontRegardless()
        }
    }

    private func loadImages() {
        if let source = config.illustration,
           !source.isEmpty,
           source.caseInsensitiveCompare("none") != .orderedSame,
           source.contains(":") || source.hasPrefix("/") {
            Task {
                artwork = try? await SafeImageLoader.load(source: source, maxPixelSize: 720)
            }
        }
        if let source = config.branding?.logo, !source.isEmpty {
            Task {
                logo = try? await SafeImageLoader.load(source: source, maxPixelSize: 160)
            }
        }
    }

    private func complete(_ result: BillboardResult) {
        guard !hasCompleted else { return }
        hasCompleted = true
        let fifo = resultFIFO

        Task.detached {
            do {
                if let fifo {
                    try ResultFIFO.write(result: result, to: fifo)
                } else {
                    var data = try BillboardJSON.encoder().encode(result)
                    data.append(0x0A)
                    try FileHandle.standardOutput.write(contentsOf: data)
                }
            } catch {
                FileHandle.standardError.write(Data("Billboard result error: \(error.localizedDescription)\n".utf8))
            }
            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
