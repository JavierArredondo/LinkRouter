# Contributing

Thanks for taking a look. LinkRouter is a small, dependency-free Swift package; contributions are welcome.

## Getting set up

Requires macOS 14+ and Xcode 16+ (Swift 6).

```sh
swift build
swift test
bash Scripts/assemble-app.sh   # -> build/LinkRouter.app
```

To exercise real routing you need an app bundle: assemble it, copy it to `/Applications`, use the app's **“Use LinkRouter for web links”** button, then test with `open "https://github.com"`. `swift run LinkRouter` will start the app but never receives URLs.

Delete `~/Library/Application Support/LinkRouter/` to reset to a first-run state.

## Ground rules

- **Keep routing logic pure.** `Routing/`, `Picker/PickerLayout`, and `Diagnostics/DiagnosticsLog` import only Foundation. New behavior belongs there, with tests — not in the coordinator or an adapter.
- **Add tests for anything in the pure layer.** Adapters (`NSWorkspace`, `NSPanel`, Launch Services) are not injectable; if your change touches one, describe how you verified it by hand in the PR.
- **No dependencies.** The package intentionally has none.
- **Don't break existing configurations.** `AppConfiguration` is `Codable` and a decode failure is treated as corruption, so adding a non-optional property would archive users' rules. Per-destination flags go in `Destination.metadata`.
- **Read the invariants in [CLAUDE.md](CLAUDE.md) before changing routing, the picker, or Chrome profile handling.** They document decisions that look arbitrary but aren't — regex specificity ordering, apex exclusion for wildcards, single-resume of the picker completion, and so on. If you're deliberately changing one, say so in the PR.

## Pull requests

1. Branch off `main`.
2. Make sure `swift build` and `swift test` pass.
3. Keep the change focused, and explain the *why* in the description.
4. If the behavior is user-visible, update `README.md`; if it establishes a new invariant, update `CLAUDE.md`.

## Reporting bugs

Include your macOS version, which browsers and Chrome profiles are installed, the rule set involved (or the relevant part of `configuration.json`), the URL pattern that misrouted, and what you expected instead. Diagnostics — opt-in, in `~/Library/Application Support/LinkRouter/diagnostics.log` — record hosts only and are usually the fastest way to pin down a precedence issue.
