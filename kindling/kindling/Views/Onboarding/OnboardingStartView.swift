//
//  OnboardingStartView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//

import SwiftUI

struct OnboardingStartView: View {
    var onContinue: () -> Void
    var onSignIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    corkBoard(geo: geo)

                    Text("reimagine your screenshot folder")
                        .font(.system(size: 36, weight: .medium))
                        .multilineTextAlignment(.center)
                        .tracking(-0.9)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    Spacer(minLength: 16)

                    VStack(spacing: 8) {
                        OnboardingPrimaryButton(title: "continue →") {
                            withAnimation(OnboardingMotion.step(reduceMotion)) {
                                onContinue()
                            }
                        }

                        Button {
                            withAnimation(OnboardingMotion.step(reduceMotion)) {
                                onSignIn()
                            }
                        } label: {
                            Text("or sign into your account")
                                .font(.system(size: 16, weight: .medium))
                                .tracking(-0.32)
                                .foregroundStyle(.black.opacity(0.5))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(OnboardingPressStyle())

                        OnboardingLegalText()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    func corkBoard(geo: GeometryProxy) -> some View {
        let boardWidth = min(geo.size.width - 64, 350)
        let boardHeight = boardWidth * (481.0 / 370.0)

        ZStack {
            Image("cork")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: boardWidth, height: boardHeight)
                .clipped()

            VStack {
                Image("kindling black")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 32)
                    .padding(.top, 36)
                Spacer()
            }

            Image("polaroid-4")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(-13.99))
                .offset(x: -boardWidth * 0.262, y: -boardHeight * 0.185)

            Image("polaroid-1")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(9.57))
                .offset(x: boardWidth * 0.252, y: -boardHeight * 0.185)

            Image("polaroid-3")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(7.86))
                .offset(x: boardWidth * 0.025, y: boardHeight * 0.079)

            Image("polaroid-2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(-13.95))
                .offset(x: -boardWidth * 0.242, y: boardHeight * 0.166)

            Image("polaroid-1")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(2.95))
                .offset(x: boardWidth * 0.055, y: boardHeight * 0.198)

            Image("sticky note")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.237)
                .rotationEffect(.degrees(-0.42))
                .offset(x: boardWidth * 0.306, y: boardHeight * 0.086)

            Image("overlay")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: boardWidth, height: boardHeight)
                .blendMode(.softLight)
        }
        .frame(width: boardWidth, height: boardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
        .padding(.horizontal, 32)
        .padding(.top, 16)
    }
}

#Preview {
    OnboardingStartView(onContinue: {}, onSignIn: {})
}
