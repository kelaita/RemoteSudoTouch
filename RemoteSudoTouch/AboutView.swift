import AppKit
import SwiftUI

struct AboutView: View {
  private let companyName = "Pomace Development Group, LLC"
  private let appRepoURL = URL(string: "https://github.com/kelaita/RemoteSudoTouch")!
  private let linuxRepoURL = URL(string: "https://github.com/kelaita/RemoteSudoTouchLinux")!
  private let macosRepoURL = URL(string: "https://github.com/kelaita/RemoteSudoTouchMacos")!

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
    ZStack {
      LinearGradient(
        colors: [
          Color(nsColor: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 1.0)),
          Color(nsColor: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.90, alpha: 1.0))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 18) {
          AppIconView()

          VStack(alignment: .leading, spacing: 8) {
            Text("RemoteSudoTouch")
              .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(appVersionText)
              .font(.headline)
              .foregroundStyle(.secondary)

            Text(companyName)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("RemoteSudoTouch is a macOS manager app for the Mac side of a Touch ID sudo bridge used by Linux or macOS servers over reverse SSH tunnels.")
            .fixedSize(horizontal: false, vertical: true)

          Text("When you SSH into a remote machine and run `sudo`, approval can happen on your local Mac with Touch ID instead of typing a password on the remote host.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14))

        VStack(alignment: .leading, spacing: 12) {
          AboutSection(
            title: "What It Installs",
            items: [
              "A local `RemoteSudoTouchAgent` listener in Application Support",
              "Per-host reverse SSH tunnel LaunchAgents",
              "A shared configuration snapshot for this Mac"
            ]
          )

          AboutSection(
            title: "Related Projects",
            items: [
              "RemoteSudoTouchLinux for Debian and Ubuntu hosts",
              "RemoteSudoTouchMacos for the macOS `rsudo` wrapper client"
            ]
          )
        }

        VStack(alignment: .leading, spacing: 10) {
          Link(destination: appRepoURL) {
            Label("GitHub: RemoteSudoTouch", systemImage: "link")
          }

          HStack(spacing: 18) {
            Link("Linux helper", destination: linuxRepoURL)
            Link("macOS wrapper", destination: macosRepoURL)
          }
          .font(.subheadline)
        }
        .foregroundStyle(Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.39, blue: 0.68, alpha: 1.0)))

        Spacer(minLength: 0)
      }
      .padding(28)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 540)
  }
}

private struct AppIconView: View {
  var body: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .interpolation(.high)
      .frame(width: 96, height: 96)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(Color.white.opacity(0.7), lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
  }
}

private struct AboutSection: View {
  let title: String
  let items: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        ForEach(items, id: \.self) { item in
          HStack(alignment: .top, spacing: 8) {
            Circle()
              .fill(Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.53, blue: 0.28, alpha: 1.0)))
              .frame(width: 6, height: 6)
              .padding(.top, 6)

            Text(item)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .font(.system(size: 13.5))
    }
  }
}
