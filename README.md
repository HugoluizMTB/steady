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

The main window supports one, two, three, or four panes. Live panes cover Claude
Code and Codex sessions, GitHub, Calendar, Mail, Notion, and Linear — so an
agent, your schedule, inbox, docs, and issues share one window. Slack and Figma
are marked *coming soon*.

The top bar dims each tool by default and lights it up with a count badge when it
has activity — a running session, unread mail, or new GitHub notifications.

On first launch an onboarding screen explains that everything stays on this Mac
and lets you connect each account once.

## Integrations

Every integration reads what is already on your Mac. Nothing is uploaded, and no
Steady account exists.

| Integration | What Steady does | Setup |
| --- | --- | --- |
| **Claude Code** | Live session board (running / done), usage, local session metadata; resume a session in Terminal. | Install the `claude` CLI. |
| **Codex** | The same session board for Codex; resume with `codex resume`. | Install the `codex` CLI. |
| **GitHub** | Notifications inbox, your open and review-requested pull requests, and repositories — through `gh`. The menu bar also lists open PRs with CI/review state and stacked relationships. | Run `gh auth login`. |
| **Calendar** | Reads every calendar account already on this Mac (iCloud, Google, Exchange) via EventKit. Agenda and month views, add events, and Join buttons for Meet/Zoom/Teams links. | Grant Calendar access when asked. |
| **Mail** | Reads and sends through the Mail app already set up on this Mac via AppleScript — sender filtering, message view, compose, and reply. No login. | Allow Automation for Mail when asked. |
| **Notion** | Registers a local OAuth client with Notion's MCP, signs in with PKCE, and searches your workspace. | Select **Sign in with Notion**. No app or key to create. |
| **Linear** | Registers a local OAuth client, signs in with PKCE, and fetches issues assigned to you through Linear MCP, grouped by state. | Select **Sign in with Linear**. No client secret. |
| **Slack** | *Coming soon.* | — |
| **Figma** | *Coming soon.* | — |

## Requirements

- macOS 26 or later
- Xcode 26 or later, including the Command Line Tools
- Swift 6.2

Some tools use local developer utilities and system permissions:

- [GitHub CLI](https://cli.github.com/) authenticated with `gh auth login`.
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and the `codex`
  CLI for the session board.
- macOS system tools such as `lsof` for port discovery.
- Calendar access (EventKit) for the Calendar tool, and Automation access for
  the Mail tool — both granted through the standard macOS permission prompts.

Notion and Linear authorise in the browser with PKCE and register themselves
dynamically, so there is no app to create and no secret to paste. Steady stores
every token in the macOS Keychain, never in the repository.

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

Steady has no server and no account. Calendars, mail, and code sessions are read
live from the apps already on your Mac; GitHub goes through your local `gh`. OAuth
tokens for Notion and Linear live in the macOS Keychain on the machine where you
connect them. Preferences and local histories stay on that machine. Nothing is
uploaded or sent to the cloud.

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
