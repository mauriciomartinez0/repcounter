// The catalog that ships with the app. Until the first download from the API
// the repository uses this copy. Resources/Catalog/catalog.json has the same
// shape as GET /exercises and the same rows as the API migrations 002 and 003
// (generated from a curated selection of hasaneyldrm/exercises-dataset).

import Foundation
import UIKit

let seedExercises: [Exercise] = {
    guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "Catalog"),
          let data = try? Data(contentsOf: url),
          let list = try? JSONSerialization.jsonObject(with: data) as? [Any]
    else { return [] }
    return list.compactMap { ($0 as? JSON).flatMap { try? Exercise(json: $0) } }
}()

/// Thumbnails (180 × 180) bundled per exercise id. Media © Gym visual —
/// https://gymvisual.com/, distributed with permission by the dataset.
@MainActor
enum ExerciseImages {
    private static let cache = NSCache<NSString, UIImage>()
    private static var missing: Set<String> = []

    static func image(for exerciseId: String) -> UIImage? {
        if let cached = cache.object(forKey: exerciseId as NSString) { return cached }
        if missing.contains(exerciseId) { return nil }
        guard let url = Bundle.module.url(forResource: exerciseId, withExtension: "jpg",
                                          subdirectory: "ExerciseImages"),
              let image = UIImage(contentsOfFile: url.path)
        else {
            missing.insert(exerciseId)
            return nil
        }
        cache.setObject(image, forKey: exerciseId as NSString)
        return image
    }
}
