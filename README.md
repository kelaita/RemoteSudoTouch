# RemoteSudoTouch

`RemoteSudoTouch` is a macOS SwiftUI installer app for the macOS side of a Touch ID sudo bridge used by Ubuntu over a reverse SSH tunnel.

## Targets

- `RemoteSudoTouch`: macOS SwiftUI app that installs and manages the bridge.
- `RemoteSudoTouchAgent`: macOS command-line tool that listens on localhost, prompts with Touch ID, and returns JSON approval responses.

## What the app installs

- `~/Library/Application Support/RemoteSudoTouch/RemoteSudoTouchAgent`
- `~/Library/Application Support/RemoteSudoTouch/RemoteSudoTouch-agent.sh`
- `~/Library/Application Support/RemoteSudoTouch/RemoteSudoTouch-ssh-tunnel.sh`
- `~/Library/Application Support/RemoteSudoTouch/installer-config.json`
- `~/Library/LaunchAgents/com.paul.remotesudotouch.agent.plist`
- `~/Library/LaunchAgents/com.paul.remotesudotouch.tunnel.plist`

## Service model

- Ubuntu runs `pam_exec` and connects to `localhost:9876`.
- The Ubuntu machine must establish a path back through the reverse SSH tunnel to the Mac.
- The macOS tunnel LaunchAgent runs `ssh -NT -R 127.0.0.1:<remotePort>:127.0.0.1:<localPort> user@host`.
- The macOS agent LaunchAgent runs the bundled `RemoteSudoTouchAgent --port <localPort>`.

## Xcode notes

- Open the project at `/Users/paul/Xcode/RemoteSudoTouch/RemoteSudoTouch.xcodeproj`.
- App Sandbox is disabled in build settings because the app writes into `~/Library/LaunchAgents` and `~/Library/Application Support`.
- The app target depends on `RemoteSudoTouchAgent` and embeds its built binary into app resources.
- Set your signing team in Xcode before archiving.

## First run checklist

1. Build the project once so the embedded `RemoteSudoTouchAgent` binary exists in the app bundle resources.
2. Launch the app and fill in the Ubuntu username, hostname, SSH key path, and ports.
3. Run `Validate SSH` before installing if the host has not been contacted from this Mac yet.
4. Click `Install / Update` to copy the agent, write LaunchAgents, and reload services.

## Limitations

- The installer currently accepts new host keys with `StrictHostKeyChecking=accept-new`.
- The app assumes user-scoped `launchctl bootstrap gui/<uid>`.
- The binary is copied from built products into app resources; verify the target dependency and copy phase remain intact if you edit the project.
