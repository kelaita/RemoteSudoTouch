import Foundation

struct TunnelHost: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var remoteUser: String
  var remoteHost: String
  var sshKeyPathOverride: String
  var remoteListenPort: String

  init(
    id: String = UUID().uuidString,
    name: String = "",
    remoteUser: String = "",
    remoteHost: String = "",
    sshKeyPathOverride: String = "",
    remoteListenPort: String = "9876"
  ) {
    self.id = id
    self.name = name
    self.remoteUser = remoteUser
    self.remoteHost = remoteHost
    self.sshKeyPathOverride = sshKeyPathOverride
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

  var trimmedSSHKeyPathOverride: String {
    sshKeyPathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
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

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case remoteUser
    case remoteHost
    case sshKeyPathOverride
    case remoteListenPort
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    remoteUser = try container.decodeIfPresent(String.self, forKey: .remoteUser) ?? ""
    remoteHost = try container.decodeIfPresent(String.self, forKey: .remoteHost) ?? ""
    sshKeyPathOverride = try container.decodeIfPresent(String.self, forKey: .sshKeyPathOverride) ?? ""
    remoteListenPort = try container.decodeIfPresent(String.self, forKey: .remoteListenPort) ?? "9876"
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

  func expandedSSHKeyPath(for host: TunnelHost) -> String {
    let overridePath = host.trimmedSSHKeyPathOverride
    if !overridePath.isEmpty {
      return (overridePath as NSString).expandingTildeInPath
    }
    return expandedSSHKeyPath
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

struct TunnelServiceStatus: Identifiable {
  let host: TunnelHost
  let isLoaded: Bool
  let isRunning: Bool
  let issue: String?

  var id: String { host.id }

  var displayName: String { host.displayName }

  var isHealthy: Bool {
    isLoaded && isRunning && issue == nil
  }
}

struct ServiceStatusSnapshot {
  let agentRunning: Bool
  let tunnelStatuses: [TunnelServiceStatus]

  var runningTunnels: Int {
    tunnelStatuses.filter(\.isLoaded).count
  }

  var healthyTunnels: Int {
    tunnelStatuses.filter(\.isHealthy).count
  }

  var totalTunnels: Int {
    tunnelStatuses.count
  }

  var issueSummaries: [String] {
    tunnelStatuses.compactMap { status in
      guard let issue = status.issue else {
        return nil
      }
      return "\(status.displayName): \(issue)"
    }
  }

  var healthyTunnelNames: [String] {
    tunnelStatuses
      .filter(\.isHealthy)
      .map(\.displayName)
  }

  var health: ServiceHealth {
    if agentRunning && healthyTunnels == totalTunnels {
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
  private let currentTeamPrefix = "net.pomace.remotesudotouch"
  private let legacyTeamPrefixes: [String] = []
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
    try removeCurrentTunnelArtifacts(keeping: configuration.hosts, log: log)
    try installBundledAgent(log: log)
    try writeConfig(configuration: configuration, log: log)
    try writeAgentRunnerScript(configuration: configuration, log: log)
    try writeTunnelRunnerScripts(configuration: configuration, log: log)
    try writeLaunchAgents(configuration: configuration, log: log)
    try reloadServices(configuration: configuration, log: log)
    log("Configuration applied.")
  }

  func validateSSH(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    try validate(configuration: configuration)

    var failedHosts: [String] = []

    for host in configuration.hosts {
      let sshKeyPath = configuration.expandedSSHKeyPath(for: host)
      do {
        let output = try runCapture([
          "/usr/bin/ssh",
          "-i", sshKeyPath,
          "-o", "BatchMode=yes",
          "-o", "ConnectTimeout=5",
          "-o", "StrictHostKeyChecking=accept-new",
          "\(host.trimmedRemoteUser)@\(host.trimmedRemoteHost)",
          "echo touchid-sudo-bridge-ok"
        ])

        log("SSH check succeeded for \(host.displayName): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
      } catch {
        failedHosts.append(host.displayName)
        log("SSH check failed for \(host.displayName): \(error.localizedDescription)")
      }
    }

    if !failedHosts.isEmpty {
      let suffix = failedHosts.count == 1 ? "" : "s"
      throw InstallerError("SSH validation finished with \(failedHosts.count) failure\(suffix): \(failedHosts.joined(separator: ", "))")
    }
  }

  func startServices(configuration: InstallerConfiguration, log: (String) -> Void) throws {
    try validate(configuration: configuration)
    try ensureInstalledArtifacts(configuration: configuration)

    var failures: [String] = []

    if try isServiceLoaded(label: agentLabel) {
      log("\(agentLabel) is already running.")
    } else {
      do {
        try bootstrap(plistURL: agentPlistURL)
        log("Started \(agentLabel).")
      } catch {
        failures.append(error.localizedDescription)
        log("WARNING: \(error.localizedDescription)")
      }
    }

    for host in configuration.hosts {
      let label = tunnelLabel(for: host)
      let plistURL = tunnelPlistURL(for: host)

      if try isServiceLoaded(label: label) {
        log("\(label) is already running.")
      } else {
        do {
          try bootstrap(plistURL: plistURL)
          log("Started \(label).")
        } catch {
          failures.append(error.localizedDescription)
          log("WARNING: \(error.localizedDescription)")
        }
      }
    }

    if !failures.isEmpty {
      let suffix = failures.count == 1 ? "" : "s"
      throw InstallerError("Some services could not be started cleanly (\(failures.count) issue\(suffix)). Review the status panel for details.")
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

    var failures: [String] = []

    do {
      try bootstrap(plistURL: agentPlistURL)
    } catch {
      failures.append(error.localizedDescription)
      log("WARNING: \(error.localizedDescription)")
    }

    for host in configuration.hosts {
      do {
        try bootstrap(plistURL: tunnelPlistURL(for: host))
      } catch {
        failures.append(error.localizedDescription)
        log("WARNING: \(error.localizedDescription)")
      }
    }

    log("Reloaded LaunchAgents.")

    if !failures.isEmpty {
      let suffix = failures.count == 1 ? "" : "s"
      throw InstallerError("LaunchAgents were reloaded, but \(failures.count) service\(suffix) did not start cleanly. Review the status panel for details.")
    }
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
    let tunnelStatuses = configuration.hosts.map(tunnelStatus(for:))

    return ServiceStatusSnapshot(
      agentRunning: agentRunning,
      tunnelStatuses: tunnelStatuses
    )
  }

  func hasInstalledArtifacts(for configuration: InstallerConfiguration) -> Bool {
    if !fileManager.fileExists(atPath: agentBinaryURL.path)
      || !fileManager.fileExists(atPath: agentRunnerScriptURL.path)
      || !fileManager.fileExists(atPath: agentPlistURL.path)
    {
      return false
    }

    for host in configuration.hosts {
      if !fileManager.fileExists(atPath: tunnelRunnerScriptURL(for: host).path)
        || !fileManager.fileExists(atPath: tunnelPlistURL(for: host).path)
      {
        return false
      }
    }

    return true
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

    if configuration.hosts.isEmpty {
      throw InstallerError("Add at least one remote server.")
    }

    var seenHosts = Set<String>()

    for host in configuration.hosts {
      let sshKeyPath = configuration.expandedSSHKeyPath(for: host)
      if !fileManager.fileExists(atPath: sshKeyPath) {
        throw InstallerError("SSH private key not found for \(host.displayName) at \(sshKeyPath)")
      }

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

  private func removeCurrentTunnelArtifacts(keeping hosts: [TunnelHost] = [], log: (String) -> Void) throws {
    let labelsToKeep = Set(hosts.map(tunnelLabel(for:)))
    let scriptsToKeep = Set(hosts.map { tunnelRunnerScriptURL(for: $0).lastPathComponent })
    let logNamesToKeep = Set(hosts.flatMap { host in
      [
        tunnelErrorLogURL(for: host).lastPathComponent,
        tunnelOutputLogURL(for: host).lastPathComponent
      ]
    })

    let currentTunnelPlists = try matchingURLs(
      in: launchAgentsDir,
      prefix: "\(currentTeamPrefix).tunnel",
      suffix: ".plist"
    )
    for url in currentTunnelPlists {
      let label = url.deletingPathExtension().lastPathComponent
      if labelsToKeep.contains(label) {
        continue
      }
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
      if scriptsToKeep.contains(url.lastPathComponent) {
        continue
      }
      try fileManager.removeItem(at: url)
      log("Removed stale tunnel script \(url.lastPathComponent).")
    }

    let staleTunnelLogs = try matchingURLs(
      in: logsDir,
      prefix: "\(appScriptPrefix)-ssh-tunnel-",
      suffix: ".log"
    )
    for url in staleTunnelLogs {
      if logNamesToKeep.contains(url.lastPathComponent) {
        continue
      }
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

  private func ensureInstalledArtifacts(configuration: InstallerConfiguration) throws {
    guard fileManager.fileExists(atPath: agentBinaryURL.path) else {
      throw InstallerError("RemoteSudoTouch has not been installed yet. Click Install first to copy the agent and write the LaunchAgents.")
    }

    guard fileManager.fileExists(atPath: agentRunnerScriptURL.path) else {
      throw InstallerError("RemoteSudoTouch support files are missing. Click Install first to recreate the agent runner.")
    }

    guard fileManager.fileExists(atPath: agentPlistURL.path) else {
      throw InstallerError("LaunchAgents have not been written yet. Click Install first before starting services.")
    }

    for host in configuration.hosts {
      let scriptURL = tunnelRunnerScriptURL(for: host)
      let plistURL = tunnelPlistURL(for: host)

      guard fileManager.fileExists(atPath: scriptURL.path) else {
        throw InstallerError("Tunnel support files are missing for \(host.displayName). Click Install first to recreate them.")
      }

      guard fileManager.fileExists(atPath: plistURL.path) else {
        throw InstallerError("The LaunchAgent for \(host.displayName) has not been written yet. Click Install first before starting services.")
      }
    }
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
    log("Wrote configuration snapshot.")
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
      let sshKeyPath = configuration.expandedSSHKeyPath(for: host)
      let script = """
      #!/bin/zsh
      set -u

      SSH_KEY="\(sshKeyPath)"
      REMOTE_TARGET="\(host.trimmedRemoteUser)@\(host.trimmedRemoteHost)"
      REMOTE_PORT="\(host.remoteListenPort)"
      LOCAL_PORT="\(configuration.localAgentPort)"
      SSH_PID=""
      SSH_EXIT_CODE=0
      HEALTH_INTERVAL=15
      MAX_FAILURES=2

      log() {
        print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
      }

      wait_for_ssh() {
        local pid="$1"
        if [[ -z "$pid" ]]; then
          return 0
        fi

        wait "$pid" 2>/dev/null
        return $?
      }

      cleanup() {
        if [[ -n "${SSH_PID:-}" ]] && kill -0 "$SSH_PID" 2>/dev/null; then
          kill "$SSH_PID" 2>/dev/null || true
          wait_for_ssh "$SSH_PID" || true
        fi
      }

      health_check() {
        local request_id="health-$(date +%s)-$$"
        local payload='{"request_id":"'"${request_id}"'","timestamp":0,"hostname":"mac","user":"health","service":"remote-sudo-touch","tty":"","rhost":"","type":"health_check"}'
        local remote_command="printf '%s\\n' '$payload' | nc -w 5 127.0.0.1 $REMOTE_PORT"
        local response

        response=$(/usr/bin/ssh \
          -i "$SSH_KEY" \
          -o BatchMode=yes \
          -o ConnectTimeout=5 \
          -o StrictHostKeyChecking=accept-new \
          -o ControlMaster=no \
          -o ControlPath=none \
          "$REMOTE_TARGET" \
          "$remote_command" 2>/dev/null) || return 1

        [[ "$response" == *"\\"request_id\\":\\"$request_id\\""* && "$response" == *"\\"approved\\":true"* ]]
      }

      trap cleanup EXIT INT TERM

      log "starting reverse tunnel for $REMOTE_TARGET on remote port $REMOTE_PORT"
      /usr/bin/ssh -NT \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=10 \
        -o ServerAliveCountMax=1 \
        -o TCPKeepAlive=yes \
        -o StrictHostKeyChecking=accept-new \
        -o ControlMaster=no \
        -o ControlPath=none \
        -i "$SSH_KEY" \
        -R "127.0.0.1:$REMOTE_PORT:127.0.0.1:$LOCAL_PORT" \
        "$REMOTE_TARGET" &
      SSH_PID=$!

      sleep 3
      if ! kill -0 "$SSH_PID" 2>/dev/null; then
        wait_for_ssh "$SSH_PID"
        exit $?
      fi

      failures=0
      while kill -0 "$SSH_PID" 2>/dev/null; do
        if health_check; then
          if (( failures > 0 )); then
            log "reverse tunnel health check recovered"
          fi
          failures=0
        else
          failures=$((failures + 1))
          log "reverse tunnel health check failed ($failures/$MAX_FAILURES)"
        fi

        if (( failures >= MAX_FAILURES )); then
          log "reverse tunnel appears stale; exiting so launchd can restart it"
          kill "$SSH_PID" 2>/dev/null || true
          wait_for_ssh "$SSH_PID" || true
          exit 1
        fi

        sleep "$HEALTH_INTERVAL"
      done

      log "ssh process exited; handing restart back to launchd"
      wait_for_ssh "$SSH_PID"
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

  private func tunnelErrorLogURL(for host: TunnelHost) -> URL {
    logsDir.appendingPathComponent("\(appScriptPrefix)-ssh-tunnel-\(host.fileSlug).err.log")
  }

  private func tunnelOutputLogURL(for host: TunnelHost) -> URL {
    logsDir.appendingPathComponent("\(appScriptPrefix)-ssh-tunnel-\(host.fileSlug).out.log")
  }

  private func tunnelStatus(for host: TunnelHost) -> TunnelServiceStatus {
    let label = tunnelLabel(for: host)
    let launchctlOutput = (try? launchctlPrint(label: label)) ?? ""
    let isLoaded = !launchctlOutput.isEmpty
    let isRunning = launchctlOutput.contains("state = running")

    let issue = tunnelIssue(
      host: host,
      launchctlOutput: launchctlOutput,
      stderrTail: recentLogTail(at: tunnelErrorLogURL(for: host)),
      stdoutTail: recentLogTail(at: tunnelOutputLogURL(for: host))
    )

    return TunnelServiceStatus(
      host: host,
      isLoaded: isLoaded,
      isRunning: isRunning,
      issue: issue
    )
  }

  private func tunnelIssue(host: TunnelHost, launchctlOutput: String, stderrTail: String, stdoutTail: String) -> String? {
    if launchctlOutput.isEmpty {
      return "not loaded"
    }

    if !launchctlOutput.contains("state = running") {
      if stderrTail.contains("remote port forwarding failed for listen port") {
        return "remote port \(host.remoteListenPort) is already occupied on the server"
      }

      if stderrTail.localizedCaseInsensitiveContains("operation timed out")
        || stderrTail.localizedCaseInsensitiveContains("connection timed out")
      {
        return "ssh connection timed out"
      }

      if stderrTail.localizedCaseInsensitiveContains("connection refused") {
        return "ssh connection refused"
      }

      if stderrTail.localizedCaseInsensitiveContains("permission denied") {
        return "ssh authentication failed"
      }

      if stdoutTail.contains("reverse tunnel appears stale") || stdoutTail.contains("reverse tunnel health check failed") {
        return "tunnel health checks are failing"
      }

      if launchctlOutput.contains("state = spawn scheduled") {
        return "launchd is retrying after a tunnel failure"
      }

      if launchctlOutput.contains("last exit code = 255") {
        return "ssh exited with code 255"
      }

      return "service is not running"
    }

    if stdoutTail.contains("reverse tunnel appears stale") {
      return "tunnel health checks are failing"
    }

    if stderrTail.contains("remote port forwarding failed for listen port") {
      return nil
    }

    return nil
  }

  private func recentLogTail(at url: URL, maxLines: Int = 20) -> String {
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8) else {
      return ""
    }

    let lines = text
      .split(whereSeparator: \.isNewline)
      .suffix(maxLines)

    return lines.joined(separator: "\n")
  }

  private func launchctlPrint(label: String) throws -> String {
    try runCapture([
      "/bin/launchctl",
      "print",
      "gui/\(getuid())/\(label)"
    ])
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
    let label = plistURL.deletingPathExtension().lastPathComponent
    let command = [
      "/bin/launchctl",
      "bootstrap",
      "gui/\(getuid())",
      plistURL.path
    ]

    for attempt in 1...3 {
      do {
        try run(command, ignoringExitCodes: [37])
        return
      } catch {
        let message = error.localizedDescription
        let isRetryable = message.contains("Bootstrap failed: 5")
          || message.localizedCaseInsensitiveContains("input/output error")

        if isRetryable, ((try? isServiceLoaded(label: label)) == true) {
          return
        }

        if !isRetryable || attempt == 3 {
          throw InstallerError("Failed to load \(label): \(message)")
        }

        try? bootout(label: label)
        Thread.sleep(forTimeInterval: 0.35 * Double(attempt))
      }
    }
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
