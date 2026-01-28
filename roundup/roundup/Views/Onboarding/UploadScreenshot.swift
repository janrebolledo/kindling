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
    fileName: String,
    image: UIImage,
) async throws -> [Item] {
    let text = await recognizeText(
        in: image,
        recognitionLevel: .accurate,
        languages: ["en"],
        usesLanguageCorrection: true
    )

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
        "entries": text.joined(separator: "\n")
    ]
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: urlRequest)

    if let httpResponse = response as? HTTPURLResponse {
        print("Status code:", httpResponse.statusCode)
    }
    print(data)

    let decoder = JSONDecoder()
    let items = try decoder.decode([Item].self, from: data)
    print(items)

    return items
}
