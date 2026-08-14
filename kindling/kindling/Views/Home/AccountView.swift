//
//  AccountView.swift
//  roundup
//
//  Created by Jan Rebolledo on 6/3/26.
//

import Foundation
import MapKit
import Photos
import PhotosUI
import Supabase
import SwiftUI
import UIKit

private let figmaGray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
private let accountRed = Color(red: 222 / 255, green: 51 / 255, blue: 43 / 255)

enum TransportType: String, CaseIterable, Identifiable {
    case driving
    case cycling
    case transit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driving: return "driving"
        case .cycling: return "cycling"
        case .transit: return "transit"
        }
    }

    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .cycling: return "bicycle"
        case .transit: return "tram.fill"
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .driving: return .automobile
        case .cycling: return .walking
        case .transit: return .transit
        }
    }
}

struct TransportPreferencePayload: Encodable {
    let user_id: UUID
    let preferred_transport_type: String
}

private struct UsernamePayload: Encodable {
    let user_id: UUID
    let username: String
}

struct AccountView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettings.self) private var userSettings

    @State private var isLoaded = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var isDeletingAccount = false
    @State private var showDiscardDialog = false

    @State private var processedScreenshotCount = 0
    @State private var totalScreenshotCount = 0
    @State private var isProcessingScreenshots = false

    @State private var displayName = ""
    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var isSavingName = false
    @FocusState private var nameFieldFocused: Bool

    @State private var username = ""
    @State private var isEditingUsername = false
    @State private var draftUsername = ""
    @State private var isSavingUsername = false
    @State private var usernameError: String?
    @FocusState private var usernameFieldFocused: Bool

    private var isEditing: Bool { isEditingName || isEditingUsername }

    private var hasUnsavedChanges: Bool {
        if isEditingName,
            draftName.trimmingCharacters(in: .whitespacesAndNewlines) != displayName
        {
            return true
        }
        if isEditingUsername,
            normalizedUsername(draftUsername) != username
        {
            return true
        }
        return false
    }

    private var email: String {
        supabase.auth.currentUser?.email ?? ""
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("account")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(.primary)
                    Spacer()
                    if isEditing {
                        saveButton
                    }
                }
                .padding(.top, 8)

                screenshotIndexingView
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 28) {
                    infoRow(label: "name") {
                        nameValue
                    }

                    VStack(alignment: .trailing, spacing: 6) {
                        infoRow(label: "username") {
                            usernameValue
                        }
                        if let usernameError {
                            Text(usernameError)
                                .font(.system(size: 13))
                                .tracking(-0.2)
                                .foregroundStyle(accountRed)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    infoRow(label: "email") {
                        Text(email)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(.primary)
                    }

                    infoRow(label: "preferred transport type") {
                        transportPicker
                    }

                    infoRow(label: "edit iPhone gallery access") {
                        Button(action: editGalleryAccess) {
                            HStack(spacing: 4) {
                                Text("Edit")
                                    .font(.system(size: 16, weight: .semibold))
                                    .tracking(-0.4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.top, 36)

                VStack(spacing: 12) {
                    pillButton(
                        title: "Give feedback",
                        systemName: "exclamationmark.bubble.fill",
                        tint: .primary,
                        action: giveFeedback
                    )

                    pillButton(
                        title: isDeletingAccount ? "Deleting…" : "Delete account",
                        systemName: "trash",
                        tint: accountRed,
                        action: { showDeleteConfirm = true }
                    )
                    .disabled(isDeletingAccount)
                }
                .padding(.top, 44)

                pillButton(title: "Sign out", systemName: nil, tint: accountRed) {
                    Task { try? await supabase.auth.signOut() }
                }
                .padding(.top, 24)

                Text("v1.00 • jan rebolledo")
                    .font(.system(size: 13))
                    .tracking(-0.2)
                    .foregroundStyle(figmaGray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 200)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
        // Tapping anywhere outside the text fields ends editing.
        .overlay {
            if isEditing {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { endEditing() }
            }
        }
        .background(
            InteractiveDismissGuard(blocking: hasUnsavedChanges) {
                showDiscardDialog = true
            }
        )
        .task {
            displayName = supabase.auth.currentUser?.displayName ?? ""
            async let preference: Void = loadPreference()
            async let screenshotProgress: Void = refreshScreenshotProgress()
            _ = await (preference, screenshotProgress)
        }
        .onChange(of: userSettings.transportType) { _, newValue in
            guard isLoaded else { return }
            Task { await userSettings.persistTransportType() }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused, isEditingName { Task { await saveName() } }
        }
        .onChange(of: usernameFieldFocused) { _, focused in
            if !focused, isEditingUsername { Task { await saveUsername() } }
        }
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently removes your account and saved data.")
        }
        .alert("Couldn't delete account", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your account is still active. Check your connection and try again.")
        }
        .alert("Discard changes?", isPresented: $showDiscardDialog) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { discardAndDismiss() }
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await commitEditing() }
        } label: {
            Text("Save")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.4)
        }
        .buttonStyle(.glass)
        .tint(.primary)
        .disabled(isSavingName || isSavingUsername)
    }

    private func endEditing() {
        nameFieldFocused = false
        usernameFieldFocused = false
    }

    private func commitEditing() async {
        if isEditingName { await saveName() }
        if isEditingUsername { await saveUsername() }
        endEditing()
    }

    private func discardAndDismiss() {
        draftName = displayName
        draftUsername = username
        usernameError = nil
        isEditingName = false
        isEditingUsername = false
        endEditing()
        dismiss()
    }

    // MARK: - Components

    private var screenshotIndexingView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("Screenshots Processed")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("\(processedScreenshotCount)/\(totalScreenshotCount)")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(figmaGray)
                        .contentTransition(.numericText())
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))

                        Capsule()
                            .fill(.primary)
                            .frame(width: proxy.size.width * screenshotProgress)
                    }
                }
                .frame(height: 6)
                .animation(.easeInOut(duration: 0.25), value: screenshotProgress)
            }
            .padding(14)

            HStack(spacing: 16) {
                screenshotActionButton(
                    title: isProcessingScreenshots ? "Processing" : "Process More",
                    systemName: isProcessingScreenshots ? "rays" : "plus",
                    isDisabled: isProcessingScreenshots,
                    action: processMoreScreenshots
                )

                screenshotActionButton(
                    title: "Upload Photos",
                    systemName: "photo",
                    action: editGalleryAccess
                )
            }

            Text("kindling cannot view your photos :)")
                .font(.system(size: 12))
                .tracking(-0.12)
                .foregroundStyle(figmaGray)
                .frame(maxWidth: .infinity)
        }
    }

    private var screenshotProgress: CGFloat {
        guard totalScreenshotCount > 0 else { return 0 }
        return min(CGFloat(processedScreenshotCount) / CGFloat(totalScreenshotCount), 1)
    }

    private func screenshotActionButton(
        title: String,
        systemName: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
            }
            .foregroundStyle(.primary)
            .opacity(isDisabled ? 0.5 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color("raisedSurface"), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var nameValue: some View {
        if isEditingName {
            TextField("name", text: $draftName)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFieldFocused)
                .onSubmit { Task { await saveName() } }
                .disabled(isSavingName)
        } else {
            Button {
                draftName = displayName
                isEditingName = true
                nameFieldFocused = true
            } label: {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(figmaGray)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var usernameValue: some View {
        if isEditingUsername {
            TextField("username", text: $draftUsername)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($usernameFieldFocused)
                .onSubmit { Task { await saveUsername() } }
                .disabled(isSavingUsername)
        } else {
            Button {
                draftUsername = username
                usernameError = nil
                isEditingUsername = true
                usernameFieldFocused = true
            } label: {
                HStack(spacing: 8) {
                    Text(username.isEmpty ? "set username" : "@\(username)")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(username.isEmpty ? figmaGray : .primary)
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(figmaGray)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func infoRow<Value: View>(
        label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 16))
                .tracking(-0.4)
                .foregroundStyle(figmaGray)
            Spacer(minLength: 12)
            value()
        }
        .frame(minHeight: 28)
    }

    private var transportPicker: some View {
        @Bindable var settings = userSettings
        return Menu {
            Picker("preferred transport type", selection: $settings.transportType) {
                ForEach(TransportType.allCases) { type in
                    Label(type.label, systemImage: type.icon).tag(type)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: userSettings.transportType.icon)
                    .font(.system(size: 14))
                Text(userSettings.transportType.label)
                    .font(.system(size: 16))
                    .tracking(-0.4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .tint(.primary)
    }

    private func pillButton(
        title: String,
        systemName: String?,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 16, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color("raisedSurface"), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func refreshScreenshotProgress() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            processedScreenshotCount = ParsedScreenshotsService().loadLocalParsedIDs().count
            totalScreenshotCount = 0
            return
        }

        let screenshots = ScreenshotManager().fetchScreenshots()
        let screenshotIDs = Set(screenshots.map(\.localIdentifier))
        let parsedIDs = ParsedScreenshotsService().loadLocalParsedIDs()

        totalScreenshotCount = screenshots.count
        processedScreenshotCount = parsedIDs.intersection(screenshotIDs).count
    }

    private func processMoreScreenshots() {
        guard !isProcessingScreenshots else { return }
        isProcessingScreenshots = true

        Task {
            await scanForNewScreenshots()
            await refreshScreenshotProgress()
            isProcessingScreenshots = false
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func editGalleryAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .limited:
            // App has limited access: let the user add more photos to the allowed set.
            if let controller = topViewController() {
                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
            }
        case .notDetermined:
            // No decision yet: request access so it can be elevated to full/limited.
            Task { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        default:
            // Authorized, denied, or restricted: send the user to Settings to change it.
            openSettings()
        }
    }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard
            let root = scene?.windows.first(where: { $0.isKeyWindow })?
                .rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private func deleteAccount() async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await AccountDeletion.deleteCurrentAccount()
        } catch {
            dump(error)
            showDeleteError = true
        }
    }

    private func giveFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "contact@janrebolledo.com"
        components.queryItems = [URLQueryItem(name: "subject", value: "Kindling Feedback")]
        if let url = components.url {
            openURL(url)
        }
    }

    // MARK: - Persistence

    private func loadPreference() async {
        guard let userID = supabase.auth.currentUser?.id else {
            isLoaded = true
            return
        }
        do {
            let rows: [UserData] =
                try await supabase
                .from("user_data")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value
            if let raw = rows.first?.preferred_transport_type,
                let parsed = TransportType(rawValue: raw)
            {
                userSettings.transportType = parsed
            }
            if let savedUsername = rows.first?.username,
                !savedUsername.isEmpty
            {
                username = savedUsername
            }
        } catch {
            dump(error)
        }
        isLoaded = true
    }

    /// Returns whether `candidate` is free, using a SECURITY DEFINER RPC so no
    /// other user's row data is exposed to the client.
    private func isUsernameAvailable(_ candidate: String) async throws -> Bool {
        try await supabase
            .rpc("is_username_available", params: ["candidate": candidate])
            .execute()
            .value
    }

    private func saveName() async {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEditingName = false
            return
        }
        guard trimmed != displayName else {
            isEditingName = false
            return
        }
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await supabase.auth.update(
                user: UserAttributes(
                    data: ["display_name": .string(trimmed)]
                )
            )
            displayName = trimmed
            isEditingName = false
        } catch {
            dump(error)
        }
    }

    private func normalizedUsername(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { value.removeFirst() }
        return value.lowercased()
    }

    private func saveUsername() async {
        guard let userID = supabase.auth.currentUser?.id else { return }

        let normalized = normalizedUsername(draftUsername)

        guard !normalized.isEmpty else {
            isEditingUsername = false
            usernameError = nil
            return
        }
        guard normalized != username else {
            isEditingUsername = false
            usernameError = nil
            return
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
        guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            usernameError = "Use only letters, numbers, periods, and underscores."
            return
        }
        guard normalized.count >= 3, normalized.count <= 20 else {
            usernameError = "Username must be 3–20 characters."
            return
        }

        isSavingUsername = true
        defer { isSavingUsername = false }
        usernameError = nil

        // Pre-check availability so we can show a friendly message before writing.
        do {
            if try await !isUsernameAvailable(normalized) {
                usernameError = "That username is already taken."
                return
            }
        } catch {
            usernameError = "Couldn't check username. Try again."
            dump(error)
            return
        }

        let payload = UsernamePayload(user_id: userID, username: normalized)
        do {
            try await supabase
                .from("user_data")
                .upsert(payload, onConflict: "user_id")
                .execute()
            username = normalized
            isEditingUsername = false
        } catch let error as PostgrestError where error.code == "23505" {
            // Unique constraint caught a race between the pre-check and the write.
            usernameError = "That username is already taken."
        } catch {
            usernameError = "Couldn't save username. Try again."
            dump(error)
        }
    }
}

/// Bridges SwiftUI sheets to UIKit so we can intercept an interactive (swipe)
/// dismissal and prompt the user before discarding unsaved edits.
private struct InteractiveDismissGuard: UIViewControllerRepresentable {
    var blocking: Bool
    var onAttemptToDismiss: () -> Void

    func makeUIViewController(context: Context) -> GuardController {
        let controller = GuardController()
        controller.onAttemptToDismiss = onAttemptToDismiss
        controller.blocking = blocking
        return controller
    }

    func updateUIViewController(_ uiViewController: GuardController, context: Context) {
        uiViewController.onAttemptToDismiss = onAttemptToDismiss
        uiViewController.blocking = blocking
        DispatchQueue.main.async { uiViewController.sync() }
    }

    final class GuardController: UIViewController, UIAdaptivePresentationControllerDelegate {
        var onAttemptToDismiss: (() -> Void)?
        var blocking = false

        /// SwiftUI installs its own delegate to keep the `isPresented` binding in
        /// sync. We capture it so we can forward the calls we don't handle.
        private weak var originalDelegate: UIAdaptivePresentationControllerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            sync()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            sync()
        }

        func sync() {
            guard let presented = presentedHost(),
                let presentationController = presented.presentationController
            else { return }

            if presentationController.delegate !== self {
                originalDelegate = presentationController.delegate
                presentationController.delegate = self
            }
            presented.isModalInPresentation = blocking
        }

        /// Walks up to the root of this controller's containment hierarchy. A
        /// presented sheet's host controller has no `parent`, so the topmost
        /// ancestor is the controller actually presented in the sheet.
        ///
        /// Note: `presentingViewController` cannot be used to find it because it
        /// auto-traverses and returns non-nil even for child controllers.
        private func presentedHost() -> UIViewController? {
            var controller: UIViewController = self
            while let parent = controller.parent {
                controller = parent
            }
            return controller.presentingViewController != nil ? controller : nil
        }

        // MARK: UIAdaptivePresentationControllerDelegate

        func presentationControllerDidAttemptToDismiss(
            _ presentationController: UIPresentationController
        ) {
            onAttemptToDismiss?()
        }

        func presentationControllerShouldDismiss(
            _ presentationController: UIPresentationController
        ) -> Bool {
            if blocking { return false }
            return originalDelegate?.presentationControllerShouldDismiss?(presentationController)
                ?? true
        }

        func presentationControllerWillDismiss(
            _ presentationController: UIPresentationController
        ) {
            originalDelegate?.presentationControllerWillDismiss?(presentationController)
        }

        func presentationControllerDidDismiss(
            _ presentationController: UIPresentationController
        ) {
            originalDelegate?.presentationControllerDidDismiss?(presentationController)
        }
    }
}

#Preview {
    AccountView()
}
