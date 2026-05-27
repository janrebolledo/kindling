import Supabase
//
//  SignUpView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/30/26.
//
import SwiftUI

struct SignUpView: View {
    @Binding var cards: [ItemWrapper]
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State var result: Result<Void, Error>?

    var body: some View {
        VStack {
            ZStack(alignment: .center) {

                Image("background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, minHeight: 350)
                    .clipped()

                LinearGradient(
                    gradient: Gradient(colors: [
                        .white.opacity(0),
                        .white.opacity(1),
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity, maxHeight: 350)

                VStack(alignment: .center) {
                    Text("log in or sign up")

                    Text("keep your screenshots clutter free")
                        .foregroundStyle(.gray)
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: 350)

            VStack(spacing: 16) {
                Text("email")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                TextField(
                    "",
                    text: $email,
                    prompt: Text(verbatim: "name@email.com")
                )
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 24)
                .frame(maxWidth: 300, maxHeight: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.black.opacity(0.25), lineWidth: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .contentShape(RoundedRectangle(cornerRadius: 24))
                Text("password")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                TextField("••••", text: $password)
                    .textContentType(.password)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 300, maxHeight: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.black.opacity(0.25), lineWidth: 4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .contentShape(RoundedRectangle(cornerRadius: 24))
                
                Button(action: {
                    print("hi")
                    continueButtonTapped()
                }) {
                    Image(systemName: "apple.logo")
                        .resizable()
                        .frame(maxWidth: 24, maxHeight: 24)
                    Text("continue with Apple")
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 300, maxHeight: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.black.opacity(0.25), lineWidth: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .contentShape(RoundedRectangle(cornerRadius: 24))
            }
            .frame(maxWidth: 300)
            Spacer()

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
    func continueButtonTapped() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await supabase.auth.signUp(
                    email: "example@email.com",
                    password: "example-password"
                )
                result = .success(())

                await InitializeCollection(items: cards)
            } catch let authError as Auth.AuthError {
                if case .api(_, let errorCode, _, _) = authError {
                    if errorCode.rawValue == "user_already_exists" {
                        // try signin
                        print("user already exists, trying user sign in")
                        try await supabase.auth.signIn(
                            email: "example@email.com",
                            password: "example-password"
                        )
                        result = .success(())
                    }
                }
            } catch {
                result = .failure(error)

            }
        }
    }
}

//#Preview {
//    SignUpView()
//}
