import SwiftUI

struct SignUpCaptureView: View {
    @Binding var cards: [ItemWrapper]
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeCardIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isCyclingCard = false
    @State private var promotionProgress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            OnboardingWarmGradient(height: 400, grayscale: true)

            VStack(spacing: 24) {
                VStack(spacing: 26) {
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

                cardDeck
                .frame(height: 320)

                Spacer()

                VStack(spacing: 12) {
                    OnboardingPrimaryButton(title: "continue to sign up →") {
                        withAnimation(OnboardingMotion.step(reduceMotion)) {
                            onContinue()
                        }
                    }

                    OnboardingPrivacyNote()
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 48)
        }
        .onChange(of: cards.count) { _, count in
            if count == 0 {
                activeCardIndex = 0
            } else {
                activeCardIndex %= count
            }
        }
    }

    @ViewBuilder
    private var cardDeck: some View {
        if cards.isEmpty {
            ProgressView()
        } else {
            ZStack {
                ForEach(visibleCardIndices, id: \.self) { index in
                    let depth = deckDepth(for: index)
                    Card(
                        function: nil,
                        card: cards[index],
                        allowsDeletion: false,
                        animatesImageLoading: true
                    )
                        .frame(width: 250, alignment: .top)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .scaleEffect(scale(for: depth))
                        .blur(radius: blur(for: depth))
                        .opacity(opacity(for: depth))
                        .rotationEffect(
                            .degrees(rotation(for: depth))
                        )
                        .offset(
                            x: horizontalOffset(for: depth),
                            y: verticalOffset(for: depth)
                        )
                        .zIndex(Double(4 - depth))
                        .allowsHitTesting(depth == 0)
                        .simultaneousGesture(swipeGesture)
                }
            }
            .accessibilityHint("Swipe a card aside to see the next result")
        }
    }

    private var visibleCardIndices: [Int] {
        guard !cards.isEmpty else { return [] }
        return (0..<min(4, cards.count)).map {
            (activeCardIndex + $0) % cards.count
        }
    }

    private func deckDepth(for index: Int) -> Int {
        (index - activeCardIndex + cards.count) % cards.count
    }

    private func rotation(for depth: Int) -> Double {
        if depth == 0 {
            return -1 + Double(dragOffset.width / 18)
        }

        switch depth {
        case 1:
            return interpolate(-6.13, -1, progress: effectivePromotionProgress)
        case 2:
            return interpolate(6.12, -6.13, progress: effectivePromotionProgress)
        default:
            return interpolate(3, 6.12, progress: effectivePromotionProgress)
        }
    }

    private func horizontalOffset(for depth: Int) -> CGFloat {
        if depth == 0 { return dragOffset.width }

        switch depth {
        case 1:
            return interpolate(-30, 0, progress: effectivePromotionProgress)
        case 2:
            return interpolate(30, -30, progress: effectivePromotionProgress)
        default:
            return interpolate(42, 30, progress: effectivePromotionProgress)
        }
    }

    private func verticalOffset(for depth: Int) -> CGFloat {
        if depth == 0 {
            return dragOffset.height
        }

        switch depth {
        case 1:
            return interpolate(18, 12, progress: effectivePromotionProgress)
        case 2:
            return interpolate(24, 18, progress: effectivePromotionProgress)
        default:
            return interpolate(30, 24, progress: effectivePromotionProgress)
        }
    }

    private var swipeProgress: CGFloat {
        min(abs(dragOffset.width) / 360, 1)
    }

    private var effectivePromotionProgress: CGFloat {
        max(promotionProgress, min(swipeProgress * 0.35, 0.35))
    }

    private func scale(for depth: Int) -> CGFloat {
        if depth == 0 {
            guard !reduceMotion else { return 1 }
            return 1 - swipeProgress * 0.04
        }

        switch depth {
        case 1:
            return interpolate(0.975, 1, progress: effectivePromotionProgress)
        case 2:
            return interpolate(0.95, 0.975, progress: effectivePromotionProgress)
        default:
            return interpolate(0.92, 0.95, progress: effectivePromotionProgress)
        }
    }

    private func blur(for depth: Int) -> CGFloat {
        guard !reduceMotion else { return 0 }
        if depth == 0 { return swipeProgress * 3 }
        return 0
    }

    private func opacity(for depth: Int) -> Double {
        if depth == 0 {
            return 1 - Double(swipeProgress) * 0.3
        }
        return 1
    }

    private func interpolate(
        _ start: CGFloat,
        _ end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }

    private func interpolate(
        _ start: Double,
        _ end: Double,
        progress: CGFloat
    ) -> Double {
        start + (end - start) * Double(progress)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isCyclingCard else { return }
                dragOffset = CGSize(
                    width: value.translation.width,
                    height: min(max(value.translation.height, -35), 35)
                )
            }
            .onEnded { value in
                guard !isCyclingCard else { return }
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard isHorizontal else {
                    withAnimation(cardResetAnimation) {
                        dragOffset = .zero
                    }
                    return
                }

                let projectedWidth = value.predictedEndTranslation.width
                guard cards.count > 1,
                      abs(value.translation.width) > 45 || abs(projectedWidth) > 90
                else {
                    withAnimation(cardResetAnimation) {
                        dragOffset = .zero
                    }
                    return
                }

                cycleCard(direction: value.translation.width < 0 ? 1 : -1)
            }
    }

    private var cardResetAnimation: Animation {
        CardSwipeMotion.transition(reduceMotion)
    }

    private func cycleCard(direction: Int) {
        guard cards.count > 1, !isCyclingCard else { return }

        isCyclingCard = true
        let outgoingOffset = direction > 0
            ? -CardSwipeMotion.outgoingOffset
            : CardSwipeMotion.outgoingOffset
        let incomingOffset = -outgoingOffset
        let animation = CardSwipeMotion.transition(reduceMotion)

        withAnimation(animation) {
            dragOffset = CGSize(width: outgoingOffset, height: 0)
        }

        withAnimation(animation) {
            promotionProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: CardSwipeMotion.handoffNanoseconds)
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                activeCardIndex = (activeCardIndex + direction + cards.count) % cards.count
                dragOffset = CGSize(width: incomingOffset, height: 0)
                promotionProgress = 0
            }

            withAnimation(animation) {
                dragOffset = .zero
                isCyclingCard = false
            }
        }
    }
}
