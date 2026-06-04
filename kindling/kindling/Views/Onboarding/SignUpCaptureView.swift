import Supabase
//
//  SignUpCaptureView.swift
//  kindling
//
import SwiftUI

struct SignUpCaptureView: View {
    @Binding var cards: [ItemWrapper]
    @Binding var step: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            Image(colorScheme == .dark ? "gradient dark" : "gradient light")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .grayscale(0.45)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("here's what\nyou missed :(")
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-0.9)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    Text("as you screenshot, we'll capture it. swipe to see more")
                        .font(.system(size: 20, weight: .medium))
                        .tracking(-0.5)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                }
                .padding(.top, 24)

                ZStack {
                    if cards.count > 1 {
                        Card(function: nil, card: cards[1])
                            .frame(width: 260)
                            .rotationEffect(.degrees(6.12))
                            .offset(x: 30)
                    }
                    if cards.count > 0 {
                        Card(function: nil, card: cards[0])
                            .frame(width: 260)
                            .rotationEffect(.degrees(-6.13))
                            .offset(x: -30)
                    }
                    if cards.count > 2 {
                        Card(function: nil, card: cards[2])
                            .frame(width: 260)
                            .rotationEffect(.degrees(-1))
                    }
                }
                .frame(height: 320)
                .clipped()

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { step = 5 }
                    } label: {
                        Text("wait kindling help me →")
                            .font(.system(size: 20, weight: .medium))
                            .tracking(-0.5)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }

                    Text("kindling cannot view your photos, everything is stored on device :)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 142/255, green: 142/255, blue: 147/255))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 48)
        }
    }
}
