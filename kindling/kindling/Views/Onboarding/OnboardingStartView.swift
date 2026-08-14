//
//  OnboardingStartView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//

import SwiftUI

struct OnboardingStartView: View {
    @Binding var step: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    corkBoard(geo: geo)

                    VStack(spacing: 0) {
                        Spacer()

                        Text("finally, a way to moodboard your weekend.")
                            .font(.system(size: 36, weight: .medium))
                            .multilineTextAlignment(.center)
                            .tracking(-0.9)
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)

                        Text("tap anywhere to continue")
                            .font(.system(size: 16))
                            .foregroundColor(.black)
                            .tracking(-0.16)
                            .padding(.top, 16)

                        Spacer()

                        legalText
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.35)) { step = 2 } }
    }

    @ViewBuilder
    func corkBoard(geo: GeometryProxy) -> some View {
        let boardWidth = geo.size.width - 32
        let boardHeight = boardWidth * (481.0 / 370.0)

        ZStack {
            Image("cork")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: boardWidth, height: boardHeight)
                .clipped()

            // Logo
            VStack {
                Image("kindling black")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 32)
                    .padding(.top, 36)
                Spacer()
            }

            // Upper-left polaroid
            Image("polaroid-4")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(-13.99))
                .offset(x: -boardWidth * 0.262, y: -boardHeight * 0.185)

            // Upper-right polaroid
            Image("polaroid-1")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(9.57))
                .offset(x: boardWidth * 0.252, y: -boardHeight * 0.185)

            // Center polaroid
            Image("polaroid-3")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(7.86))
                .offset(x: boardWidth * 0.025, y: boardHeight * 0.079)

            // Lower-left polaroid
            Image("polaroid-2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(-13.95))
                .offset(x: -boardWidth * 0.242, y: boardHeight * 0.166)

            // Lower-center-right polaroid
            Image("polaroid-1")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.3)
                .rotationEffect(.degrees(2.95))
                .offset(x: boardWidth * 0.055, y: boardHeight * 0.198)

            // Sticky note
            Image("sticky note")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: boardWidth * 0.237)
                .rotationEffect(.degrees(-0.42))
                .offset(x: boardWidth * 0.306, y: boardHeight * 0.086)
            
            // Overlay
            Image("overlay")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: boardWidth, height: boardHeight)
                .blendMode(.softLight)
        }
        .frame(width: boardWidth, height: boardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 50))
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    var legalText: some View {
        Text("By continuing, you agree to kindling's \(Text("Terms & Conditions").underline()) and acknowledge the \(Text("Privacy Policy").underline()).")
            .font(.system(size: 12))
            .foregroundColor(Color(red: 142/255, green: 142/255, blue: 147/255))
            .multilineTextAlignment(.center)
            .tracking(-0.12)
    }
}

#Preview {
    OnboardingStartView(step: .constant(1))
}
