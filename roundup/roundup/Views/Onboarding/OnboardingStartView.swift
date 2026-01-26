//
//  OnboardingStartView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//

import Photos
import SwiftUI

struct OnboardingStartView: View {
    @Binding var step: Int
    @State private var screenshotManager = ScreenshotManager()
    var screenshots: [PHAsset] = []

    var body: some View {
        VStack {

            ZStack {
                Image("background")
                    .resizable()
                    .frame(maxHeight: .infinity)

                LinearGradient(
                    colors: [
                        .white.opacity(0), .white.opacity(0),
                        .white.opacity(1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxHeight: .infinity)

                VStack {
                    Text("the round up").font(
                        .editorialNew(.italic, size: 24)
                    )
                    Spacer()
                    Text("don't let your screenshots disappear")
                        .multilineTextAlignment(.center)
                        .font(
                            .editorialNew(.regular, size: 32)
                        )
                    StyledButton(
                        title: "allow access to photos to start",
                        systemName: "heart.fill"
                    ) {
                        screenshotManager.requestPhotoLibraryAccess {
                            granted in
                            guard granted else {
                                print("Photo library access denied")
                                return
                            }

                            step = 2
                            // Fetch screenshots
                            screenshotManager.fetchScreenshots {
                                screenshots in
                                //                                screenshots = screenshots
                                print("Found \(screenshots.count) screenshots")

                                // Load first screenshot as example
                                if let firstScreenshot = screenshots.first {
                                    screenshotManager.loadImage(
                                        from: firstScreenshot
                                    ) { image in
                                        if let image = image {
                                            print(
                                                "Loaded screenshot: \(image.size)"
                                            )
                                            // Use the image here
                                            Task {
                                                await uploadImage(
                                                    fileName: "screenshot.png",
                                                    image: image
                                                )
                                            }
                                        }
                                    }

                                    // Get metadata
                                    let info =
                                        screenshotManager
                                        .getScreenshotInfo(
                                            from: firstScreenshot
                                        )
                                    print("Screenshot info: \(info)")
                                }
                            }
                        }
                    }

                }.padding(.top, 100).padding(.bottom, 20)
            }
            .frame(maxHeight: 500)
            ZStack {
                Image("blackhole")
                    .resizable()
                    .frame(maxHeight: .infinity)
                LinearGradient(
                    colors: [
                        .white.opacity(1), .white.opacity(0.5),
                        .white.opacity(0), .white.opacity(0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxHeight: .infinity)
                Image("blonde")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .position(x: 130, y: 55)
                    .jiggle(amount: 1.0, duration: 0.25)
                Image("polaroid1")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .position(x: 300, y: 70)
                    .jiggle(amount: 1.5, duration: 0.35)
                Image("polaroid2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .position(x: 50, y: 180)
                    .jiggle(amount: 1.0, duration: 0.45)
                Image("maps")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .position(x: 245, y: 190)
                    .jiggle(amount: 2.0, duration: 0.25)

                GeometryReader { geometry in
                    Image("glow")
                        .resizable()
                        .frame(maxHeight: 300)
                        .position(x: geometry.size.width / 2, y: 140)
                }
                Image("dtmf")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .position(x: 280, y: 300)
                    .jiggle(amount: 0.5, duration: 0.15)
            }
        }
        .ignoresSafeArea()
    }
}
