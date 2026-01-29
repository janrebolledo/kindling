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

struct Upload: Codable {
    let id: String
    let text: String
}

func uploadImages(
    images: [(String, UIImage?)]
) async throws -> [Item] {
    let entries: [Upload] = await withTaskGroup(
        of: (String, String).self
    ) { group in

        for image in images {
            group.addTask {
                return (
                    id: image.0,
                    text: await recognizeText(
                        in: image.1!,
                        recognitionLevel: .accurate,
                        languages: ["en"],
                        usesLanguageCorrection: true
                    )
                )
            }
        }

        var results: [Upload] = []
        for await result in group {
            results.append(Upload(id: result.0, text: result.1))
        }
        return results
    }
    print(entries)

    // TODO: make this a more permanent url, ie get this hosted!!
    let url = URL(string: "http://localhost:3000/ideas")

    var urlRequest = URLRequest(url: url!)
    urlRequest.httpMethod = "POST"

    urlRequest.setValue(
        "application/x-www-form-urlencoded",
        forHTTPHeaderField: "Content-Type"
    )
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    let encoder = JSONEncoder()
    urlRequest.httpBody = try encoder.encode(entries)
    
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
