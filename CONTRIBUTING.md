# Contributing to Steady

Thanks for helping build a calmer way to work.

## Ground rules

- **Everything is a `StatusTool`.** New capabilities are new tools, not new shell
  code. If you find yourself special-casing a tool inside `Sources/Steady/*Panel*`,
  stop — push it behind the protocol.
- **UI goes through `SteadyUI`.** No raw `.glassEffect`, color literals, or ad-hoc
  spacing in tools. Extend the design system instead.
- **`SteadyKit` stays UI-free.** Core protocols/models must not import the app.
- **Dark-first, restrained motion.** Match macOS-native easing; no flashy
  animation for its own sake.

## Dev setup

Requires macOS 26+, Xcode 26+, Swift 6.2.

```bash
swift build          # compile
./scripts/bundle.sh debug && open build/Steady.app   # run in the menu bar
swift test           # once tests exist
```

## Adding a tool

1. Create `Sources/Steady/Tools/YourTool.swift` conforming to `StatusTool`.
2. Register it in `SteadyApp.bootstrap()`.
3. Keep the glance row grammar: icon · title/subtitle · trailing `StatPill`.
4. Secrets → Keychain, never `UserDefaults` or source.

## Pull requests

- One focused change per PR. Explain the *why*.
- Run `swift build` clean (no new warnings) before opening.
- Reference the relevant `docs/specs/` phase.

## Roadmap & scope

See [`docs/specs/ROADMAP.md`](docs/specs/ROADMAP.md). Building foundation-up —
please don't open PRs for a phase whose predecessors aren't merged.
