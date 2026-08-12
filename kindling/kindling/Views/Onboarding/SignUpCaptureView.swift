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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeCardIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isDismissingCard = false
    @State private var promotionProgress: CGFloat = 0

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

                cardDeck
                .frame(height: 320)

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
                        allowsDeletion: false
                    )
                        .frame(width: 260, height: 293, alignment: .top)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
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
        if depth == 0 { return dragOffset.height * 0.12 }

        switch depth {
        case 1:
            return interpolate(5, 0, progress: effectivePromotionProgress)
        case 2:
            return interpolate(10, 5, progress: effectivePromotionProgress)
        default:
            return interpolate(15, 10, progress: effectivePromotionProgress)
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
            return reduceMotion ? 1 : 1 - swipeProgress * 0.12
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
        guard depth == 0, !reduceMotion else { return 0 }
        return swipeProgress * 8
    }

    private func opacity(for depth: Int) -> Double {
        if depth == 0 { return Double(1 - swipeProgress) }
        if depth == 3 { return Double(effectivePromotionProgress) }
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
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isDismissingCard else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isDismissingCard else { return }
                let projectedWidth = value.predictedEndTranslation.width
                guard abs(projectedWidth) > 90, cards.count > 1 else {
                    withAnimation(
                        reduceMotion
                            ? .linear(duration: 0.01)
                            : .spring(duration: 0.32, bounce: 0.22)
                    ) {
                        dragOffset = .zero
                        promotionProgress = 0
                    }
                    return
                }

                isDismissingCard = true
                let direction: CGFloat = projectedWidth < 0 ? -1 : 1
                let duration = reduceMotion ? 0.01 : 0.42
                withAnimation(
                    reduceMotion
                        ? .linear(duration: duration)
                        : .spring(duration: duration, bounce: 0.08)
                ) {
                    dragOffset = CGSize(width: direction * 520, height: value.translation.height)
                    promotionProgress = 1
                }

                Task {
                    try? await Task.sleep(
                        nanoseconds: UInt64(duration * 1_000_000_000)
                    )
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        activeCardIndex = (activeCardIndex + 1) % cards.count
                        dragOffset = .zero
                        promotionProgress = 0
                        isDismissingCard = false
                    }
                }
            }
    }
}
