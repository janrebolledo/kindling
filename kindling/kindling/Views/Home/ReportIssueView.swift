import Photos
import SwiftUI
import Supabase
import Vision

private struct IssueReportSubmission: Encodable {
    let source: String
    let name: String
    let email: String?
    let message: String
    let user_id: UUID
}

private enum IssueReason: String, CaseIterable, Hashable {
    case inaccuratePlaceInformation
    case shouldNotHaveBeenProcessed

    var title: String {
        switch self {
        case .inaccuratePlaceInformation:
            return "inaccurate place information"
        case .shouldNotHaveBeenProcessed:
            return "should not have been processed"
        }
    }
}

struct ReportIssueView: View {
    let card: CardData

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedReasons: Set<IssueReason> = []
    @State private var includeScreenshotText = false
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @FocusState private var commentFocused: Bool

    private var trimmedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        (!selectedReasons.isEmpty || !trimmedComment.isEmpty) && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    submittedView
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    formView
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .navigationTitle("report an issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("what went wrong?")
                        .font(.system(size: 24, weight: .medium))
                        .tracking(-0.6)

                    Text("help us fix this idea for everyone.")
                        .font(.system(size: 16))
                        .tracking(-0.32)
                        .foregroundStyle(.secondary)

                    Text(card.ideas?.name ?? "untitled idea")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("select all that apply")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.secondary)

                    ForEach(IssueReason.allCases, id: \.self) { reason in
                        reasonButton(reason)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("include screenshot text", isOn: $includeScreenshotText)
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .tint(.primary)

                    Text("we’ll read the saved screenshot on your device and attach the text to this report.")
                        .font(.system(size: 13))
                        .tracking(-0.26)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Text("comment")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        if trimmedComment.isEmpty {
                            Text("tell us a little more (optional)")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $comment)
                            .focused($commentFocused)
                            .font(.system(size: 16))
                            .scrollContentBackground(.hidden)
                            .padding(12)
                    }
                    .frame(minHeight: 130)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.black.opacity(0.08), lineWidth: 1)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(isSubmitting ? "sending…" : "send report")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .disabled(!canSubmit)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func reasonButton(_ reason: IssueReason) -> some View {
        let isSelected = selectedReasons.contains(reason)

        return Button {
            if isSelected {
                selectedReasons.remove(reason)
            } else {
                selectedReasons.insert(reason)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(reason.title)
                    .font(.system(size: 16))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(
                isSelected ? Color.primary.opacity(0.08) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.black.opacity(isSelected ? 0.16 : 0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var submittedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("thanks for the report")
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.6)

            Text("we’ll look into it and use your feedback to make kindling better.")
                .font(.system(size: 16))
                .tracking(-0.32)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func submit() async {
        guard let user = supabase.auth.currentUser else {
            errorMessage = "please sign in again and try once more."
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let screenshotText = includeScreenshotText
            ? await extractScreenshotText()
            : nil
        let submission = IssueReportSubmission(
            source: "ios",
            name: user.displayName,
            email: user.email,
            message: makeMessage(screenshotText: screenshotText),
            user_id: user.id
        )

        do {
            try await supabase
                .from("contact_submissions")
                .insert(submission)
                .execute()

            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : AnimationConstants.springFast) {
                submitted = true
            }
        } catch {
            errorMessage = "couldn’t send that. check your connection and try again."
        }
    }

    private func makeMessage(screenshotText: String?) -> String {
        var sections = [
            "idea: \(card.ideas?.name ?? "untitled")",
            "idea id: \(card.ideas?.id ?? card.id)",
        ]

        if !selectedReasons.isEmpty {
            let reasons = IssueReason.allCases
                .filter { selectedReasons.contains($0) }
                .map(\.title)
                .joined(separator: ", ")
            sections.append("issue: \(reasons)")
        }

        if !trimmedComment.isEmpty {
            sections.append("comment:\n\(trimmedComment)")
        }

        if let screenshotText {
            sections.append("screenshot text:\n\(screenshotText)")
        }

        return String(sections.joined(separator: "\n\n").prefix(4000))
    }

    private func extractScreenshotText() async -> String {
        var results: [String] = []

        for (index, localID) in card.screenshotLocalIDs.enumerated() {
            guard let image = try? await loadImage(
                from: localID,
                targetSize: CGSize(width: 1800, height: 1800),
                resizeMode: .fast
            ) else { continue }

            let text = await recognizeText(
                in: image,
                recognitionLevel: .accurate,
                languages: ["en"],
                usesLanguageCorrection: true
            )
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { continue }
            results.append("screenshot \(index + 1):\n\(trimmedText)")
        }

        return results.isEmpty ? "no readable text found" : results.joined(separator: "\n\n")
    }
}

#Preview {
    Text("Report issue preview")
}
