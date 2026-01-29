//
//  ParseScreenshot.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/26/26.
//

// OCRTextRecognizer.swift

import UIKit
import Vision

func recognizeText(
    in image: UIImage,
    recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
    languages: [String]? = nil,
    usesLanguageCorrection: Bool = true,
) async -> String {
    guard let cgImage = image.cgImage else { return "" }

    // Create a new image-request handler.
    let requestHandler = VNImageRequestHandler(cgImage: cgImage)

    // Create a new request to recognize text.
    let request = VNRecognizeTextRequest()

    do {
        // Perform the text-recognition request.
        try requestHandler.perform([request])
        guard
            let observations =
                request.results
        else {
            return ""
        }
        
        let recognizedStrings = observations.compactMap { observation in
            return observation.topCandidates(1).first?.string
        }

        return recognizedStrings.joined(separator: "\n")
    } catch {
        print("Unable to perform the requests: \(error).")
    }

    return ""

}
