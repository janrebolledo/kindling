//
//  UploadScreenshot.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/26/26.
//

import Foundation
import Photos
import UIKit

func uploadImage(
    fileName: String,
    image: UIImage,
    completion: @escaping ([Item]?) -> Void
) async {
    // TODO: make this a more permanent url, ie get this hosted!!
    let url = URL(string: "http://10.110.198.101:3000/")
    let boundary = UUID().uuidString

    _ = URLSession.shared

    var urlRequest = URLRequest(url: url!)
    urlRequest.httpMethod = "POST"

    urlRequest.setValue(
        "multipart/form-data; boundary=\(boundary)",
        forHTTPHeaderField: "Content-Type"
    )

    var data = Data()

    // Add the image data to the raw http request data
    data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
    let paramName = "file"
    data.append(
        "Content-Disposition: form-data; name=\"\(paramName)\"; filename=\"\(fileName)\"\r\n"
            .data(using: .utf8)!
    )
    data.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
    data.append(image.pngData()!)

    data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    do {
        let (responseData, response) = try await URLSession.shared.upload(
            for: urlRequest,
            from: data
        )

        if let httpResponse = response as? HTTPURLResponse {
            print("Status code:", httpResponse.statusCode)
        }

        guard !responseData.isEmpty else {
            print("Empty response body")
            return
        }

        //        if let raw = String(data: responseData, encoding: .utf8) {
        //            print("Raw response:", raw)
        //        }

        let decoder = JSONDecoder()
        // If your JSON is a top-level array of items:
        let items = try decoder.decode([Item].self, from: responseData)
        completion(items)
    } catch {
        print("Upload failed with error:", error)
        completion(nil)
    }
}
