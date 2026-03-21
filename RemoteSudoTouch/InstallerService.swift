import Foundation

struct TunnelHost: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var remoteUser: String
  var remoteHost: String
  var remoteListenPort: String

  init(
    id: String = UUID().uuidString,
    name: String = "",
    remoteUser: String = "ubuntu",
    remoteHost: String = "",
    remoteListenPort: String = "9876"
  ) {
    self.id = id
    self.name = name
    self.remoteUser = remoteUser
    self.remoteHost = remoteHost
    self.remoteListenPort = remoteListenPort
  }

  var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var trimmedRemoteUser: String {
    remoteUser.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var trimmedRemoteHost: String {
    remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var displayName: String {
    if !trimmedName.isEmpty {
      return trimmedName
    }
    if !trimmedRemoteHost.isEmpty {
      return trimmedRemoteHost
    }
    return "Unnamed Server"
  }

  var remoteListenPortValue: Int {
    Int(remoteListenPort) ?? 0
  }

  var fileSlug: String {
    let source = trimmedName.isEmpty ? trimmedRemoteHost : trimmedName
    let lowered = source.lowercased()
    let sanitizedScalars = lowered.unicodeScalars.map { scalar -> Character in
      if CharacterSet.alphanumerics.contains(scalar) {
        return Character(scalar)
      }
      if scalar == "-" || scalar == "." || scalar == "_" {
        return Character(scalar)
      }
      return "-"
    }

    var slug = String(sanitizedScalars)
      .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))

    if slug.isEmpty {
      slug = "server"
    }

    return slug + "-" + shortID
  }

  private var shortID: String {
    String(id.prefix(8)).lowercased()
  }
}

struct InstallerConfiguration {
  let sshKeyPath: String
  let localAgentPort: String
  let launchAtLogin: Bool
  let keepAlive: Bool
  let hosts: [TunnelHost]

  var expandedSSHKeyPath: String {
    (sshKeyPath as NSString).expandingTildeInPath
  }

  var agentPortValue: Int {
    Int(localAgentPort) ?? 0
  }
}

struct InstallerError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

enum ServiceHealth {
  case stopped
  case partial
  case running
}

struct ServiceStatusSnapshot {
  let agentRunning: Bool
  let runningTunnels: Int
  let totalTunnels: Int

  var health: ServiceHealth {
    if agentRunning && runningTunnels == totalTunnels {
      return .running
    }
    if agentRunning || runningTunnels > 0 {
      return .partial
    }
    return .stopped
  }
}

final class InstallerService {
  private let fileManager = FileManager.default
  private let bundleBinaryName = "RemoteSudoTouchAgent"
  private let currentTeamPrefix = "com.paul.remotesudotouch"
  private let legacyTeamPrefixes = [
    "com.paul.remotesudotouchagent",
    "com.paul.touchidsudoinstaller",
  ]
  private let supportFolderName = "RemoteSudoTouch"
  private let legacySupportFolderName = "TouchIDSudoBridge"
  private let appScriptPrefix = "RemoteSudoTouch"

