//
//  SignUpCaptureView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//
import SwiftUI
internal import PostgREST
import Supabase

struct SignUpCaptureView: View {
    @Binding var cards: [ItemWrapper]
    @State private var screenshotManager = ScreenshotManager()
    
    var body: some View {

        ScrollView {
            ZStack(alignment: .leading) {

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

                VStack(alignment: .leading) {
                    Text("captured").font(
                        Font.custom("PPEditorialNew-Italic", size: 24)
                    )

                    Text("32 screenshots saved")
                        .foregroundStyle(.gray)
                        .font(
                            Font.custom("PPNeueMontreal-Medium", size: 16)
                        )
                }
                .padding(.horizontal, 32)
            }
            .frame(height: 350)

            VStack(spacing: 24) {
                ForEach(cards) { card in
                    Card(card: card)
                        .padding(.horizontal)
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
        .overlay(
            VStack {
                Spacer()
                ZStack(alignment: .bottom) {
                    VariableBlurView(maxBlurRadius: 20, direction: .blurredBottomClearTop)
                            .frame(height: 200)
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0),
                            .white.opacity(1),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    
                    StyledButton(
                        title: "sign up to view all activities",
                        systemName: "heart.fill"
                    ) {
                        print("fireeee")
                    }
                    .padding(.bottom, 64)
                }
            }.ignoresSafeArea()
        )

    }
}

//#Preview {
//    SignUpCaptureView()
//}
