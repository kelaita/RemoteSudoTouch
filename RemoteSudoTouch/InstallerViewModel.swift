import AppKit
import Foundation

@MainActor
final class InstallerViewModel: ObservableObject {
  @Published var sshKeyPath = NSHomeDirectory() + "/.ssh/id_ed25519"
  @Published var localAgentPort = "8765"
  @Published var launchAtLogin = true
  @Published var keepAlive = true
  @Published var hosts: [TunnelHost] = [TunnelHost()]
  @Published var selectedHostID: String?
  @Published var statusLines: [String] = ["Ready."]
  @Published var serviceStatus = ServiceStatusSnapshot(agentRunning: false, tunnelStatuses: [])
  @Published var statusRevealToken = UUID()
  @Published var isBusy = false
  @Published var showSuccess = false

  private let service = InstallerService()

  init() {
    loadSavedConfiguration()
    if selectedHostID == nil {
      selectedHostID = hosts.first?.id
    }
    refreshServiceStatus()
  }

  var supportDir: URL { service.supportDir }
  var launchAgentsDir: URL { service.launchAgentsDir }

  var selectedHostIndex: Int? {
    guard let selectedHostID else {
      return hosts.isEmpty ? nil : 0
    }

    return hosts.firstIndex(where: { $0.id == selectedHostID }) ?? (hosts.isEmpty ? nil : 0)
  }

  func pickSSHKey() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true
    panel.prompt = "Choose"

    if panel.runModal() == .OK, let url = panel.url {
      sshKeyPath = url.path
    }
  }

  func addHost() {
    let newHost = TunnelHost()
    hosts.append(newHost)
    selectedHostID = newHost.id
    refreshServiceStatus()
  }

  func removeSelectedHost() {
    guard let index = selectedHostIndex else {
      return
    }

    let removedID = hosts[index].id
    hosts.remove(at: index)

    if hosts.isEmpty {
      let replacement = TunnelHost()
      hosts = [replacement]
      selectedHostID = replacement.id
      refreshServiceStatus()
      return
    }

    if selectedHostID == removedID {
      let nextIndex = min(index, hosts.count - 1)
      selectedHostID = hosts[nextIndex].id
    }
    refreshServiceStatus()
  }

  func install() async {
    await perform("Installing components") {
      try service.install(configuration: configuration, log: appendStatus(_:))
      showSuccess = true
    }
  }

  func validateSetup() async {
    await perform("Validating SSH connectivity") {
      try service.validateSSH(configuration: configuration, log: appendStatus(_:))
    }
  }

  func startServices() async {
    await perform("Starting services") {
      try service.startServices(configuration: configuration, log: appendStatus(_:))
    }
  }

  func stopServices() async {
    await perform("Stopping services") {
      try service.stopServices(configuration: configuration, log: appendStatus(_:))
    }
  }

  func reloadServices() async {
    await perform("Reloading services") {
      try service.reloadServices(configuration: configuration, log: appendStatus(_:))
    }
  }

  func uninstall() async {
    await perform("Uninstalling components") {
      try service.removeInstalledArtifacts(configuration: configuration, log: appendStatus(_:))
      appendStatus("Uninstall complete.")
    }
  }

  private func loadSavedConfiguration() {
    guard let stored = service.loadSavedConfiguration() else {
      return
    }

    sshKeyPath = stored.sshKeyPath
    localAgentPort = String(stored.localAgentPort)
    launchAtLogin = stored.launchAtLogin
    keepAlive = stored.keepAlive
    hosts = stored.hosts.isEmpty ? [TunnelHost()] : stored.hosts
    selectedHostID = hosts.first?.id
    statusLines = ["Loaded saved configuration."]
  }

  private var configuration: InstallerConfiguration {
    InstallerConfiguration(
      sshKeyPath: sshKeyPath,
      localAgentPort: localAgentPort,
      launchAtLogin: launchAtLogin,
      keepAlive: keepAlive,
      hosts: hosts
    )
  }

  private func perform(_ title: String, action: () throws -> Void) async {
    isBusy = true
    defer { isBusy = false }

    statusRevealToken = UUID()
    appendStatus("")
    appendStatus("== \(title) ==")

    do {
      try action()
    } catch {
      appendStatus("ERROR: \(error.localizedDescription)")
    }

    refreshServiceStatus()
  }

  func refreshServiceStatus() {
    serviceStatus = service.currentServiceStatus(configuration: configuration)
  }

  private func appendStatus(_ line: String) {
    statusLines.append(line)
  }
}
