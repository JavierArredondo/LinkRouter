# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project

LinkRouter is a local-first macOS menu-bar utility that registers itself as the system handler for `http`/`https`, evaluates ordered host/path rules, and opens each link in the chosen browser or Chromium profile — falling back to a keyboard-first picker when no rule matches. Swift 6 / SwiftUI + AppKit, SwiftPM, no dependencies, no network, macOS 14+.

## Commands

```sh
swift build
swift test
swift test --filter RuleEngineTests/testWildcardExcludesApexAndIncludesSubdomain   # single test
bash Scripts/assemble-app.sh   # -> build/LinkRouter.app
swift Scripts/generate-presets.swift   # Presets/presets.json -> SitePresets+Generated.swift
```

`swift run LinkRouter` launches the executable, but it will **not** receive URLs: `CFBundleURLTypes` registration only works from an app bundle. To exercise real routing, run `Scripts/assemble-app.sh`, move `build/LinkRouter.app` to `/Applications` (Launch Services largely ignores handlers outside it), then set it as the default web handler and test with `open "https://github.com"`. `Package.swift` deliberately `exclude`s `App/Info.plist` — the assemble script is what copies it into the bundle and then re-signs, because the linker's ad-hoc signature is applied before the plist exists and leaves it unsealed.

macOS will not list LinkRouter in System Settings → Default web browser: that list is filtered to apps handling `public.html` documents. Use the app's own "Use LinkRouter for web links" button, which calls `NSWorkspace.setDefaultApplication` and bypasses the filter. Call it once per scheme sequentially — two concurrent requests race and one reports a spurious failure.

Runtime state lives in `~/Library/Application Support/LinkRouter/` (`configuration.json`, `history.jsonl`). Delete it to reset to a first-run state.

## Architecture

The core rule is that **routing and presentation logic is pure and OS-free; everything that touches macOS is an adapter**. Keep it that way — `Routing/`, `Picker/PickerLayout`, and `History/RouteHistoryLog` import only Foundation and are the only parts under test.

