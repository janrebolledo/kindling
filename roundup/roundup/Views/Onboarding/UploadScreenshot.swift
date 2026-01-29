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

func uploadImages(
    images: [UIImage]
) async throws -> [Item] {
    let entries: [String] = await withTaskGroup(of: String.self) { group in

        for image in images {
            group.addTask {
                await recognizeText(
                    in: image,
                    recognitionLevel: .accurate,
                    languages: ["en"],
                    usesLanguageCorrection: true
                )
            }
        }

        var results: [String] = []
        for await result in group {
            results.append(result)
        }
        return results
    }

    // TODO: make this a more permanent url, ie get this hosted!!
    let url = URL(string: "http://localhost:3000/ideas")

    var urlRequest = URLRequest(url: url!)
    urlRequest.httpMethod = "POST"

    urlRequest.setValue(
        "application/x-www-form-urlencoded",
        forHTTPHeaderField: "Content-Type"
    )
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: entries)

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
