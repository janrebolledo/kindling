import AVFoundation
import AVKit
//
//  OnboardingAnimationView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/12/26.
//
import SwiftUI

struct OnboardingAnimationView: View {
    @Binding var player: AVPlayer
    @State var textVisible: Bool = false

    var body: some View {

        ZStack {
            FullBleedVideo(player: player)
            VStack {

                Spacer()
                VStack {
                    Text("nice to meet u").font(
                        .editorialNew(.regular, size: 36)
                    )
                    .opacity(textVisible ? 1 : 0)
                    HStack {
                        ProgressView()
                        Text("processing your screenshots").font(
                            .neueMontreal(.regular, size: 18)
                        )
                        .foregroundStyle(.secondary)
                    }
                    .opacity(textVisible ? 1 : 0)
                }
                Spacer()
                Spacer()
            }

        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                player.play()
                try await Task.sleep(for: .seconds(0.2))

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        textVisible = true
                    }
                }
            }
        }
    }
}

#Preview {
    @State var player: AVPlayer = AVPlayer(
        url: Bundle.main.url(forResource: "onboarding", withExtension: ".mp4")!
    )
    OnboardingAnimationView(player: $player, )
}
