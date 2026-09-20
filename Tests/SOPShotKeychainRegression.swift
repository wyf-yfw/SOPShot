import Foundation

@main
struct SOPShotAPIKeyStoreRegression {
    static func main() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sopshot-api-key-regression-\(UUID().uuidString)", isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("api-keys.json", isDirectory: false)
        let store = APIKeyStore(fileURL: fileURL)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try store.save("regression-test-key", for: .deepSeek)

        let recreated = APIKeyStore(fileURL: fileURL)
        guard try recreated.load(for: .deepSeek) == "regression-test-key" else {
            throw RegressionError.expectedPersistedKey
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o777 == 0o600 else {
            throw RegressionError.expectedPrivateFile
        }

        try recreated.save("", for: .deepSeek)
        guard try APIKeyStore(fileURL: fileURL).load(for: .deepSeek) == nil else {
            throw RegressionError.expectedClearedKey
        }

        print("SOPShot local API Key persistence and permissions regression: PASS")
    }
}

private enum RegressionError: Error {
    case expectedPersistedKey
    case expectedPrivateFile
    case expectedClearedKey
}
