//
//  UploadScreenshot.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/26/26.
//

import Auth
import Foundation
import Photos
import Supabase
import UIKit
import Vision
import os

struct Upload: Codable {
    let id: String
    let text: String
}

// ItemWrapper and collectionItemWrapper will conform to this protocol

protocol CardData {
    var id: Int { get }
    var local_id: String { get }
    var ideas: Item? { get }
    var screenshotLocalIDs: [String] { get }
    var collectionItemIDs: [Int] { get }
}

extension CardData {
    var screenshotLocalIDs: [String] {
        local_id.isEmpty ? [] : [local_id]
    }

    var collectionItemIDs: [Int] {
        [id]
    }
}

struct ItemWrapper: Codable, Identifiable, CardData {
    let id: Int
    let local_id: String
    let idea_id: Int
    let highlights: String?
    let highlights_sources: [String]?
    let ideas: Item?
}

enum ScreenshotUploadEvent {
    case idea(ItemWrapper)
    case processed(String)
}

private struct ProcessedScreenshotEvent: Decodable {
    let id: String
}

// Debug builds default to live. Remove USE_LIVE_BACKEND from the Debug
// compilation conditions when a local backend is needed.
#if DEBUG && !USE_LIVE_BACKEND
nonisolated let backendBaseURL = URL(string: "http://192.168.1.114:3000")!
nonisolated let webBaseURL = URL(string: "http://10.104.192.97:4321")!
#else
nonisolated let backendBaseURL = URL(string: "https://api.getkindl.ing")!
nonisolated let webBaseURL = URL(string: "https://getkindl.ing")!
#endif

/// Builds a request for cloud inference or for server enrichment of an
/// extraction produced by Apple's on-device model.
private func makeRequest(url: URL, body: Data) -> URLRequest {
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    if let userID = supabase.auth.currentUser?.id {
        urlRequest.setValue(userID.uuidString, forHTTPHeaderField: "X-User-Id")
    }
    urlRequest.httpBody = body
    return urlRequest
}

private nonisolated let screenshotUploadLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "kindling",
    category: "ScreenshotUpload"
)

/// Streams ideas from POST /ideas (SSE) and yields each `ItemWrapper` as it arrives. Finishes when the server sends the "done" event.
func uploadImagesStreaming(
    images: [(String, UIImage?)]
) -> AsyncThrowingStream<ScreenshotUploadEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                let entries: [Upload] = await withTaskGroup(
                    of: (String, String).self
                ) { group in
                    for image in images {
                        group.addTask {
                            guard let uiImage = image.1 else {
                                screenshotUploadLogger.error(
                                    "Skipping screenshot with no image, id=\(image.0, privacy: .private(mask: .hash))"
                                )
                                return (image.0, "")
                            }

                            let text = await recognizeText(
                                in: uiImage,
                                recognitionLevel: .fast,
                                languages: ["en"],
                                usesLanguageCorrection: true
                            )
                            return (image.0, text)
                        }
                    }
                    var results: [Upload] = []
                    for await result in group {
                        results.append(Upload(id: result.0, text: result.1))
                    }
                    return results
                }
                let providerRaw = UserDefaults.standard.string(
                    forKey: InferenceProvider.defaultsKey
                )
                let provider = InferenceProvider(rawValue: providerRaw ?? "") ?? .cloud
                let urlRequest: URLRequest
                switch provider {
                case .cloud:
                    urlRequest = makeRequest(
                        url: backendBaseURL.appendingPathComponent("ideas"),
                        body: try JSONEncoder().encode(entries)
                    )
                case .appleFoundationModels:
                    guard LocalScreenshotInference.isAvailable else {
                        screenshotUploadLogger.error(
                            "Local inference requested but Apple Intelligence is unavailable"
                        )
                        throw ScreenshotInferenceError.appleModelUnavailable
                    }
                    let extracted = try await LocalScreenshotInference.extract(entries)
                    urlRequest = makeRequest(
                        url: backendBaseURL.appendingPathComponent("ideas/extracted"),
                        body: try JSONEncoder().encode(extracted)
                    )
                }
                let (bytes, response) = try await URLSession.shared.bytes(
                    for: urlRequest
                )

                guard let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode)
                else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    screenshotUploadLogger.error(
                        "Screenshot upload received an invalid HTTP response, status=\(statusCode)"
                    )
                    continuation.finish(
                        throwing: NSError(
                            domain: "UploadScreenshot",
                            code: -1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Invalid response"
                            ]
                        )
                    )
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
                            if byteBuffer[idx] == doubleNewline[0],
                                byteBuffer[idx + 1] == doubleNewline[1]
                            {
                                break
                            }
                            idx += 1
                        }
                        guard idx + 1 < byteBuffer.count else { break }
                        let eventBytes = Array(byteBuffer[..<idx])
                        byteBuffer.removeFirst(idx + 2)
                        guard
                            let eventBlock = String(
                                bytes: eventBytes,
                                encoding: .utf8
                            )
                        else {
                            screenshotUploadLogger.error("Received invalid UTF-8 in SSE response")
                            break
                        }
                        let eventType = eventBlock.split(separator: "\n")
                            .reduce(into: (event: "", data: "")) { acc, line in
                                let s = String(line)
                                if s.hasPrefix("event: ") {
                                    acc.event = String(s.dropFirst(7))
                                        .trimmingCharacters(in: .whitespaces)
                                } else if s.hasPrefix("data: ") {
                                    acc.data =
                                        (acc.data.isEmpty
                                            ? "" : acc.data + "\n")
                                        + String(s.dropFirst(6))
                                }
                            }
                        if eventType.event == "done" {
                            continuation.finish()
                            return
                        }
                        if eventType.event == "idea", !eventType.data.isEmpty {
                            if let data = eventType.data.data(using: .utf8),
                                let wrapper = try? decoder.decode(
                                    ItemWrapper.self,
                                    from: data
                                )
                            {
                                continuation.yield(.idea(wrapper))
                            } else {
                                screenshotUploadLogger.error("Failed to decode SSE idea event")
                            }
                        }
                        if eventType.event == "processed", !eventType.data.isEmpty {
                            if let data = eventType.data.data(using: .utf8),
                                let processed = try? decoder.decode(
                                    ProcessedScreenshotEvent.self,
                                    from: data
                                )
                            {
                                continuation.yield(.processed(processed.id))
                            } else {
                                screenshotUploadLogger.error("Failed to decode SSE processed event")
                            }
                        }
                    }
                }
                screenshotUploadLogger.error(
                    "Screenshot upload stream ended without a done event"
                )
                continuation.finish()
            } catch {
                screenshotUploadLogger.error(
                    "Screenshot upload failed: \(String(describing: error), privacy: .public)"
                )
                continuation.finish(throwing: error)
            }
        }
    }
}

enum ScreenshotInferenceError: LocalizedError {
    case appleModelUnavailable

    var errorDescription: String? {
        "Apple Intelligence isn't available on this iPhone. Choose Kindling Cloud in settings or finish enabling Apple Intelligence."
    }
}

func uploadImages(images: [(String, UIImage?)]) async throws -> [ItemWrapper] {
    var items: [ItemWrapper] = []
    for try await event in uploadImagesStreaming(images: images) {
        if case .idea(let item) = event {
            items.append(item)
        }
    }
    print(items)
    return items
}
