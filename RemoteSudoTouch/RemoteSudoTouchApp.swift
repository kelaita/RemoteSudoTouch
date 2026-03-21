import SwiftUI

@main
struct RemoteSudoTouchApp: App {
  @StateObject private var viewModel = InstallerViewModel()

  var body: some Scene {
    WindowGroup {
      InstallerView(viewModel: viewModel)
        .frame(minWidth: 900, minHeight: 700)
    }
    .windowResizability(.contentMinSize)
  }
}
