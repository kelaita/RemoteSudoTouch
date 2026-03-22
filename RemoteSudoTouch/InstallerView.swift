import AppKit
import SwiftUI

struct InstallerView: View {
  @StateObject var viewModel: InstallerViewModel
  @Environment(\.colorScheme) private var colorScheme

  private let accentGreen = Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.53, blue: 0.28, alpha: 1.0))
  private let accentRed = Color(nsColor: NSColor(calibratedRed: 0.70, green: 0.19, blue: 0.18, alpha: 1.0))
  private let accentBlue = Color(nsColor: NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.69, alpha: 1.0))
  private let accentAmber = Color(nsColor: NSColor(calibratedRed: 0.74, green: 0.49, blue: 0.12, alpha: 1.0))

  private var canvasColors: [Color] {
    if colorScheme == .dark {
      return [
        Color(nsColor: .windowBackgroundColor),
        Color(nsColor: .underPageBackgroundColor),
        Color(nsColor: .controlBackgroundColor)
      ]
    }

    return [
      Color(nsColor: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.94, alpha: 1.0)),
      Color(nsColor: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.92, alpha: 1.0)),
      Color(nsColor: .windowBackgroundColor)
    ]
  }

  private var cardColor: Color {
    Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .textBackgroundColor)
      .opacity(colorScheme == .dark ? 0.92 : 0.9)
  }

  private var cardBorder: Color {
    Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.75 : 0.45)
  }

  private var headerGradientColors: [Color] {
    if colorScheme == .dark {
      return [
        Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 1.0)),
        Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1.0))
      ]
    }

    return [
      Color.white.opacity(0.96),
      Color(nsColor: NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.89, alpha: 1.0))
    ]
  }

  private var serviceStatusIcon: String {
    switch viewModel.serviceStatus.health {
    case .running:
      return "checkmark.circle.fill"
    case .partial:
      return "exclamationmark.triangle.fill"
    case .stopped:
      return "stop.circle.fill"
    }
  }

  private var serviceStatusColor: Color {
    switch viewModel.serviceStatus.health {
    case .running:
      return accentGreen
    case .partial:
      return accentAmber
    case .stopped:
      return accentRed
    }
  }

  private var serviceStatusText: String {
    switch viewModel.serviceStatus.health {
    case .running:
      return "Running"
    case .partial:
      return "Partially Running"
    case .stopped:
      return "Stopped"
    }
  }

  private var appVersionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let shortVersion = info["CFBundleShortVersionString"] as? String
    let buildNumber = info["CFBundleVersion"] as? String

    switch (shortVersion, buildNumber) {
    case let (version?, build?) where !version.isEmpty && !build.isEmpty:
      return "Version \(version) (\(build))"
    case let (version?, _) where !version.isEmpty:
      return "Version \(version)"
    case let (_, build?) where !build.isEmpty:
      return "Build \(build)"
    default:
      return "Development Build"
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          header
          settingsSection
          serversSection
          serviceSection
          actionsSection
          statusSection
          footer
        }
        .padding(18)
      }
      .onChange(of: viewModel.statusRevealToken) { _, _ in
        DispatchQueue.main.async {
          withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo("status-section", anchor: .top)
          }
        }
      }
    }
    .background(
      LinearGradient(
        colors: canvasColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .alert("Configuration applied", isPresented: $viewModel.showSuccess) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("The Touch ID agent and all configured reverse tunnel services were updated and refreshed.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("RemoteSudoTouch")
        .font(.system(size: 26, weight: .bold, design: .rounded))
        .foregroundStyle(.primary)

      Text("Configure one local Touch ID agent and multiple reverse SSH tunnels so several remote servers can request sudo approval from this Mac.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        badge("Local agent", color: accentGreen)
        badge("Multi-server tunnels", color: accentBlue)
        badge("LaunchAgent managed", color: accentAmber)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 24)
        .fill(
          LinearGradient(
            colors: headerGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 24)
        .stroke(cardBorder, lineWidth: 1)
    )
  }

  private var settingsSection: some View {
    sectionCard(title: "Agent Settings", systemImage: "touchid") {
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
        GridRow(alignment: .center) {
          fieldLabel("SSH private key")
          HStack(spacing: 10) {
            TextField("~/.ssh/id_ed25519", text: $viewModel.sshKeyPath)
              .textFieldStyle(.roundedBorder)

            Button("Browse…") {
              viewModel.pickSSHKey()
            }
            .buttonStyle(.bordered)
          }
        }

        GridRow {
          fieldLabel("Local agent port")
          TextField("8765", text: $viewModel.localAgentPort)
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var serversSection: some View {
    sectionCard(title: "Remote Servers", systemImage: "server.rack") {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          List(selection: $viewModel.selectedHostID) {
            ForEach($viewModel.hosts) { $host in
              VStack(alignment: .leading, spacing: 3) {
                Text(host.displayName)
                  .font(.system(size: 13, weight: .semibold))
                Text("\(host.remoteUser.isEmpty ? "ubuntu" : host.remoteUser)@\(host.remoteHost.isEmpty ? "<hostname>" : host.remoteHost):\(host.remoteListenPort)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 2)
              .tag(host.id)
            }
          }
          .frame(minWidth: 260, minHeight: 180)
          .scrollContentBackground(.hidden)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
          )

          HStack(spacing: 10) {
            Button("Add Server") {
              viewModel.addHost()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentBlue)

            Button("Remove Server") {
              viewModel.removeSelectedHost()
            }
            .buttonStyle(.bordered)
            .tint(accentRed)
            .disabled(viewModel.hosts.count <= 1)
          }
        }
        .frame(width: 290)

        Rectangle()
          .fill(cardBorder.opacity(0.7))
          .frame(width: 1)
          .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 10) {
          if let selectedHostIndex = viewModel.selectedHostIndex {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
              GridRow {
                fieldLabel("Display name")
                TextField("prod-db", text: $viewModel.hosts[selectedHostIndex].name)
                  .textFieldStyle(.roundedBorder)
              }

              GridRow {
                fieldLabel("Remote user")
                TextField("ubuntu", text: $viewModel.hosts[selectedHostIndex].remoteUser)
                  .textFieldStyle(.roundedBorder)
              }

              GridRow {
                fieldLabel("Remote host")
                TextField("server.example.com", text: $viewModel.hosts[selectedHostIndex].remoteHost)
                  .textFieldStyle(.roundedBorder)
              }

              GridRow {
                fieldLabel("Remote port")
                TextField("9876", text: $viewModel.hosts[selectedHostIndex].remoteListenPort)
                  .textFieldStyle(.roundedBorder)
                  .frame(width: 120)
              }
            }

            Text("Each server gets its own reverse SSH tunnel LaunchAgent. The local Touch ID agent is shared.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .padding(.top, 4)
          } else {
            Text("Select a server to edit its connection details.")
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var serviceSection: some View {
    sectionCard(title: "Services", systemImage: "switch.2") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("Load services at login", isOn: $viewModel.launchAtLogin)
        Toggle("Keep services alive", isOn: $viewModel.keepAlive)

        Rectangle()
          .fill(cardBorder.opacity(0.7))
          .frame(height: 1)
          .padding(.vertical, 2)

        LabeledContent("App Support") {
          Text(viewModel.supportDir.path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }

        LabeledContent("LaunchAgents") {
          Text(viewModel.launchAgentsDir.path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }
      }
    }
  }

  private var actionsSection: some View {
    sectionCard(title: "Actions", systemImage: "bolt.circle") {
      HStack(alignment: .center, spacing: 14) {
        HStack(spacing: 10) {
          Image(systemName: serviceStatusIcon)
            .foregroundStyle(serviceStatusColor)
          VStack(alignment: .leading, spacing: 2) {
            Text(serviceStatusText)
              .font(.system(size: 13, weight: .semibold))
            Text("Agent: \(viewModel.serviceStatus.agentRunning ? "running" : "stopped") | Tunnels: \(viewModel.serviceStatus.runningTunnels)/\(viewModel.serviceStatus.totalTunnels)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 14)
            .fill(serviceStatusColor.opacity(0.10))
        )

        HStack(spacing: 12) {
          Button("Install") {
            Task { await viewModel.install() }
          }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .tint(accentGreen)
          .disabled(viewModel.isBusy)

          Button("Validate SSH") {
            Task { await viewModel.validateSetup() }
          }
          .buttonStyle(.bordered)
          .tint(accentBlue)
          .disabled(viewModel.isBusy)

          Button("Start") {
            Task { await viewModel.startServices() }
          }
          .buttonStyle(.borderedProminent)
          .tint(accentGreen)
          .disabled(viewModel.isBusy)

          Button("Stop") {
            Task { await viewModel.stopServices() }
          }
          .buttonStyle(.bordered)
          .tint(accentRed)
          .disabled(viewModel.isBusy)

          Button("Reload") {
            Task { await viewModel.reloadServices() }
          }
          .buttonStyle(.bordered)
          .tint(accentAmber)
          .disabled(viewModel.isBusy)

          Button("Uninstall", role: .destructive) {
            Task { await viewModel.uninstall() }
          }
          .buttonStyle(.borderedProminent)
          .tint(accentRed)
          .disabled(viewModel.isBusy)

          Spacer(minLength: 0)

          Button("Open Support Folder") {
            NSWorkspace.shared.open(viewModel.supportDir)
          }
          .buttonStyle(.bordered)
          .disabled(viewModel.isBusy)
        }
      }
    }
    .onAppear {
      viewModel.refreshServiceStatus()
    }
  }

  private var statusSection: some View {
    sectionCard(title: "Status", systemImage: "list.bullet.rectangle") {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(viewModel.statusLines.enumerated()), id: \.offset) { index, line in
              Text(line)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .id(index)
            }
          }
          .padding(12)
        }
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 190)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(cardBorder.opacity(0.75), lineWidth: 1)
        )
        .onAppear {
          scrollToBottom(with: proxy)
        }
        .onChange(of: viewModel.statusLines.count) { _, _ in
          scrollToBottom(with: proxy)
        }
      }
    }
    .id("status-section")
  }

  private var footer: some View {
    HStack {
      Spacer()
      Text(appVersionText)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(.horizontal, 6)
    }
  }

  private func sectionCard<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.headline)

      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 22)
        .fill(cardColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 22)
        .stroke(cardBorder, lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
  }

  private func badge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        Capsule()
          .fill(color.opacity(0.14))
      )
      .foregroundStyle(color)
  }

  private func fieldLabel(_ title: String) -> some View {
    Text(title)
      .foregroundStyle(.secondary)
      .frame(width: 130, alignment: .leading)
  }

  private func scrollToBottom(with proxy: ScrollViewProxy) {
    guard let lastIndex = viewModel.statusLines.indices.last else {
      return
    }

    DispatchQueue.main.async {
      proxy.scrollTo(lastIndex, anchor: .bottom)
    }
  }
}
