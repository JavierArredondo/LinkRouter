import AppKit
import SwiftUI

struct PlaygroundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: RoutingCoordinator
    @State private var text = ""
    @State private var source: String?

    private var explanation: RouteExplanation? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return coordinator.explain(url, from: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test a link").font(.title3.bold())
            Text("Paste a URL to see which rule wins and why, without opening anything.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("https://example.com/path", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            Picker("Opened from", selection: $source) {
                Text("Any app").tag(String?.none)
                ForEach(coordinator.sourceCandidates()) { Text($0.name).tag(String?.some($0.bundleIdentifier)) }
            }

            if let explanation {
                result(explanation)
            } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Label("That is not a URL.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            Spacer(minLength: 0)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
        }
        .padding()
        .frame(width: 520, height: 420)
    }

    @ViewBuilder
    private func result(_ explanation: RouteExplanation) -> some View {
        if let error = explanation.error {
            Label("Rejected: \(String(describing: error))", systemImage: "xmark.octagon.fill")
                .font(.callout).foregroundStyle(.orange)
        } else {
            Form {
                Section("Normalised") {
                    LabeledContent("Host", value: explanation.host ?? "—")
                    LabeledContent("Path", value: explanation.path?.isEmpty == false ? explanation.path! : "/")
                    if let stripped = explanation.strippedURL {
                        LabeledContent("Cleaned") { Text(stripped.absoluteString).font(.caption.monospaced()).lineLimit(2) }
                    }
                }

                Section("Rules that match") {
                    if explanation.candidates.isEmpty {
                        Text("None — this link would open the picker.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(explanation.candidates, id: \.rule.id) { candidate in
                            HStack(spacing: 8) {
                                Image(systemName: candidate.isWinner ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(candidate.isWinner ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(candidate.rule.match.host)
                                        .font(candidate.rule.match.hostMode == .regex ? .body.monospaced() : .body)
                                        .lineLimit(1)
                                    Text(RuleSummary.description(candidate.rule.match))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                // Losing candidates are the point: they show the ranking at work.
                                if !candidate.isWinner {
                                    Text("outranked").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Section("Result") {
                    if let destination = explanation.destination {
                        HStack(spacing: 8) {
                            DestinationIcon(bundleIdentifier: destination.bundleIdentifier, size: 16)
                            Text(destination.displayName)
                        }
                    } else {
                        Label("The picker would open.", systemImage: "hand.tap")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
