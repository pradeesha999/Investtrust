import FirebaseStorage
import Foundation

// Adds async/await wrappers to Firebase Storage's callback-based API
extension StorageReference {
    func putDataAsync(_ data: Data, metadata: StorageMetadata?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            putData(data, metadata: metadata) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    func getDataAsync(maxSize: Int64) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            getData(maxSize: maxSize) { data, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "Investtrust",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Empty download data."]
                    ))
                }
            }
        }
    }

    func downloadURLAsync() async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            downloadURL { url, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "Investtrust",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Missing download URL."]
                    ))
                }
            }
        }
    }
}
