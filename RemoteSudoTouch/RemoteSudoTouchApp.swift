import AppKit
import SwiftUI

@main
struct RemoteSudoTouchApp: App {
  @StateObject private var viewModel = InstallerViewModel()

  var body: some Scene {
    WindowGroup {
      InstallerView(viewModel: viewModel)
        .frame(minWidth: 980, minHeight: 760)
        .background(WindowConfigurator())
    }
    .windowResizability(.contentMinSize)
  }
}

private struct WindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()

    DispatchQueue.main.async {
      guard let window = view.window else {
        return
      }

      let configuredKey = "RemoteSudoTouchHasConfiguredInitialFrame"
      guard window.frameAutosaveName != configuredKey else {
        return
      }

      let visibleFrame = window.screen?.visibleFrame
        ?? NSScreen.main?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

      let targetWidth = min(max(visibleFrame.width * 0.60, 920), 1180)
      let targetHeight = min(max(visibleFrame.height * 0.88, 760), 980)
      let originX = visibleFrame.midX - (targetWidth / 2)
      let originY = visibleFrame.midY - (targetHeight / 2)
      let targetFrame = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

      window.setFrame(targetFrame, display: true)
      window.setFrameAutosaveName(configuredKey)
    }

    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
