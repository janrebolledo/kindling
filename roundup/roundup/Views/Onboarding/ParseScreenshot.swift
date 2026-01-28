//
//  ParseScreenshot.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/26/26.
//

// OCRTextRecognizer.swift

import UIKit
import Vision

/// A utility responsible for performing OCR (text recognition) on images using Apple's Vision framework.
enum OCRTextRecognizer {

    /// Recognizes text in the given UIImage.
    ///
    /// - Parameters:
    ///   - image: The source UIImage to perform OCR on.
    ///   - recognitionLevel: The Vision recognition level to use (.accurate or .fast). Defaults to .accurate.
    ///   - languages: Optional array of language codes to bias recognition towards.
    ///                Example: ["en-US"], ["en", "es"], ["zh-Hant", "zh-Hans"].
    ///   - usesLanguageCorrection: Whether to enable language correction. Defaults to true.
    ///   - completion: Called on the main thread with either the recognized strings or an error.
    static func recognizeText(
        in image: UIImage,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        languages: [String]? = nil,
        usesLanguageCorrection: Bool = true,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        // Ensure we can get a CGImage from the UIImage
        guard let cgImage = image.cgImage else {
            let error = NSError(
                domain: "OCRTextRecognizer",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to create CGImage from UIImage."
                ]
            )
            completion(.failure(error))
            return
        }

        // Create the text recognition request
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard
                let observations = request.results
                    as? [VNRecognizedTextObservation]
            else {
                DispatchQueue.main.async {
                    completion(.success([]))
                }
                return
            }

            // Extract the top candidate string from each observation
            let recognizedStrings: [String] = observations.compactMap {
                observation in
                observation.topCandidates(1).first?.string
            }

            DispatchQueue.main.async {
                completion(.success(recognizedStrings))
            }
        }

        // Configure request parameters (recognition level, languages, corrections)
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = usesLanguageCorrection
        request.recognitionLanguages = languages!

        // Create the request handler
        let requestHandler = VNImageRequestHandler(
            cgImage: cgImage,
            options: [:]
        )

        // Perform OCR on a background queue to avoid blocking the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