  var supportDir: URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(supportFolderName, isDirectory: true)
  }

  private var legacySupportDir: URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(legacySupportFolderName, isDirectory: true)
  }

  var launchAgentsDir: URL {
    URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
  }

  private var logsDir: URL {
    supportDir.appendingPathComponent("Logs", isDirectory: true)
  }

  private var agentBinaryURL: URL {
    supportDir.appendingPathComponent(bundleBinaryName)
  }

  private var agentRunnerScriptURL: URL {
    supportDir.appendingPathComponent("\(appScriptPrefix)-agent.sh")
  }

  private var configFileURL: URL {
    supportDir.appendingPathComponent("installer-config.json")
  }

  private var agentPlistURL: URL {
    launchAgentsDir.appendingPathComponent("\(currentTeamPrefix).agent.plist")
  }

  private var agentLabel: String { "\(currentTeamPrefix).agent" }

  private var legacyLabels: [String] {
    legacyTeamPrefixes.flatMap { prefix in
      ["\(prefix).agent", "\(prefix).tunnel"]
    }
  }

  private var legacyPlistURLs: [URL] {
    legacyTeamPrefixes.flatMap { prefix in
      [
        launchAgentsDir.appendingPathComponent("\(prefix).agent.plist"),
        launchAgentsDir.appendingPathComponent("\(prefix).tunnel.plist"),
      ]
    }
  }

  private var cleanupFileURLs: [URL] {
    [
      supportDir.appendingPathComponent("RemoteSudoTouch-agent.sh"),
      supportDir.appendingPathComponent("RemoteSudoTouch-ssh-tunnel.sh"),
      legacySupportDir.appendingPathComponent("run-touchid-sudo-agent.sh"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouch-agent.sh"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouch-ssh-tunnel.sh"),
      legacySupportDir.appendingPathComponent("touchid-sudo-agent"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouchAgent"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouch"),
      legacySupportDir.appendingPathComponent("installer-config.json"),
    ]
  }

  func install(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    try validate(configuration: configuration)
    try ensureDirectories(log: log)
    try removeLegacyArtifacts(log: log)
    try removeCurrentTunnelArtifacts(log: log)
    try installBundledAgent(log: log)
    try writeConfig(configuration: configuration, log: log)
    try writeAgentRunnerScript(configuration: configuration, log: log)
    try writeTunnelRunnerScripts(configuration: configuration, log: log)
    try writeLaunchAgents(configuration: configuration, log: log)
    try reloadServices(configuration: configuration, log: log)
    log("Install/update complete.")
  }

  func validateSSH(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    try validate(configuration: configuration)

    for host in configuration.hosts {
      let output = try runCapture([
        "/usr/bin/ssh",
        "-i", configuration.expandedSSHKeyPath,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=accept-new",
        "\(host.trimmedRemoteUser)@\(host.trimmedRemoteHost)",
        "echo touchid-sudo-bridge-ok"
      ])

      log("SSH check succeeded for \(host.displayName): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
  }

  func startServices(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    try validate(configuration: configuration)

    if try isServiceLoaded(label: agentLabel) {
      log("\(agentLabel) is already running.")
    } else {
      try bootstrap(plistURL: agentPlistURL)
      log("Started \(agentLabel).")
    }

    for host in configuration.hosts {
      let label = tunnelLabel(for: host)
      let plistURL = tunnelPlistURL(for: host)

      if try isServiceLoaded(label: label) {
        log("\(label) is already running.")
      } else {
        try bootstrap(plistURL: plistURL)
        log("Started \(label).")
      }
    }
  }

  func stopServices(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    for host in configuration.hosts.reversed() {
      let label = tunnelLabel(for: host)
      try bootout(label: label)
      log("Stopped \(label).")
    }

    try bootout(label: agentLabel)
    log("Stopped \(agentLabel).")
  }

  func reloadServices(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    for label in legacyLabels {
      try bootout(label: label)
    }

    for label in currentKnownLabels(configuration: configuration) {
      try bootout(label: label)
    }

    try bootstrap(plistURL: agentPlistURL)
    for host in configuration.hosts {
      try bootstrap(plistURL: tunnelPlistURL(for: host))
    }
    log("Reloaded LaunchAgents.")
  }

  func loadSavedConfiguration() -> StoredConfiguration? {
    let urls = [configFileURL, legacySupportDir.appendingPathComponent("installer-config.json")]

    for url in urls {
      guard fileManager.fileExists(atPath: url.path) else {
        continue
      }

      do {
        let data = try Data(contentsOf: url)

        if let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: data) {
          return stored
        }

        if let legacy = try? JSONDecoder().decode(LegacyStoredConfiguration.self, from: data) {
          return StoredConfiguration(
            sshKeyPath: legacy.sshKeyPath,
            localAgentPort: legacy.localAgentPort,
            launchAtLogin: legacy.launchAtLogin,
            keepAlive: legacy.keepAlive,
            hosts: [
              TunnelHost(
                remoteUser: legacy.remoteUser,
                remoteHost: legacy.remoteHost,
                remoteListenPort: String(legacy.remoteListenPort)
              )
            ]
          )
        }
      } catch {
        continue
      }
    }

    return nil
  }

  func currentServiceStatus(configuration: InstallerConfiguration) -> ServiceStatusSnapshot {
    let agentRunning = (try? isServiceLoaded(label: agentLabel)) ?? false
    let runningTunnels = configuration.hosts.filter { host in
      ((try? isServiceLoaded(label: tunnelLabel(for: host))) ?? false)
    }.count

    return ServiceStatusSnapshot(
      agentRunning: agentRunning,
      runningTunnels: runningTunnels,
      totalTunnels: configuration.hosts.count
    )
  }

  func removeInstalledArtifacts(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    for label in legacyLabels + currentKnownLabels(configuration: configuration) {
      try bootout(label: label)
    }

    for url in legacyPlistURLs + [agentPlistURL] + tunnelPlistURLs(configuration: configuration) {
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
        log("Removed \(url.lastPathComponent).")
      }
    }

    try removeCurrentTunnelArtifacts(log: log)

    for url in cleanupFileURLs + [agentBinaryURL, configFileURL] {
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
        log("Removed \(url.lastPathComponent).")
      }
    }
  }

  private func validate(configuration: InstallerConfiguration) throws {
    guard let localPort = Int(configuration.localAgentPort), (1...65535).contains(localPort) else {
      throw InstallerError("Local agent port must be a valid TCP port.")
    }

    if !fileManager.fileExists(atPath: configuration.expandedSSHKeyPath) {
      throw InstallerError("SSH private key not found at \(configuration.expandedSSHKeyPath)")
    }

    if configuration.hosts.isEmpty {
      throw InstallerError("Add at least one remote server.")
    }

    var seenHosts = Set<String>()

    for host in configuration.hosts {
      if host.trimmedRemoteUser.isEmpty {
        throw InstallerError("Each server needs a remote Ubuntu username.")
      }

      if host.trimmedRemoteHost.isEmpty {
        throw InstallerError("Each server needs a remote hostname.")
      }

      let duplicateKey = host.trimmedRemoteUser + "@" + host.trimmedRemoteHost + ":" + host.remoteListenPort
      if seenHosts.contains(duplicateKey) {
        throw InstallerError("Duplicate server entry for \(duplicateKey).")
      }
      seenHosts.insert(duplicateKey)

      guard (1...65535).contains(host.remoteListenPortValue) else {
        throw InstallerError("Remote forwarded port must be a valid TCP port for \(host.displayName).")
      }
    }
  }

  private func ensureDirectories(log: (String) -> Void) throws {
    try fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
    log("Ensured Application Support and LaunchAgents directories.")
  }

  private func removeLegacyArtifacts(log: (String) -> Void) throws {
    for label in legacyLabels {
      try bootout(label: label)
    }

    for url in legacyPlistURLs {
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
        log("Removed legacy LaunchAgent \(url.lastPathComponent).")
      }
    }

    let legacyFiles = [
      legacySupportDir.appendingPathComponent("run-touchid-sudo-agent.sh"),
      legacySupportDir.appendingPathComponent("touchid-sudo-agent"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouchAgent"),
      legacySupportDir.appendingPathComponent("installer-config.json"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouch-agent.sh"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouch-ssh-tunnel.sh"),
      legacySupportDir.appendingPathComponent("RemoteSudoTouch"),
    ]

    for url in legacyFiles {
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
        log("Removed legacy support file \(url.lastPathComponent).")
      }
    }

    if fileManager.fileExists(atPath: legacySupportDir.path),
       (try? fileManager.contentsOfDirectory(atPath: legacySupportDir.path).isEmpty) == true {
      try fileManager.removeItem(at: legacySupportDir)
      log("Removed legacy support folder \(legacySupportDir.lastPathComponent).")
    }
  }

  private func removeCurrentTunnelArtifacts(log: (String) -> Void) throws {
    let currentTunnelPlists = try matchingURLs(
      in: launchAgentsDir,
      prefix: "\(currentTeamPrefix).tunnel",
      suffix: ".plist"
    )
    for url in currentTunnelPlists {
      let label = url.deletingPathExtension().lastPathComponent
      try bootout(label: label)
      try fileManager.removeItem(at: url)
      log("Removed stale tunnel LaunchAgent \(url.lastPathComponent).")
    }

    let currentTunnelScripts = try matchingURLs(
      in: supportDir,
      prefix: "\(appScriptPrefix)-ssh-tunnel-",
      suffix: ".sh"
    )
    for url in currentTunnelScripts {
      try fileManager.removeItem(at: url)
      log("Removed stale tunnel script \(url.lastPathComponent).")
    }

    let staleTunnelLogs = try matchingURLs(
      in: logsDir,
      prefix: "\(appScriptPrefix)-ssh-tunnel-",
      suffix: ".log"
    )
    for url in staleTunnelLogs {
      try fileManager.removeItem(at: url)
      log("Removed stale tunnel log \(url.lastPathComponent).")
    }
  }

  private func matchingURLs(in directory: URL, prefix: String, suffix: String) throws -> [URL] {
    guard fileManager.fileExists(atPath: directory.path) else {
      return []
    }

    return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(suffix) }
  }

  private func installBundledAgent(log: (String) -> Void) throws {
    guard let bundledURL = Bundle.main.url(forResource: bundleBinaryName, withExtension: nil) else {
      throw InstallerError("Bundled \(bundleBinaryName) binary is missing from app resources.")
    }

    if fileManager.fileExists(atPath: agentBinaryURL.path) {
      try fileManager.removeItem(at: agentBinaryURL)
    }

    try fileManager.copyItem(at: bundledURL, to: agentBinaryURL)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agentBinaryURL.path)
    log("Installed bundled \(bundleBinaryName).")
  }

  private func writeConfig(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    let payload = StoredConfiguration(
      sshKeyPath: configuration.expandedSSHKeyPath,
      localAgentPort: configuration.agentPortValue,
      launchAtLogin: configuration.launchAtLogin,
      keepAlive: configuration.keepAlive,
      hosts: configuration.hosts
    )

    let data = try JSONEncoder.pretty.encode(payload)
    try data.write(to: configFileURL, options: .atomic)
    log("Wrote installer configuration snapshot.")
  }

  private func writeAgentRunnerScript(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    let script = """
    #!/bin/zsh
    exec "\(agentBinaryURL.path)" --port \(configuration.agentPortValue)
    """

    try script.write(to: agentRunnerScriptURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agentRunnerScriptURL.path)
    log("Wrote \(agentRunnerScriptURL.lastPathComponent).")
  }

  private func writeTunnelRunnerScripts(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    for host in configuration.hosts {
      let script = """
      #!/bin/zsh
      exec /usr/bin/ssh -NT \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=accept-new \
        -i "\(configuration.expandedSSHKeyPath)" \
        -R 127.0.0.1:\(host.remoteListenPort):127.0.0.1:\(configuration.localAgentPort) \
        "\(host.trimmedRemoteUser)@\(host.trimmedRemoteHost)"
      """

      let url = tunnelRunnerScriptURL(for: host)
      try script.write(to: url, atomically: true, encoding: .utf8)
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
      log("Wrote \(url.lastPathComponent).")
    }
  }

  private func writeLaunchAgents(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    let agentPlist: [String: Any] = [
      "Label": agentLabel,
      "ProgramArguments": [agentRunnerScriptURL.path],
      "RunAtLoad": configuration.launchAtLogin,
      "KeepAlive": configuration.keepAlive,
      "WorkingDirectory": supportDir.path,
      "StandardOutPath": logsDir.appendingPathComponent("RemoteSudoTouch-agent.out.log").path,
      "StandardErrorPath": logsDir.appendingPathComponent("RemoteSudoTouch-agent.err.log").path
    ]

    try writePlist(agentPlist, to: agentPlistURL)

    for host in configuration.hosts {
      let slug = host.fileSlug
      let tunnelPlist: [String: Any] = [
        "Label": tunnelLabel(for: host),
        "ProgramArguments": [tunnelRunnerScriptURL(for: host).path],
        "RunAtLoad": configuration.launchAtLogin,
        "KeepAlive": configuration.keepAlive,
        "WorkingDirectory": supportDir.path,
        "StandardOutPath": logsDir.appendingPathComponent("\(appScriptPrefix)-ssh-tunnel-\(slug).out.log").path,
        "StandardErrorPath": logsDir.appendingPathComponent("\(appScriptPrefix)-ssh-tunnel-\(slug).err.log").path
      ]

      try writePlist(tunnelPlist, to: tunnelPlistURL(for: host))
    }

    log("Wrote LaunchAgents.")
  }

  private func writePlist(_ object: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    try data.write(to: url, options: .atomic)
  }

  private func currentKnownLabels(configuration: InstallerConfiguration) -> [String] {
    [agentLabel] + configuration.hosts.map(tunnelLabel(for:))
  }

  private func tunnelPlistURLs(configuration: InstallerConfiguration) -> [URL] {
    configuration.hosts.map(tunnelPlistURL(for:))
  }

  private func tunnelRunnerScriptURL(for host: TunnelHost) -> URL {
    supportDir.appendingPathComponent("\(appScriptPrefix)-ssh-tunnel-\(host.fileSlug).sh")
  }

  private func tunnelPlistURL(for host: TunnelHost) -> URL {
    launchAgentsDir.appendingPathComponent("\(tunnelLabel(for: host)).plist")
  }

  private func tunnelLabel(for host: TunnelHost) -> String {
    "\(currentTeamPrefix).tunnel.\(host.fileSlug)"
  }

  private func isServiceLoaded(label: String) throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["print", "gui/\(getuid())/\(label)"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
  }

  private func bootstrap(plistURL: URL) throws {
    try run([
      "/bin/launchctl",
      "bootstrap",
      "gui/\(getuid())",
      plistURL.path
    ], ignoringExitCodes: [37])
  }

  private func bootout(label: String) throws {
    try run([
      "/bin/launchctl",
      "bootout",
      "gui/\(getuid())/\(label)"
    ], ignoringExitCodes: [3, 36, 113])
  }

  private func run(_ command: [String], ignoringExitCodes: Set<Int>) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let code = Int(process.terminationStatus)
    if code != 0 && !ignoringExitCodes.contains(code) {
      let stderrString = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw InstallerError(stderrString.isEmpty ? "Command failed with exit code \(code)." : stderrString)
    }
  }

  private func runCapture(_ command: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command[0])
    process.arguments = Array(command.dropFirst())

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

    if process.terminationStatus != 0 {
      let stderrString = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      throw InstallerError(stderrString.isEmpty ? "SSH validation failed." : stderrString)
    }

    return String(decoding: stdoutData, as: UTF8.self)
  }
}

struct StoredConfiguration: Codable {
  let sshKeyPath: String
  let localAgentPort: Int
  let launchAtLogin: Bool
  let keepAlive: Bool
  let hosts: [TunnelHost]
}

private struct LegacyStoredConfiguration: Codable {
  let remoteUser: String
  let remoteHost: String
  let sshKeyPath: String
  let remoteListenPort: Int
  let localAgentPort: Int
  let launchAtLogin: Bool
  let keepAlive: Bool
}

private extension JSONEncoder {
  static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
