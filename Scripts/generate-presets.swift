#!/usr/bin/env swift
//
// Generates Sources/LinkRouter/Routing/SitePresets+Generated.swift from Presets/presets.json.
//
//   swift Scripts/generate-presets.swift
//
// The JSON is the source of truth so a preset can be contributed without writing Swift, but the
// catalog is still compiled in: reading it at runtime would put file I/O and a parse failure into
// Routing/, which is deliberately pure and OS-free. CI regenerates and diffs, so a hand-edited
// generated file — or a JSON change that was never regenerated — fails the build instead of
// shipping a catalog that does not match the repository.
//
// This script is standalone by necessity: it runs before/independently of the package build, so it
// cannot import LinkRouter and redeclares the shapes it needs.

import Foundation

// MARK: - Input

struct PresetHostSpec: Decodable {
    let host: String
    let mode: String?
}

struct PresetSpec: Decodable {
    let id: String
    let title: String
    let detail: String
    let hosts: [PresetHostSpec]
}

struct Catalog: Decodable {
    let presets: [PresetSpec]
}

// MARK: - Paths

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let inputURL = projectRoot.appendingPathComponent("Presets/presets.json")
let outputURL = projectRoot.appendingPathComponent("Sources/LinkRouter/Routing/SitePresets+Generated.swift")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Load

guard let data = try? Data(contentsOf: inputURL) else {
    fail("cannot read \(inputURL.path)")
}

let catalog: Catalog
do {
    catalog = try JSONDecoder().decode(Catalog.self, from: data)
} catch {
    fail("\(inputURL.lastPathComponent) is not valid: \(error)")
}

// MARK: - Validate
//
// Every check here is a rule the app would otherwise discover at runtime, where the cost is a
// silently dead or overly broad rule in someone's configuration.

let validModes = ["exact", "wildcard", "regex"]
var seenIDs = Set<String>()

guard !catalog.presets.isEmpty else { fail("the catalog is empty") }

for preset in catalog.presets {
    let where_ = "preset '\(preset.id)'"

    guard !preset.id.trimmingCharacters(in: .whitespaces).isEmpty else { fail("a preset has an empty id") }
    guard seenIDs.insert(preset.id).inserted else { fail("duplicate preset id '\(preset.id)'") }
    guard preset.id == preset.id.lowercased(), !preset.id.contains(" ") else {
        fail("\(where_): id must be lowercase and space-free — it is a stable key, not a label")
    }
    guard !preset.title.isEmpty else { fail("\(where_) has an empty title") }
    guard !preset.detail.isEmpty else { fail("\(where_) has an empty detail") }
    guard !preset.hosts.isEmpty else { fail("\(where_) has no hosts") }

    var seenHosts = Set<String>()
    for entry in preset.hosts {
        let host = entry.host.trimmingCharacters(in: .whitespaces)
        let mode = entry.mode ?? "exact"

        guard !host.isEmpty else { fail("\(where_) has an empty host") }
        guard validModes.contains(mode) else {
            fail("\(where_), host '\(host)': unknown mode '\(mode)' — use \(validModes.joined(separator: ", "))")
        }
        guard seenHosts.insert("\(mode):\(host.lowercased())").inserted else {
            fail("\(where_): duplicate host '\(host)' (\(mode))")
        }

        switch mode {
        case "exact":
            guard !host.contains("*") else {
                fail("\(where_): '\(host)' looks like a wildcard but is declared exact")
            }
            guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
                fail("\(where_): '\(host)' is not a valid host")
            }
        case "wildcard":
            // RuleEngine matches a wildcard as a "." + suffix check, so a pattern without the
            // leading "*." reads as covering the apex when it never will.
            guard host.hasPrefix("*.") else {
                fail("\(where_): wildcard '\(host)' must start with '*.' — wildcards never match the apex")
            }
            let suffix = String(host.dropFirst(2))
            guard !suffix.isEmpty, suffix.contains("."), !suffix.contains("*") else {
                fail("\(where_): wildcard '\(host)' must be '*.' followed by a plain host")
            }
        case "regex":
            guard (try? NSRegularExpression(pattern: host)) != nil else {
                fail("\(where_): '\(host)' is not a valid regular expression")
            }
        default:
            fail("unreachable")
        }
    }
}

// MARK: - Emit

func swiftLiteral(_ value: String) -> String {
    var escaped = ""
    for character in value {
        switch character {
        case "\\": escaped += "\\\\"
        case "\"": escaped += "\\\""
        case "\n": escaped += "\\n"
        case "\t": escaped += "\\t"
        default: escaped.append(character)
        }
    }
    return "\"\(escaped)\""
}

var out = """
// Generated by Scripts/generate-presets.swift from Presets/presets.json. Do not edit.
//
// Add or change a preset in Presets/presets.json, then run:
//
//     swift Scripts/generate-presets.swift

extension SitePresets {
    static let all: [SitePreset] = [

"""

for (presetIndex, preset) in catalog.presets.enumerated() {
    out += """
            SitePreset(
                id: \(swiftLiteral(preset.id)),
                title: \(swiftLiteral(preset.title)),
                detail: \(swiftLiteral(preset.detail)),
                hosts: [

    """
    for (hostIndex, entry) in preset.hosts.enumerated() {
        let host = entry.host.trimmingCharacters(in: .whitespaces)
        let mode = entry.mode ?? "exact"
        let arguments = mode == "exact"
            ? swiftLiteral(host)
            : "\(swiftLiteral(host)), .\(mode)"
        let comma = hostIndex == preset.hosts.count - 1 ? "" : ","
        out += "                PresetHost(\(arguments))\(comma)\n"
    }
    out += "            ]\n"
    out += presetIndex == catalog.presets.count - 1 ? "        )\n" : "        ),\n"
}

out += """
    ]
}

"""

// Only rewrite on an actual change, so a no-op run does not churn file timestamps.
let existing = try? String(contentsOf: outputURL, encoding: .utf8)
if existing != out {
    do {
        try out.write(to: outputURL, atomically: true, encoding: .utf8)
    } catch {
        fail("cannot write \(outputURL.path): \(error)")
    }
    print("Wrote \(outputURL.lastPathComponent)")
} else {
    print("\(outputURL.lastPathComponent) is up to date")
}

let hostCount = catalog.presets.reduce(0) { $0 + $1.hosts.count }
print("\(catalog.presets.count) presets, \(hostCount) hosts")