- `Routing/` — `URLNormalizer` (scheme/host validation, lowercasing, percent-encoded path) → `RuleEngine` (matching + precedence) → `Router.decide`, a pure function of `(URL, AppConfiguration, availableBundleIdentifiers)` returning a `RouteDecision` of `.open` / `.ask` / `.reject`. Also `SitePresets` (bundled catalog → generated rules) and `RulePatternValidator` (regex validation at authoring time). No AppKit, no I/O, no singletons.
- `Presets/presets.json` — the source of truth for the preset catalog, compiled in via `SitePresets+Generated.swift`. `Scripts/generate-presets.swift` regenerates it and CI diffs the result, so the two cannot drift.
- `App/RoutingCoordinator` (in `LinkRouterApp.swift`) — the `@MainActor` singleton that owns all mutable state and wires adapters to the Router. It queues incoming URLs and processes them strictly one at a time (`isProcessing` / `finish()` / `processNext()`), because the picker is modal; any new async path must call `finish()` on every branch or routing stalls permanently.
- `Destinations/` — `BrowserRegistry` (discovers handlers, classifies which are real browsers, expands Chrome profiles), `ChromeProfileRegistry` (parses Chrome's `Local State`), `DefaultHandlerService`, `TargetLauncher`. All `@MainActor`.
- `Picker/` — `PickerLayout` (pure ordering and numbering), `QuickPickerView` (SwiftUI), `QuickPickerController` (borderless `NSPanel` lifecycle).
- **`MenuBarExtra` is the only SwiftUI scene.** Settings and onboarding are AppKit `NSWindow`s owned by `HostedWindowController`. The SwiftUI `Settings` and `WindowGroup` scenes were removed because in an `.accessory` app they misbehave: `sendAction(showSettingsWindow:)` returns `true` while no window is ever created, so settings became unreachable. Do not reintroduce them — add windows through the controller instead, and note `isReleasedWhenClosed = false` is what makes a closed window safe to show again.
- `Persistence/ConfigurationStore` and `History/RouteHistoryStore` — `actor`s for file I/O, called from the coordinator via `Task`.

### Invariants that carry design intent

- **Precedence is specificity-first, order-second** (`RuleEngine.specificity`): exact host = 20, **regex = 15**, wildcard = 10, `+1` if a path condition exists; ties break on `Rule.order`. A narrower rule wins even if listed later.
- **Tracking parameters are stripped at launch, not at match time.** Rules match on host and path, so removing query parameters can never change which rule won, and the history keeps the link as clicked. `TrackingParameters.strip` returns the *original* URL when nothing matched — rebuilding it can re-encode characters and hand the browser something subtly different.
- **A globally stripped parameter must be unambiguous.** A false positive silently breaks links, which is worse than leaving a tracker in place; generic names like `s` or `t` are scoped to a host instead. The generator refuses a host-scoped entry that is already global, and a name a prefix already covers.
- **Wildcards exclude the apex.** `*.example.com` matches `docs.example.com` but not `example.com`.
- **A regex pattern is never case-folded.** Lowercasing it would rewrite `\D` into `\d` and invert its meaning, so host patterns get case-insensitivity as a *matching option* instead. Path patterns stay case-sensitive, consistent with prefix/contains.
- **An uncompilable pattern matches nothing, never everything** — the opposite would hijack every link the moment a rule is saved with a typo. `RulePatternValidator` also blocks saving one.
- **Regex input is capped** at `RuleEngine.maximumMatchLength`. Matching runs on the main thread while routing is serialized, so catastrophic backtracking would freeze the UI *and* every queued link. The cap bounds exposure to pattern complexity rather than URL length; it does not eliminate the risk.
- **Recursion guard.** Destinations whose bundle id equals LinkRouter's own are filtered out of candidates and force `.ask` rather than `.open` — routing to self would loop forever.
- **Failures degrade to the picker, never to a dropped link.** A missing or uninstalled destination yields `.ask` with an explanatory message; only a malformed/non-web URL yields `.reject`.
- **The picker must resume the coordinator exactly once.** `QuickPickerController` nils its stored completion before invoking it, and treats `windowWillClose` / `windowDidResignKey` as cancellation. Any dismissal path that fails to report back leaves `isProcessing` true and silently queues every later link forever.
- **A borderless `NSPanel` refuses key status** unless `canBecomeKey` is overridden, which would kill every keyboard shortcut. Click-away dismissal is gated on having become key at least once, so a panel that never takes focus cannot cancel itself on appearance.
- **Chromium profiles are destinations, not a separate concept.** `ChromiumProfileRegistry` holds a table of Chromium-family browsers (bundle id + user-data path) and parses each one's `Local State` into one `Destination` per profile. One parser and one launch path serve the whole family because they share the format and the `--profile-directory` flag. Because every profile of a browser shares its bundle id, **identity is `Destination.identityKey`, never `bundleIdentifier`** — keying by bundle id collapses the profiles into one and trips the duplicate-key trap in `Dictionary(uniqueKeysWithValues:)`.
- **`DestinationKind.chromiumProfile` and the profile metadata key keep their original raw values** (`"chromeProfile"`, `"chromeProfileDirectory"`) even though the Swift names generalised. Changing a persisted raw value would fail to decode existing `configuration.json` files, and a decode failure is treated as corruption and archives the file.
- **Profile launches need `createsNewApplicationInstance = true`** and the URL passed as a command-line argument. macOS silently drops `OpenConfiguration.arguments` for an already-running app, so without the new-instance flag the link lands in whatever profile is frontmost. The browser's singleton forwards the new process's command line to the live instance. Verified against a running Chrome with three profiles; only Chrome is verified empirically, the rest rely on shared Chromium behaviour.
- **Each browser's on-disk format is untrusted.** Any parse failure returns an empty profile list for that browser, degrading to its plain destination rather than breaking routing.
- **`refreshDestinations` keeps the stored `id` but takes fresh name and metadata** from discovery. Rules target the id, so it must survive; preserving the whole stored destination instead would freeze renames and never deliver newly introduced metadata keys.
- **Destination metadata carries new per-destination flags, not `AppConfiguration`.** Adding a non-optional property to that `Codable` struct breaks decoding of existing `configuration.json` files, and `ConfigurationStore.load` treats a decode failure as corruption and archives the file — losing the user's rules.
- **Uninstalled browsers are retained** in `configuration.destinations` so existing rules stay repairable instead of silently breaking.
- **Corrupt config is moved aside**, not deleted: renamed to `configuration.corrupt-<epoch>.json`, returning defaults.
- **The preset catalog is generated, not parsed at launch.** `Presets/presets.json` exists so a preset can be contributed without writing Swift, but reading it at runtime would put a bundle lookup, file I/O and a decode failure into `Routing/`, which is the layer that must stay pure — and would mean shipping a catalog that can arrive empty. The generator validates instead: unknown modes, duplicate ids or hosts, uncompilable regexes, and a wildcard missing its leading `*.` all fail the build rather than becoming a dead rule in a user's configuration. **Never hand-edit `SitePresets+Generated.swift`**; CI regenerates and runs `git diff --exit-code`.
- **History records host and path, never the query string.** It is stripped in `HistoryEntry.make` on the way in rather than hidden on the way out, because query strings carry session tokens, password-reset links and tracking parameters. Do not "improve" this by storing the full URL.
- **History is on by default** (`AppConfiguration.historyEnabled` is `Bool?`, absent meaning on). It must never interrupt routing — write errors are swallowed by design — and it is the single source for rule suggestions, which are derived from entries whose outcome is `.picker` or `.fallback`.
- **`history.jsonl` is one JSON object per line** so appending is cheap; it overshoots the 500-entry cap and is compacted in batches. A line that fails to parse is skipped rather than failing the read, so an interrupted write costs one entry instead of the whole history.
- **The history outcome is recorded after the launch attempt**, so a destination that refused to open is logged as `.failed` rather than as a success.

## Testing

`Tests/LinkRouterTests/` covers the pure layer via `@testable import`: rule matching and precedence, Chrome profile parsing, picker layout, regex semantics, preset de-duplication, and the history log format and suggestions. Adapters (`NSWorkspace`, panels, Launch Services) are not injectable and are unverified by tests — verify those by hand against a real install. When adding behavior, extend the pure layer and cover it there rather than pushing logic into the coordinator.

Chrome profile routing is verifiable without a UI: compare `stat -f '%Sm' ~/Library/Application\ Support/Google/Chrome/<Profile>/Sessions` before and after opening a link, and confirm only the targeted profile's timestamp moved.

## Known state

Implemented: browser and Chrome-profile routing, host/path rules with exact, wildcard and regex matchers, the bundled preset catalog, history-based suggestions, and the borderless picker. `DestinationKind.nativeApp` is modeled but unimplemented.

Settings is reachable from the menu-bar icon **and** by relaunching the app: `applicationShouldHandleReopen` opens it, which is what makes Finder/Spotlight/`open -a` do something visible for a Dock-less app.

The `.build/` and `build/` directories are local artifacts and are gitignored, as is `.Codex/settings.local.json`. The repository is `github.com/JavierArredondo/LinkRouter` (public, MIT); CI runs `swift build`, `swift test`, and the assemble script on `macos-15`.
