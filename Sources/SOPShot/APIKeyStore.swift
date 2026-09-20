import Foundation

enum APIKeyStoreError: LocalizedError {
    case unableToRead
    case unableToWrite
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .unableToRead:
            return "无法读取本机 API Key 配置。"
        case .unableToWrite:
            return "无法保存本机 API Key 配置。"
        case .invalidStoredData:
            return "本机 API Key 配置格式无效。"
        }
    }
}

struct APIKeyStore: Sendable {
    private static let applicationDirectory = "SOPShot"
    private static let fileName = "api-keys.json"

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load(for provider: ModelProvider) throws -> String? {
        try load(forAccount: provider.rawValue)
    }

    func save(_ value: String, for provider: ModelProvider) throws {
        try save(value, forAccount: provider.rawValue)
    }

    func load(forAccount account: String) throws -> String? {
        let values = try readValues()
        return values[account]
    }

    func save(_ value: String, forAccount account: String) throws {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = try readValues()

        if cleanValue.isEmpty {
            values.removeValue(forKey: account)
        } else {
            values[account] = cleanValue
        }

        try writeValues(values)
    }

    private func readValues() throws -> [String: String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw APIKeyStoreError.unableToRead
        }

        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw APIKeyStoreError.invalidStoredData
        }
    }

    private func writeValues(_ values: [String: String]) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: directoryURL.path
            )

            let data = try JSONEncoder().encode(values)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw APIKeyStoreError.unableToWrite
        }
    }

    private static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupportURL
            .appendingPathComponent(applicationDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
