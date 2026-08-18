//
//  OnboardingScreenshotSummaryView.swift
//  kindling
//

import SwiftUI

struct OnboardingScreenshotSummaryView: View {
    var onContinue: () -> Void
    let screenshotImages: [UIImage]
    let totalCount: Int
    let totalSizeGB: Double
    @Binding var isProcessing: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinAngle: Double = 0

    private var sizeText: String {
        if totalSizeGB < 1 {
            return "\(String(format: "%.0f", totalSizeGB * 1024)) mbs"
        }
        return "\(String(format: "%.1f", totalSizeGB)) gbs"
    }
    
    private struct PolaroidItem {
        let rotation: Double
        let offsetX: CGFloat
        let offsetY: CGFloat
    }
    
    private let polaroidLayouts: [PolaroidItem] = [
        PolaroidItem(rotation:  9.57, offsetX:  118, offsetY: -138),
        PolaroidItem(rotation:  8.33, offsetX:  -13, offsetY: -196),
        PolaroidItem(rotation: -3.85, offsetX:   35, offsetY:  -85),
        PolaroidItem(rotation:-13.99, offsetX: -115, offsetY: -134),
        PolaroidItem(rotation:  7.86, offsetX:  -48, offsetY:  -64),
    ]
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            OnboardingWarmGradient(height: 400)

            VStack(spacing: 24) {
                GeometryReader { geo in
                    let scale = geo.size.width / 402
                    ZStack {
                        ForEach(0..<min(screenshotImages.count, polaroidLayouts.count), id: \.self) { i in
                            let layout = polaroidLayouts[i]
                            UserPhotoPolaroid(image: screenshotImages[i])
                                .rotationEffect(.degrees(layout.rotation))
                                .offset(
                                    x: layout.offsetX * scale,
                                    y: layout.offsetY * scale
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, 200)

                VStack(spacing: 8) {
                    Text("we looked at your \(totalCount) recent screenshots")
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-0.9)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text("you have \(totalCount) screenshots taking up ~\(sizeText) 🫥")
                        .font(.system(size: 20, weight: .medium))
                        .tracking(-0.5)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    if isProcessing {
                        HStack(spacing: 10) {
                            Image(systemName: "rays")
                                .rotationEffect(.degrees(reduceMotion ? 0 : spinAngle))
                            Text("pondering")
                        }
                        .font(.system(size: 20, weight: .medium))
                        .tracking(-0.5)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.gray, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        OnboardingPrimaryButton(title: "see what we found →") {
                            withAnimation(OnboardingMotion.step(reduceMotion)) {
                                onContinue()
                            }
                        }
                    }

                    OnboardingPrivacyNote()
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 48)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
        }
    }
    
    private struct UserPhotoPolaroid: View {
        let image: UIImage
        
        var body: some View {
            VStack(spacing: 0) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 110, height: 110)
                    .clipped()
                Color.clear.frame(height: 28)
            }
            .frame(width: 130, height: 148)
            .clipShape(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .background {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255),
                                Color(red: 115 / 255, green: 115 / 255, blue: 115 / 255),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(0.91))
                    }
                    .shadow(
                        color: Color(
                            red: 116 / 255,
                            green: 116 / 255,
                            blue: 78 / 255
                        ).opacity(0.25),
                        radius: 4.5,
                        x: 0,
                        y: 2
                    )
            }
        }
    }
}

#Preview {
    OnboardingScreenshotSummaryView(
        onContinue: {},
        screenshotImages: [],
        totalCount: 142,
        totalSizeGB: 0.5,
        isProcessing: .constant(true)
    )
}
