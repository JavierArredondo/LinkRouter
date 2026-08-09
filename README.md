# LinkRouter

**Open every link in the right browser — automatically.**

LinkRouter is a local-first macOS menu-bar utility that registers itself as the system handler for `http`/`https`, evaluates your ordered host/path rules, and opens each link in the browser or Chrome profile you chose for it. When no rule matches, it falls back to a keyboard-first picker instead of guessing.

Work links to your work Chrome profile, personal links to Safari, `localhost` to whatever you're debugging in — without ever thinking about it again.

[![CI](https://github.com/JavierArredondo/LinkRouter/actions/workflows/ci.yml/badge.svg)](https://github.com/JavierArredondo/LinkRouter/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## Features

- **Rule-based routing** — match hosts exactly, by wildcard (`*.example.com`), or by regular expression, and narrow further with a path prefix, substring, or regex.
- **Specificity-first precedence** — a narrower rule wins over a broader one regardless of list order; equally specific rules fall back to your manual ordering.
- **Chrome profiles as first-class destinations** — each profile is discovered from Chrome's own profile list and launched directly, not just "whatever window is frontmost".
- **Keyboard-first picker** — unmatched links open a borderless panel: digits and arrows select, `↩` opens, `⌘↩` opens *and* remembers the host as a new rule, `esc` cancels.
- **Preset catalog** — seed rules from a bundled list of common sites in one click. The catalog is plain JSON in the repo ([`Presets/presets.json`](Presets/presets.json)), so adding a site takes a pull request, not Swift.
- **History** — a searchable log of every link LinkRouter opened, with the destination and the rule that decided it. Query strings are dropped before anything is written, so session tokens and tracking parameters never reach disk.
- **History-based suggestions** — LinkRouter proposes rules for the hosts that keep reaching the picker.
- **Fails safe** — a missing or uninstalled destination degrades to the picker; a link is never dropped.
- **Local-first and private** — no network, no account, no telemetry. History stays on your machine, is capped at the last 500 entries, records host and path only — never query strings — and can be turned off or cleared at any time.

## Install

Requires macOS 14+ and Xcode 16+ (Swift 6).

```sh
git clone https://github.com/JavierArredondo/LinkRouter.git
cd LinkRouter
bash Scripts/assemble-app.sh
cp -R build/LinkRouter.app /Applications/
open /Applications/LinkRouter.app
```

Then click **“Use LinkRouter for web links”** in the app.

Two things worth knowing:

- **Install into `/Applications`.** Launch Services largely ignores URL handlers living elsewhere.
- **LinkRouter will not appear in System Settings → Default web browser.** That list is filtered to apps that handle `public.html` documents. The app's own button calls `NSWorkspace.setDefaultApplication` and bypasses the filter.

The bundle is ad-hoc signed for local use. Sign it with a Developer ID certificate and notarize it before distributing.

## Usage

Open **Settings** either from the menu-bar icon or by launching LinkRouter again — opening an already-running copy (Finder, Spotlight, `open -a LinkRouter`) brings up Settings rather than doing nothing. Each rule pairs a host condition (and an optional path condition) with a destination — a browser or a specific Chrome profile.

| Host matcher | Example | Matches | Does not match |
| --- | --- | --- | --- |
| Exact | `github.com` | `github.com` | `docs.github.com` |
| Wildcard | `*.example.com` | `docs.example.com` | `example.com` (apex is excluded by design) |
| Regex | `^(dev\|stg)\..*` | `dev.acme.io` | `www.acme.io` |

Precedence is exact host → regex → wildcard, with a path condition breaking ties upward. Ties beyond that fall back to rule order, so you rarely have to reorder anything by hand.

Runtime state lives in `~/Library/Application Support/LinkRouter/` (`configuration.json`, `history.jsonl`). Delete that folder to reset the app to a first-run state.

## Development

```sh
swift build
swift test
swift test --filter RuleEngineTests    # a single suite
bash Scripts/assemble-app.sh           # -> build/LinkRouter.app
```

The app icon's source is [`Resources/AppIcon.svg`](Resources/AppIcon.svg) — a hand-authored vector, not a binary blob, so it is reviewable in a diff. `Scripts/generate-icon.swift` rasterises it into `AppIcon.icns` and a 1024px PNG during assembly; edit the SVG and rebuild.

`swift run LinkRouter` launches the executable, but it will **not** receive URLs — `CFBundleURLTypes` registration only works from an app bundle. To exercise real routing, assemble the app, move it to `/Applications`, set it as the default handler, and test with `open "https://github.com"`.

### Architecture

Routing and presentation logic is pure and OS-free; everything touching macOS is an adapter. `Routing/`, `Picker/PickerLayout`, and `History/RouteHistoryLog` import only Foundation and are the parts under test.

| Path | Role |
| --- | --- |
| `Routing/` | `URLNormalizer` → `RuleEngine` → `Router.decide`, a pure function returning `.open` / `.ask` / `.reject`. Plus `SitePresets` and `RulePatternValidator`. |
| `App/RoutingCoordinator` | The `@MainActor` singleton owning mutable state; queues incoming URLs and processes them one at a time, because the picker is modal. |
| `Destinations/` | Browser discovery, Chrome profile parsing, default-handler registration, launching. |
| `Picker/` | Pure layout, the SwiftUI view, and the borderless `NSPanel` lifecycle. |
| `Persistence/`, `History/` | `actor`s for file I/O; `RouteHistoryLog` holds the pure format and suggestion logic. |

See [CLAUDE.md](CLAUDE.md) for the full set of design invariants — the non-obvious constraints (why an uncompilable regex must match *nothing*, why Chrome profiles are keyed by identity rather than bundle id, why every async path must resume the coordinator exactly once).

## Status

Implemented: browser and Chrome-profile routing, host/path rules with exact, wildcard and regex matchers, the bundled preset catalog, routing history with suggestions, and the picker.

Known gaps:

- `DestinationKind.nativeApp` is modeled but unimplemented.
- Adapters (`NSWorkspace`, panels, Launch Services) are not injectable and are covered by manual verification rather than tests.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Javier Arredondo Contreras
