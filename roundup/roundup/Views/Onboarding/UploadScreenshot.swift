//
//  UploadScreenshot.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/26/26.
//

import Foundation
import Photos
import UIKit
import Vision

func uploadImage(
    imageText: String,
) async throws -> [Item]? {
    // TODO: make this a more permanent url, ie get this hosted!!
    let url = URL(string: "http://10.110.198.101:3000/v2/places")
    print("req start")

    var urlRequest = URLRequest(url: url!)
    urlRequest.httpMethod = "POST"

    urlRequest.setValue(
        "application/x-www-form-urlencoded",
        forHTTPHeaderField: "Content-Type"
    )
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
    let body: [String: String] = [
        "entries": imageText
    ]
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: urlRequest)

    if let httpResponse = response as? HTTPURLResponse {
        print("Status code:", httpResponse.statusCode)
    }

    let decoder = JSONDecoder()
    let items = try decoder.decode([Item].self, from: data)
    
    return items
}

func parseAndUploadImage(
    fileName: String,
    image: UIImage,
    completion: @escaping ([Item]?) -> Void
) async {
    var screenshotText: String = ""

    OCRTextRecognizer.recognizeText(
        in: image,
        recognitionLevel: .accurate,
        languages: ["en"],
        usesLanguageCorrection: true
    ) { result in
        switch result {
        case .success(let strings):
            screenshotText = strings.joined(separator: "\n")
            Task {
                do {
                    let items = try await uploadImage(imageText: screenshotText)
                } catch {
                    print(error)
                }
            }

        case .failure(let error):
            print("OCR failed: \(error.localizedDescription)")
        }
    }

    return

}
