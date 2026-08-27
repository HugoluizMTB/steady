<h1 align="center">Steady</h1>

<p align="center">
  A calm, native macOS <b>menu-bar command center</b> for developers.<br>
  Liquid Glass · dark-first · your local Claude Code &amp; Codex sessions, unified.
</p>

---

> **Status:** Phase 1 (foundation) is built and runs. See the
> [roadmap](docs/specs/ROADMAP.md).

## Why

Raycast is *pull* — you invoke it. Steady is *calm push* — it shows you the short
list of what actually needs you, and lets you **resolve and advance**. Two
surfaces, one menu-bar app:

- **Status island** — glanceable dev tools: network meter, open PRs, listening
  ports, color picker, and more.
- **Focus queue** — "only what needs you now": Claude Code / Codex sessions,
  Slack, email, Linear — a finite queue you clear with two actions.

The moat: **local AI coding-agent sessions as first-class citizens** — read,
resume, and drive Claude Code and Codex without leaving the menu bar. Nobody else
does this in a calm, native form.

## Stack

Native **SwiftUI**, macOS 26 (Liquid Glass), Swift 6.2, SwiftPM. Modular by
design — every feature is a `StatusTool` plugin.

```
SteadyKit   core: StatusTool protocol, ToolRegistry, models   (no UI)
SteadyUI    design system: Liquid Glass components, dark theme
Steady      app shell: MenuBarExtra + first-party tools
```

## Run it

Requires macOS 26+ and Xcode 26+.

```bash
swift build
./scripts/bundle.sh debug
open build/Steady.app        # look in the menu bar (hexagon icon)
```

## Write a tool

Everything the user sees is a `StatusTool`. Conform a type, register it — the
shell renders the rest.

```swift
@MainActor @Observable
final class MyTool: StatusTool {
    let id = "dev.my-tool"
    let title = "My Tool"
    let systemImage = "sparkles"
    let placement: ToolPlacement = .island
    func glance() -> AnyView { AnyView(GlassCard { Text("hello") }) }
}
// then in SteadyApp.bootstrap(): registry.register(MyTool())
```

See `Sources/Steady/Tools/NetworkMeterTool.swift` for a complete live example.

## Roadmap

| Phase | What |
|-------|------|
| 1 ✅ | Foundation: shell, design system, plugin registry, network meter |
| 2 | Status island + dev tools (GitHub PRs, Port Pilot, Color Picker) |
| 3 | Focus queue: Snooze/Resolve, resolve-and-advance, ⌘K |
| 4 | Claude Code + Codex sessions |
| 5 | Slack, email, Linear (OAuth / MCP) |
| 6 | Notarized distribution + community tool SDK |

Full specs in [`docs/specs/`](docs/specs/).

## License

MIT — see [LICENSE](LICENSE). Contributions welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md).
