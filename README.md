# Steady

Steady is a native macOS command center for the developer workflow. It combines
a compact Liquid Glass-inspired menu-bar panel with a configurable workspace for
the tools you use while building software.

The app is written in SwiftUI and distributed as a Swift Package executable.

## What it includes

### Menu-bar tools

- **Pull Requests** — lists open GitHub pull requests, CI state, review state,
  owner filters, favourites, and stacked pull-request relationships.
- **Claude Usage** — shows Claude Code session and weekly usage, refreshes
  automatically, and can notify when a configured threshold is reached.
- **Ports** — watches listening development ports, shows network activity, and
  provides quick actions to open a local service or stop its process.
- **Colors** — samples any pixel on screen, copies its hex value, and keeps a
  local colour history.
- **Clipboard** — keeps a local clipboard history and restores an item with one
  click.
- **Code Snap** — opens a dedicated editor for turning a code snippet into a
  shareable image.

### Workspace

The main window supports one, two, three, or four panes. Live panes are
available for Claude Code sessions, Codex sessions, Linear, and Slack, so you
can keep an agent, issues, and messages in the same workspace.

## Integrations

| Integration | What Steady does today | Setup |
| --- | --- | --- |
| **GitHub** | Reads your open pull requests through `gh`, including CI and review state, owner filters, favourites, and stacked PRs. | Run `gh auth login`. |
| **Claude Code** | Shows session/weekly usage, tracks live Claude processes, reads local session metadata, and resumes a selected session in Terminal. | Install and sign in to the `claude` CLI. |
| **Codex** | Detects live Codex processes and lets you resume a selected session in Terminal with `codex resume`. | Install and sign in to the `codex` CLI. |
| **Linear** | Registers a local OAuth client, uses PKCE to sign in, fetches issues assigned to you through Linear MCP, groups them by state, and opens an issue in the browser. | Select **Sign in with Linear** in the workspace. No client secret is required. |
| **Slack** | Connects to the official Slack MCP, stores the OAuth result locally, and discovers the tools available to the connected workspace. | Create a Slack app once, then enter its Client ID and Client Secret in Steady. |

Slack currently establishes and verifies the MCP connection; a full channel and
conversation UI is not exposed in the workspace yet.

## Requirements

- macOS 26 or later
- Xcode 26 or later, including the Command Line Tools
- Swift 6.2

Some tools use local developer utilities when they are available:

- [GitHub CLI](https://cli.github.com/) authenticated with `gh auth login` for
  pull requests.
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) for usage data.
- macOS system tools such as `lsof` for port discovery.

Linear and Slack authorise in the browser. Steady stores their tokens and Slack
client details in the macOS Keychain, not in the repository.

## Run locally

```bash
git clone https://github.com/HugoluizMTB/steady.git
cd steady

swift build
./scripts/bundle.sh debug
open build/Steady.app
```

The bundled app runs as a menu-bar application. Select the Steady icon in the
menu bar to open the tool panel, or use the window launched above for the
workspace.

For an optimized build:

```bash
./scripts/bundle.sh release
open build/Steady.app
```

## Project layout

```text
Sources/
├── Steady/          App shell, workspace, menu-bar panel, Code Snap
├── PRMenubar/       GitHub pull-request integration
├── ClaudeUsage/     Claude Code usage integration
├── PortPilotKit/     Port and network monitoring
├── ColorPickerKit/  Screen colour picker
└── ClipboardKit/     Clipboard history
```

`Package.swift` defines the executable and all local modules. SwiftTerm is the
only external Swift Package dependency.

## Privacy and credentials

Steady does not include credentials in source control. OAuth tokens, Slack
client details, and Linear credentials are stored in the macOS Keychain on the
machine where you connect them. Preferences and local histories remain on that
machine as well.

Before contributing, keep `.env` files, private keys, generated app bundles,
and local screenshots out of Git. The repository's `.gitignore` already covers
those local-only files.

## Development

```bash
swift build
./scripts/bundle.sh debug
```

Run `swift build` before opening a pull request. The project targets the current
macOS 26 SwiftUI APIs, including Liquid Glass.

## License

[MIT](LICENSE)
