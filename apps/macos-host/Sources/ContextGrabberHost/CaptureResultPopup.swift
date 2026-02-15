import AppKit
import ContextGrabberCore
import SwiftUI

@MainActor
final class CaptureResultPopupController {
  private var panel: NSPanel?

  func show(
    state: CaptureFeedbackState,
    onCopy: (() -> Void)?,
    onOpen: (() -> Void)?,
    onDismiss: @escaping () -> Void
  ) {
    let panel = ensurePanel()
    panel.contentViewController = NSHostingController(
      rootView: CaptureResultPopupView(
        state: state,
        onCopy: onCopy,
        onOpen: onOpen,
        onDismiss: onDismiss
      )
    )
    panel.setContentSize(NSSize(width: 420, height: 182))
    position(panel: panel)
    panel.orderFrontRegardless()
  }

  func hide() {
    panel?.orderOut(nil)
  }

  private func ensurePanel() -> NSPanel {
    if let panel {
      return panel
    }

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 182),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.worksWhenModal = true

    self.panel = panel
    return panel
  }

  private func position(panel: NSPanel) {
    let mouseLocation = NSEvent.mouseLocation
    let activeScreen =
      NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
      ?? NSScreen.main
      ?? NSScreen.screens.first

    guard let screen = activeScreen else {
      return
    }

    let frame = screen.visibleFrame
    let popupSize = panel.frame.size
    let x = frame.maxX - popupSize.width - 20
    let y = frame.maxY - popupSize.height - 32
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

private struct CaptureResultPopupView: View {
  let state: CaptureFeedbackState
  let onCopy: (() -> Void)?
  let onOpen: (() -> Void)?
  let onDismiss: () -> Void

  var body: some View {
    let accent = state.kind == .success ? Color.green : Color.orange
    let symbol = state.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"

    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: symbol)
          .foregroundStyle(accent)
          .font(.system(size: 15, weight: .semibold))

        VStack(alignment: .leading, spacing: 2) {
          Text(state.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          if let targetLabel = state.targetLabel, !targetLabel.isEmpty {
            Text(targetLabel)
              .font(.callout)
              .lineLimit(1)
          }
          Text(state.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Spacer(minLength: 0)

        Button(action: onDismiss) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }

      HStack(spacing: 10) {
        if let sourceLabel = state.sourceLabel, !sourceLabel.isEmpty {
          Text(sourceLabel)
        }
        if let extractionMethod = state.extractionMethod, !extractionMethod.isEmpty {
          Text("Method: \(extractionMethod)")
        }
        if let tokenLabel = formatTokenEstimateLabel(state.tokenCount) {
          Text(tokenLabel)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)

      if let warning = state.warning, !warning.isEmpty {
        Text("Warning: \(warning)")
          .font(.caption2)
          .foregroundStyle(.orange)
          .lineLimit(2)
      }

      HStack(spacing: 8) {
        Button("Copy to Clipboard") {
          onCopy?()
        }
        .buttonStyle(.borderedProminent)
        .disabled(onCopy == nil)

        Button("Open File") {
          onOpen?()
        }
        .buttonStyle(.bordered)
        .disabled(onOpen == nil)

        Button("Dismiss") {
          onDismiss()
        }
        .buttonStyle(.bordered)

        Spacer(minLength: 0)
      }
    }
    .padding(12)
    .frame(width: 420, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.regularMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
    )
  }
}
