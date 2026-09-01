//
//  ParseScreenshot.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/26/26.
//

import UIKit
import Vision

func recognizeText(
    in image: UIImage,
    recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
    languages: [String]? = nil,
    usesLanguageCorrection: Bool = true,
) async -> String {
    guard let cgImage = image.cgImage else { return "" }
    return await Task.detached(priority: .userInitiated) {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        if let languages, !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        request.usesLanguageCorrection = usesLanguageCorrection
        do {
            try requestHandler.perform([request])
            guard let observations = request.results else { return "" }
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            print("Unable to perform the requests: \(error).")
            return ""
        }
    }.value
}
