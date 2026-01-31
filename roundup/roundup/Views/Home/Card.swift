//
//  Card.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/23/26.
//
import SwiftUI

struct Card: View {
    @State var image: UIImage? = nil

    var card: ItemWrapper
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if card.data.media_url != nil {
                    AsyncImage(url: URL(string: card.data.media_url!)) {
                        image in
                        image.image?.resizable()
                            .scaledToFill()
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .clipped()
                    }
                } else {
                    if image != nil {
                        Image(uiImage: image!)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .clipped()
                    }

                }

                LinearGradient(
                    gradient: Gradient(colors: [
                        .black.opacity(0.8),
                        .black.opacity(0),
                    ]),
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        Spacer()
                        Text("tap to view")
                            .font(.neueMontreal(.regular, size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Text(card.data.venue!)
                        .font(.editorialNew(.regular, size: 24))
                        .foregroundStyle(.white)

                    HStack {
                        if card.data.location_type != nil {
                            Text(card.data.location_type!)
                            Text("•")
                        }
                        if card.data.duration != nil {
                            Text(card.data.duration!)
                            Text("•")
                        }
                        if card.data.pricing != nil {
                            HStack(spacing: 0) {
                                ForEach(0..<card.data.pricing!, id: \.self) {
                                    _ in
                                    Text("$")
                                }
                                ForEach(
                                    0..<(3 - card.data.pricing!),
                                    id: \.self
                                ) {
                                    _ in
                                    Text("$")
                                }
                                .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .font(.neueMontreal(.regular, size: 16))
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onAppear {
            Task {
                image = try await loadImage(from: card.id)
            }
        }
    }
}

#Preview {
    ContentView()
}
