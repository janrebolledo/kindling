//
//  ContentView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import Foundation
internal import PostgREST
import Supabase
import SwiftUI

struct ContentView: View {
    @State private var cards: [Item] = []

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

            VStack {
                ForEach(cards) { card in
                    Card(card: card)
                        .padding(.horizontal)
                }
            }
            .task {
                do {
                    print("try to get cards pls")
                    cards = try await supabase.from("ideas").select().execute()
                        .value
                    print(cards)
                } catch {
                    //                dump(error)
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
}

#Preview {
    ContentView()
}
