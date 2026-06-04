//
//  AccountView.swift
//  roundup
//
//  Created by Jan Rebolledo on 6/3/26.
//

import Foundation
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
}

private struct TransportPreferencePayload: Encodable {
    let user_id: UUID
    let preferred_transport_type: String
}

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var transportType: TransportType = .driving
    @State private var isLoaded = false
    @State private var showDeleteConfirm = false

    private var email: String {
        supabase.auth.currentUser?.email ?? ""
    }

    private var name: String {
        let prefix = email.split(separator: "@").first.map(String.init) ?? "you"
        return prefix.prefix(1).uppercased() + prefix.dropFirst()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                homePill

                Text("account")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(.primary)
                    .padding(.top, 28)

                VStack(alignment: .leading, spacing: 28) {
                    infoRow(label: "name") {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(.primary)
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
                        title: "Delete account",
                        systemName: "trash",
                        tint: accountRed,
                        action: { showDeleteConfirm = true }
                    )
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
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
        .task { await loadPreference() }
        .onChange(of: transportType) { _, newValue in
            guard isLoaded else { return }
            Task { await savePreference(newValue) }
        }
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { try? await supabase.auth.signOut() }
            }
        } message: {
            Text("This permanently removes your account and saved data.")
        }
    }

    // MARK: - Components

    private var homePill: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("home")
                    .font(.system(size: 16))
                    .tracking(-0.4)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .tint(.primary)
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
    }

    private var transportPicker: some View {
        Menu {
            Picker("preferred transport type", selection: $transportType) {
                ForEach(TransportType.allCases) { type in
                    Label(type.label, systemImage: type.icon).tag(type)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: transportType.icon)
                    .font(.system(size: 14))
                Text(transportType.label)
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
                transportType = parsed
            }
        } catch {
            dump(error)
        }
        isLoaded = true
    }

    private func savePreference(_ type: TransportType) async {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let payload = TransportPreferencePayload(
            user_id: userID,
            preferred_transport_type: type.rawValue
        )
        do {
            try await supabase
                .from("user_data")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {
            dump(error)
        }
    }
}

#Preview {
    AccountView()
}
