internal import PostgREST
import Supabase
//
//  SignUpCaptureView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//
import SwiftUI

struct SignUpCaptureView: View {
    @Binding var cards: [ItemWrapper]
    @Binding var step: Int
    @Binding var screenshotCount: Int

    var body: some View {

        ScrollView {
            ZStack(alignment: .leading) {

                //                Image("background")
                //                    .resizable()
                //                    .aspectRatio(contentMode: .fill)
                //                    .frame(maxWidth: .infinity, minHeight: 350)
                //                    .clipped()
                //
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

                    Text("\(screenshotCount) screenshots saved")
                        .foregroundStyle(.gray)
                        .font(
                            Font.custom("PPNeueMontreal-Medium", size: 16)
                        )
                }
                .padding(.horizontal, 32)
            }
            .frame(height: 350)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(cards) { card in
                    Card(function: deleteCard, card: card)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 200)
        }
        .edgesIgnoringSafeArea(.top)
        .overlay(
            VStack {
                Spacer()
                ZStack(alignment: .bottom) {
                    VariableBlurView(
                        maxBlurRadius: 20,
                        direction: .blurredBottomClearTop
                    )
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
                        step = 4
                    }
                    .padding(.bottom, 64)
                }
            }.ignoresSafeArea()
        )

    }
    func deleteCard(item: ItemWrapper?) async {

        cards = cards.filter { el in
            return el.id != item?.id
        }
    }
}

//#Preview {
//    SignUpCaptureView()
//}
