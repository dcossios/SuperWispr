import AppKit
import SwiftUI

/// A floating translucent panel that shows recording status and audio levels.
/// Uses NSPanel with .nonactivatingPanel so it never steals focus.
final class FlowBarPanel {
    private var panel: NSPanel?
    private var levelUpdateHandler: ((Float) -> Void)?

    func show() {
        guard panel == nil else { return }

        let viewModel = FlowBarViewModel()
        let hostingView = NSHostingView(rootView: FlowBarView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 44)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = hostingView
        p.isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let x = (screen.frame.width - 200) / 2
            let y = screen.frame.height - 80
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.orderFrontRegardless()
        panel = p

        levelUpdateHandler = { [weak viewModel] level in
            DispatchQueue.main.async { viewModel?.audioLevel = level }
        }
    }

    func updateLevel(_ level: Float) {
        levelUpdateHandler?(level)
    }

    func showProcessing() {
        if let viewModel = (panel?.contentView as? NSHostingView<FlowBarView>)?.rootView.viewModel {
            DispatchQueue.main.async { viewModel.isProcessing = true }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        levelUpdateHandler = nil
    }
}

// MARK: - SwiftUI Views

final class FlowBarViewModel: ObservableObject {
    @Published var audioLevel: Float = 0
    @Published var isProcessing: Bool = false
}

struct FlowBarView: View {
    @ObservedObject var viewModel: FlowBarViewModel

    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text("Processing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 14))

                WaveformView(level: viewModel.audioLevel)
                    .frame(width: 100, height: 24)

                Text("Recording")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WaveformView: View {
    let level: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                let scale = barHeight(index: i)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.red.opacity(0.8))
                    .frame(width: 3, height: max(4, 24 * scale))
                    .animation(.easeInOut(duration: 0.08), value: level)
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        let base = CGFloat(level)
        let variation = sin(Double(index) * 1.2 + Double(level) * 10)
        return max(0.15, min(1, base + CGFloat(variation) * 0.2))
    }
}
