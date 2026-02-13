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

struct ItemWrapper: Decodable, Identifiable {
    let id: String
    let data: Item
}

private let ideasURL = URL(string: "http://localhost:3000/ideas")!

/// Builds the OCR entries and shared request for POST /ideas. Caller sets body and uses for streaming or single response.
private func makeEntriesAndRequest(entries: [Upload]) throws -> (URLRequest, [Upload]) {
    var urlRequest = URLRequest(url: ideasURL)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    urlRequest.httpBody = try JSONEncoder().encode(entries)
    return (urlRequest, entries)
}

/// Streams ideas from POST /ideas (SSE) and yields each `ItemWrapper` as it arrives. Finishes when the server sends the "done" event.
func uploadImagesStreaming(
    images: [(String, UIImage?)]
) -> AsyncThrowingStream<ItemWrapper, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                let entries: [Upload] = await withTaskGroup(of: (String, String).self) { group in
                    for image in images {
                        group.addTask {
                            (
                                image.0,
                                await recognizeText(
                                    in: image.1!,
                                    recognitionLevel: .fast,
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

                let (urlRequest, _) = try makeEntriesAndRequest(entries: entries)
                let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ..< 300).contains(httpResponse.statusCode)
                else {
                    continuation.finish(throwing: NSError(domain: "UploadScreenshot", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                    return
                }

                let decoder = JSONDecoder()
                var byteBuffer: [UInt8] = []
                let doubleNewline: [UInt8] = [10, 10]
                for try await byte in bytes {
                    byteBuffer.append(byte)
                    while true {
                        var idx = 0
                        while idx + 1 < byteBuffer.count {
                            if byteBuffer[idx] == doubleNewline[0], byteBuffer[idx + 1] == doubleNewline[1] { break }
                            idx += 1
                        }
                        guard idx + 1 < byteBuffer.count else { break }
                        let eventBytes = Array(byteBuffer[..<idx])
                        byteBuffer.removeFirst(idx + 2)
                        guard let eventBlock = String(bytes: eventBytes, encoding: .utf8) else { break }
                        let eventType = eventBlock.split(separator: "\n").reduce(into: (event: "", data: "")) { acc, line in
                            let s = String(line)
                            if s.hasPrefix("event: ") {
                                acc.event = String(s.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                            } else if s.hasPrefix("data: ") {
                                acc.data = (acc.data.isEmpty ? "" : acc.data + "\n") + String(s.dropFirst(6))
                            }
                        }
                        if eventType.event == "done" {
                            continuation.finish()
                            return
                        }
                        if eventType.event == "idea", !eventType.data.isEmpty {
                            if let data = eventType.data.data(using: .utf8),
                               let wrapper = try? decoder.decode(ItemWrapper.self, from: data) {
                                continuation.yield(wrapper)
                            }
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

func uploadImages(images: [(String, UIImage?)]) async throws -> [ItemWrapper] {
    var items: [ItemWrapper] = []
    for try await item in uploadImagesStreaming(images: images) {
        items.append(item)
    }
    return items
}
