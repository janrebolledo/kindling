import SwiftUI

/// A continuously moving, seamless strip of real Kindling cards.
struct OnboardingCardCarousel: View {
    let cards: [ItemWrapper]
    var speed: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 271
    private let spacing: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            carouselContent
                .frame(
                    width: geometry.size.width,
                    height: cardHeight,
                    alignment: .leading
                )
                .clipped()
        }
        .frame(height: cardHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kindling card carousel")
    }

    @ViewBuilder
    private var carouselContent: some View {
        if cards.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if reduceMotion {
            ScrollView(.horizontal, showsIndicators: false) {
                cardStrip
                    .padding(.horizontal, 51)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                let cycleWidth = CGFloat(cards.count) * (cardWidth + spacing)
                let distance = CGFloat(
                    context.date.timeIntervalSinceReferenceDate
                ) * speed

                cardStrip
                    .offset(
                        x: -distance.truncatingRemainder(
                            dividingBy: cycleWidth
                        )
                    )
            }
        }
    }

    private var repeatedCards: [ItemWrapper] {
        Array(repeating: cards, count: 3).flatMap { $0 }
    }

    private var cardStrip: some View {
        HStack(spacing: spacing) {
            ForEach(Array(repeatedCards.enumerated()), id: \.offset) { _, card in
                Card(
                    card: card,
                    loadsMapData: false,
                    allowsDetailPresentation: false
                )
                .frame(width: cardWidth, height: cardHeight, alignment: .top)
            }
        }
    }
}
