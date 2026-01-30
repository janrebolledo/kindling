import AVKit
//
//  Card.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/23/26.
//
import SwiftUI

struct Card: View {
    @State private var player: AVPlayer?

    var card: Item
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let player {
                FullBleedVideo(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()  // crop anything that spills outside the parent
            }

            LinearGradient(
                gradient: Gradient(colors: [
                    .black.opacity(0.8),
                    .black.opacity(0),
                ]),
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {

                    Spacer()

                    Text("tap to view")
                        .font(.neueMontreal(.regular, size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text(card.venue!)
                    .font(.editorialNew(.regular, size: 24))
                    .foregroundStyle(.white)

                HStack {
                    // extra content
                    if card.location_type != nil {
                        Text(card.location_type!)
                        Text("•")
                    }
                    if card.duration != nil {

                        Text(card.duration!)
                        Text("•")
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<card.pricing!, id: \.self) { _ in
                            Text("$")
                        }
                        ForEach(0..<(3 - card.pricing!), id: \.self) { _ in
                            Text("$")
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .foregroundStyle(.white)
                .font(
                    .neueMontreal(.regular, size: 16)
                )
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
//        .task {
//            player = AVPlayer(url: URL(string: card.media_url!)!)
//            player?.isMuted = true
//            player?.play()
//        }

    }
}

#Preview {
    ContentView()
}
