# RemoteSudoTouch

`RemoteSudoTouch` is a macOS SwiftUI manager app for the macOS side of a Touch ID sudo bridge used by a Linux or macOS server over a reverse SSH tunnel.

The problem this is solving: you're on your Mac and you're SSH'ed into a remote Mac or Linux server.  Any sudo calls on those remote servers will prompt you with the local touchID dialog box on your local Mac to approve the sudo.

The Linux helper package lives here:
[RemoteSudoTouchLinux](https://github.com/kelaita/RemoteSudoTouchLinux)

The macOS `rsudo` wrapper client lives here:
[RemoteSudoTouchMacos](https://github.com/kelaita/RemoteSudoTouchMacos)

## Targets

- `RemoteSudoTouch`: macOS SwiftUI app that installs and manages the bridge.
- `RemoteSudoTouchAgent`: macOS command-line tool that listens on localhost, prompts with Touch ID, and returns JSON approval responses.

## What the app installs

- `~/Library/Application Support/RemoteSudoTouch/RemoteSudoTouchAgent`
- `~/Library/Application Support/RemoteSudoTouch/RemoteSudoTouch-agent.sh`
- `~/Library/Application Support/RemoteSudoTouch/RemoteSudoTouch-ssh-tunnel.sh`
- `~/Library/Application Support/RemoteSudoTouch/installer-config.json`
- `~/Library/LaunchAgents/net.pomace.remotesudotouch.agent.plist`
- `~/Library/LaunchAgents/net.pomace.remotesudotouch.tunnel.plist`

## Service model

- Linux runs `pam_exec` and connects to `localhost:9876`.
- The Linux machine must establish a path back through the reverse SSH tunnel to the Mac.
- The macOS tunnel LaunchAgent runs `ssh -NT -R 127.0.0.1:<remotePort>:127.0.0.1:<localPort> user@host`.
- The macOS agent LaunchAgent runs the bundled `RemoteSudoTouchAgent --port <localPort>`.

## Xcode notes

- Open `RemoteSudoTouch.xcodeproj` in Xcode.
- App Sandbox is disabled in build settings because the app writes into `~/Library/LaunchAgents` and `~/Library/Application Support`.
- The app target depends on `RemoteSudoTouchAgent` and embeds its built binary into app resources.
- Set your signing team in Xcode before archiving.

## Packaging

- `scripts/build-pkg.sh` builds a Release archive, creates a component package, and wraps it in a final installer package.
- By default it produces an unsigned installer in `dist/RemoteSudoTouch-<version>.pkg`.
- The repo may also already include a prebuilt installer in `dist/`, which can be used directly without rebuilding the package first.
- To sign the installer package, set one or both of these environment variables before running it:
  - `PKG_SIGNING_IDENTITY="Developer ID Installer: ..."`
  - `APP_SIGNING_IDENTITY="Developer ID Application: ..."`
- Example:

```bash
./scripts/build-pkg.sh
```

```bash
APP_SIGNING_IDENTITY="Developer ID Application: Pomace Development Group, LLC" \
PKG_SIGNING_IDENTITY="Developer ID Installer: Pomace Development Group, LLC" \
./scripts/build-pkg.sh
```

## First run checklist

1. Build the project once so the embedded `RemoteSudoTouchAgent` binary exists in the app bundle resources.
2. Launch the app and fill in the Linux username, hostname, SSH key path, and ports.
3. Run `Validate SSH` before applying configuration if the host has not been contacted from this Mac yet.
4. Click `Install` to copy the agent, write LaunchAgents, and reload services.

## Limitations

- The manager currently accepts new host keys with `StrictHostKeyChecking=accept-new`.
- The app assumes user-scoped `launchctl bootstrap gui/<uid>`.
- The binary is copied from built products into app resources; verify the target dependency and copy phase remain intact if you edit the project.
