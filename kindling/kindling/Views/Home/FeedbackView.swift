import SwiftUI
import Supabase

private struct FeedbackSubmission: Encodable {
    let source: String
    let name: String
    let email: String?
    let message: String
    let user_id: UUID
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @FocusState private var messageFocused: Bool

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    submittedView
                } else {
                    formView
                }
            }
            .navigationTitle("feedback")
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
                Text("what's on your mind?")
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.6)

                Text("tell us what’s working, what isn’t, or what you’d love to see next.")
                    .font(.system(size: 16))
                    .tracking(-0.32)
                    .foregroundStyle(.secondary)

                TextEditor(text: $message)
                    .focused($messageFocused)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 170)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.black.opacity(0.08), lineWidth: 1)
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(isSubmitting ? "sending…" : "send feedback")
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                messageFocused = true
            }
        }
    }

    private var submittedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("thanks for the feedback")
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.6)

            Text("we’ll read it and use it to make kindling better.")
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

        let submission = FeedbackSubmission(
            source: "ios",
            name: user.displayName,
            email: user.email,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            user_id: user.id
        )

        do {
            try await supabase
                .from("contact_submissions")
                .insert(submission)
                .execute()
            submitted = true
        } catch {
            errorMessage = "couldn’t send that. check your connection and try again."
        }
    }
}

#Preview {
    FeedbackView()
}
