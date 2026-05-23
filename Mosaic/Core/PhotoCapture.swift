//
//  PhotoCapture.swift
//  Mosaic
//
//  Saves a UIImage to the user's Photos library. First call triggers
//  the system "Add to Photos" authorization sheet
//  (NSPhotoLibraryAddUsageDescription rationale shown). We only ask
//  for `.addOnly` since Mosaic just writes, never reads.
//

import UIKit
import Photos
import os

enum PhotoCapture {

    enum SaveError: Error {
        case notAuthorized
        case underlying(Error)
    }

    static func save(_ image: UIImage,
                     completion: @escaping (Result<Void, SaveError>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Log.ui.warning("photo capture: library access denied (status=\(status.rawValue))")
                DispatchQueue.main.async { completion(.failure(.notAuthorized)) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        Log.ui.info("photo capture: saved")
                        completion(.success(()))
                    } else {
                        let underlying = error ?? NSError(
                            domain: "Mosaic.PhotoCapture", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Unknown error"]
                        )
                        Log.ui.error("photo capture failed: \(underlying.localizedDescription, privacy: .public)")
                        completion(.failure(.underlying(underlying)))
                    }
                }
            }
        }
    }
}
