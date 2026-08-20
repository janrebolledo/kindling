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

private enum SettingsPage: Hashable {
    case settings
    case displayName
    case username
    case transportType

    var title: String {
        switch self {
        case .settings: return "settings"
        case .displayName: return "display name"
        case .username: return "username"
        case .transportType: return "transport type"
        }
    }
}

struct AccountView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(UserSettings.self) private var userSettings
    @Environment(ScreenshotIndexingController.self) private var screenshotIndexing

    @State private var isLoaded = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var isDeletingAccount = false
    @State private var showDiscardDialog = false
    @State private var showSignOutConfirm = false
    @State private var showFeedback = false

    @State private var isPhotoPickerPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showUploadError = false
    @State private var uploadErrorMessage = ""

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
            draftName.trimmingCharacters(in: .whitespacesAndNewlines) != userSettings.displayName
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

    private var lowercaseUsernameBinding: Binding<String> {
        Binding(
            get: { draftUsername },
            set: { draftUsername = $0.lowercased() }
        )
    }

    var body: some View {
        ScrollView {
            settingsPage
                .padding(.top, 16)
                .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
        .navigationTitle(SettingsPage.settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if hasUnsavedChanges {
                        showDiscardDialog = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close settings")
            }
        }
        .background(
            InteractiveDismissGuard(blocking: hasUnsavedChanges) {
                showDiscardDialog = true
            }
        )
        .task {
            await loadPreference()
            await screenshotIndexing.refreshProgress()
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
        .onChange(of: selectedPhotoItems) { _, newItems in
            processSelectedPhotos(newItems)
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
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                Task { try? await supabase.auth.signOut() }
            }
        } message: {
            Text("You can sign back in anytime.")
        }
        .alert("Couldn't upload photos", isPresented: $showUploadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploadErrorMessage)
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
    }

    private func detailPage(for destination: SettingsPage) -> some View {
        ScrollView {
            Group {
                switch destination {
                case .settings:
                    settingsPage
                case .displayName:
                    displayNamePage
                case .username:
                    usernamePage
                case .transportType:
                    transportTypePage
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .onAppear { beginEditing(destination) }
        .onDisappear { endEditing() }
    }

    private func beginEditing(_ destination: SettingsPage) {
        switch destination {
        case .displayName:
            draftName = userSettings.displayName
            isEditingName = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                nameFieldFocused = true
            }
        case .username:
            draftUsername = username
            usernameError = nil
            isEditingUsername = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                usernameFieldFocused = true
            }
        case .settings, .transportType:
            break
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
        draftName = userSettings.displayName
        draftUsername = username
        usernameError = nil
        isEditingName = false
        isEditingUsername = false
        endEditing()
        dismiss()
    }

    // MARK: - Components

    private var settingsPage: some View {
        VStack(spacing: 64) {
            screenshotIndexingView

            settingsSection(title: "account") {
                VStack(spacing: 24) {
                    settingsCard {
                        displayNameRow
                        usernameRow
                        emailRow
                    }

                    settingsActionButton(
                        title: isDeletingAccount ? "Deleting…" : "Delete account",
                        systemName: "trash",
                        tint: accountRed,
                        action: { showDeleteConfirm = true }
                    )
                    .disabled(isDeletingAccount)
                }
            }

            settingsSection(title: "preferences") {
                settingsCard {
                    transportTypeRow
                    inferenceProviderRow
                    galleryAccessRow
                }
            }

            settingsSection(title: "legal") {
                settingsCard {
                    settingsRow(
                        label: "terms & conditions",
                        value: nil,
                        tint: .primary,
                        chevronTint: .primary
                    ) {
                        openPolicy(path: "terms")
                    }
                    settingsRow(
                        label: "privacy policy",
                        value: nil,
                        tint: .primary,
                        chevronTint: .primary
                    ) {
                        openPolicy(path: "privacy")
                    }
                }
            }

            VStack(spacing: 24) {
                settingsActionButton(
                    title: "Give feedback",
                    systemName: "exclamationmark.bubble.fill",
                    tint: .primary,
                    action: { showFeedback = true }
                )

                settingsActionButton(
                    title: "Sign out",
                    systemName: nil,
                    tint: accountRed,
                    action: { showSignOutConfirm = true }
                )
            }

            Text("v1.00 early preview • jan rebolledo")
                .font(.system(size: 16))
                .tracking(-0.16)
                .foregroundStyle(figmaGray)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private var displayNamePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("display name")
                    .font(.system(size: 10))
                    .tracking(-0.125)
                    .foregroundStyle(figmaGray)

                TextField("display name", text: $draftName)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFieldFocused)
                    .onSubmit { Task { await saveName() } }
                    .disabled(isSavingName)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("raisedSurface"), in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usernamePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("username")
                    .font(.system(size: 10))
                    .tracking(-0.125)
                    .foregroundStyle(figmaGray)

                TextField("username", text: lowercaseUsernameBinding)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(nil)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($usernameFieldFocused)
                    .onSubmit { Task { await saveUsername() } }
                    .onChange(of: draftUsername) { _, newValue in
                        let lowered = newValue.lowercased()
                        if newValue != lowered { draftUsername = lowered }
                    }
                    .disabled(isSavingUsername)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("raisedSurface"), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                if usernameError != nil {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(accountRed, lineWidth: 2)
                }
            }

            Text(usernameError ?? "your username is unique and helps other add you")
                .font(.system(size: 16))
                .tracking(-0.4)
                .foregroundStyle(usernameError == nil ? figmaGray : accountRed)
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transportTypePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(TransportType.allCases.enumerated()), id: \.element.id) { index, type in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                    }

                    Button {
                        userSettings.transportType = type
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: type.icon)
                                .font(.system(size: 16))
                                .frame(width: 16)
                            Text(type.label)
                                .font(.system(size: 16, weight: .medium))
                                .tracking(-0.4)
                            Spacer()
                            if userSettings.transportType == type {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(Color("raisedSurface"), in: RoundedRectangle(cornerRadius: 24))

            Text("this is used to show destination ETA")
                .font(.system(size: 16))
                .tracking(-0.4)
                .foregroundStyle(figmaGray)
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .tracking(-0.45)
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 20) {
            content()
        }
        .padding(6)
        .background(Color("raisedSurface"), in: RoundedRectangle(cornerRadius: 24))
    }

    private func settingsRow(
        label: String,
        value: String?,
        tint: Color = .primary,
        chevronTint: Color = figmaGray,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(tint)

                Spacer(minLength: 8)

                if let value {
                    Text(value)
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(figmaGray)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chevronTint)
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayNameRow: some View {
        settingsNavigationRow(
            label: "display name",
            value: userSettings.displayName,
            destination: .displayName
        )
    }

    private var usernameRow: some View {
        settingsNavigationRow(
            label: "username",
            value: username.isEmpty ? "set username" : username,
            destination: .username
        )
    }

    private var emailRow: some View {
        HStack(spacing: 10) {
            Text("email")
                .font(.system(size: 16, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(email)
                .font(.system(size: 16, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(figmaGray)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
    }

    private var transportTypeRow: some View {
        NavigationLink {
            AnyView(detailPage(for: .transportType))
        } label: {
            HStack(spacing: 10) {
                Text("transport type")
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: userSettings.transportType.icon)
                        .font(.system(size: 14))
                    Text(userSettings.transportType.label)
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                }
                .foregroundStyle(figmaGray)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(figmaGray)
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsNavigationRow(
        label: String,
        value: String?,
        tint: Color = .primary,
        destination: SettingsPage
    ) -> some View {
        NavigationLink {
            AnyView(detailPage(for: destination))
        } label: {
            settingsRowLabel(label: label, value: value, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func settingsRowLabel(
        label: String,
        value: String?,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(tint)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(figmaGray)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(figmaGray)
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .contentShape(Rectangle())
    }

    private var galleryAccessRow: some View {
        settingsRow(label: "edit iPhone gallery access", value: "Edit", tint: .primary) {
            editGalleryAccess()
        }
    }

    private var inferenceProviderRow: some View {
        @Bindable var settings = userSettings
        return Menu {
            Picker("screenshot inference", selection: $settings.inferenceProvider) {
                Label("kindling cloud", systemImage: "cloud.fill")
                    .tag(InferenceProvider.cloud)
                Label("on this iPhone", systemImage: "iphone.gen3")
                    .tag(InferenceProvider.appleFoundationModels)
                    .disabled(!LocalScreenshotInference.isAvailable)
            }
            if !LocalScreenshotInference.isAvailable {
                Text("Apple Intelligence is unavailable")
            }
        } label: {
            HStack(spacing: 10) {
                Text("screenshot inference")
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(userSettings.inferenceProvider.label)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(figmaGray)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(figmaGray)
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose cloud processing or private on-device Apple Intelligence")
    }

    private func settingsActionButton(
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
            .frame(height: 48)
            .background(Color("raisedSurface"), in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    private var screenshotIndexingView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("screenshots processed")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 0) {
                        Text("\(screenshotIndexing.processedScreenshotCount)")
                            .contentTransition(.numericText())
                            .opacity(screenshotIndexing.isProcessing && !reduceMotion ? 0.5 : 1)
                            .animation(
                                screenshotIndexing.isProcessing && !reduceMotion
                                    ? .easeInOut(duration: 0.9).repeatForever(
                                        autoreverses: true
                                    )
                                    : .easeOut(duration: 0.15),
                                value: screenshotIndexing.isProcessing
                            )

                        Text("/\(screenshotIndexing.totalScreenshotCount)")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(figmaGray)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))

                        if screenshotIndexing.isProcessing {
                            Capsule()
                                .fill(Color(red: 247 / 255, green: 190 / 255, blue: 125 / 255))
                                .frame(width: proxy.size.width * processingScreenshotProgress)
                        }

                        Capsule()
                            .fill(Color(red: 255 / 255, green: 137 / 255, blue: 4 / 255))
                            .frame(width: proxy.size.width * displayedScreenshotProgress)
                    }
                }
                .frame(height: 6)
                .animation(.easeInOut(duration: 0.25), value: displayedScreenshotProgress)
                .animation(.easeInOut(duration: 0.25), value: processingScreenshotProgress)
            }
            .padding(14)

            HStack(spacing: 16) {
                screenshotActionButton(
                    title: screenshotIndexing.isProcessing ? "processing" : "process more",
                    systemName: screenshotIndexing.isProcessing ? "rays" : "plus",
                    isDisabled: screenshotIndexing.isBusy,
                    isSpinning: screenshotIndexing.isProcessing,
                    action: processMoreScreenshots
                )

                Button {
                    isPhotoPickerPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .medium))
                        Text("upload photos")
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.4)
                    }
                    .foregroundStyle(.primary)
                    .opacity(screenshotIndexing.isBusy ? 0.5 : 1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color("raisedSurface"), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(screenshotIndexing.isBusy)
                .photosPicker(
                    isPresented: $isPhotoPickerPresented,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 5,
                    matching: .images
                )
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text("kindling does not store your photos")
            }
                .font(.system(size: 12))
                .tracking(-0.12)
                .foregroundStyle(figmaGray)
                .frame(maxWidth: .infinity)
        }
    }

    private var screenshotProgress: CGFloat {
        guard screenshotIndexing.totalScreenshotCount > 0 else { return 0 }
        return min(
            CGFloat(screenshotIndexing.processedScreenshotCount)
                / CGFloat(screenshotIndexing.totalScreenshotCount),
            1
        )
    }

    private var displayedScreenshotProgress: CGFloat {
        guard screenshotIndexing.totalScreenshotCount > 0 else { return screenshotProgress }
        guard screenshotIndexing.isProcessing else { return screenshotProgress }

        return min(
            CGFloat(
                screenshotIndexing.processedScreenshotCount
                    + screenshotIndexing.processedProcessingImageCount
            ) / CGFloat(screenshotIndexing.totalScreenshotCount),
            1
        )
    }

    private var processingScreenshotProgress: CGFloat {
        let remainingImages = max(
            screenshotIndexing.processingImageCount
                - screenshotIndexing.processedProcessingImageCount,
            0
        )
        guard remainingImages > 0 else { return displayedScreenshotProgress }

        let indicatorWidth: CGFloat
        if screenshotIndexing.totalScreenshotCount > 0 {
            indicatorWidth = min(
                CGFloat(remainingImages) / CGFloat(screenshotIndexing.totalScreenshotCount),
                0.08
            )
        } else {
            indicatorWidth = 0.05
        }

        return min(displayedScreenshotProgress + indicatorWidth, 1)
    }

    private func screenshotActionButton(
        title: String,
        systemName: String,
        isDisabled: Bool = false,
        isSpinning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    if isSpinning {
                        SpinningRaysIcon(reduceMotion: reduceMotion)
                    } else {
                        Image(systemName: systemName)
                    }
                }
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
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFieldFocused)
                .onSubmit { Task { await saveName() } }
                .disabled(isSavingName)
        } else {
            Button {
                draftName = userSettings.displayName
                isEditingName = true
                nameFieldFocused = true
            } label: {
                HStack(spacing: 8) {
                    Text(userSettings.displayName)
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
            TextField("username", text: lowercaseUsernameBinding)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(nil)
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($usernameFieldFocused)
                .onSubmit { Task { await saveUsername() } }
                .onChange(of: draftUsername) { _, newValue in
                    let lowered = newValue.lowercased()
                    if newValue != lowered { draftUsername = lowered }
                }
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

    private func processMoreScreenshots() {
        guard !screenshotIndexing.isBusy else { return }
        Task { await screenshotIndexing.scan(limit: 5) }
    }

    private func processSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, !screenshotIndexing.isBusy else { return }

        Task {
            do {
                try await screenshotIndexing.processSelectedPhotos(items)
                selectedPhotoItems = []
            } catch {
                selectedPhotoItems = []
                uploadErrorMessage = error.localizedDescription
                showUploadError = true
            }
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

    private func openPolicy(path: String) {
        guard let url = URL(string: "https://getkindl.ing/\(path)") else { return }
        openURL(url)
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
                username = savedUsername.lowercased()
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
        let trimmed = draftName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else {
            isEditingName = false
            return
        }
        guard trimmed != userSettings.displayName else {
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
            userSettings.displayName = trimmed
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

private struct SpinningRaysIcon: View {
    let reduceMotion: Bool
    @State private var spinAngle: Double = 0

    var body: some View {
        Image(systemName: "rays")
            .rotationEffect(.degrees(reduceMotion ? 0 : spinAngle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
    }
}

#Preview {
    AccountView()
}
