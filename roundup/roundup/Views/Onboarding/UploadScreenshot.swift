//
//  UploadScreenshot.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/26/26.
//

import Foundation
import Photos
import UIKit

func uploadImage(fileName: String, image: UIImage) async {
    // TODO: make this a more permanent url, ie get this hosted!!
    let url = URL(string: "http://192.168.50.40:3000/")
    let boundary = UUID().uuidString

    let session = URLSession.shared

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

    session.uploadTask(
        with: urlRequest,
        from: data,
        completionHandler: { responseData, response, error in
            if error == nil {
                let jsonData = try? JSONSerialization.jsonObject(
                    with: responseData!,
                    options: .allowFragments
                )
                if let json = jsonData as? [String: Any] {
                    print(json)
                }
            }
        }
    ).resume()
}
