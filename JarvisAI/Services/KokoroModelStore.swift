import CryptoKit
import Foundation
import Combine

enum KokoroError: LocalizedError {
    case download, invalidFile(String), unavailable, busy, synthesis, timeout

    var errorDescription: String? {
        switch self {
        case .download: "No se pudo descargar Kokoro. Comprueba la conexión y vuelve a intentarlo."
        case .invalidFile(let name): "La verificación del archivo \(name) falló. Vuelve a descargar Kokoro."
        case .unavailable: "El modelo Kokoro no está listo. Comprueba la descarga en Configuración."
        case .busy: "Kokoro todavía está terminando una síntesis anterior."
        case .synthesis: "Kokoro no pudo generar o reproducir el audio."
        case .timeout: "Kokoro tardó demasiado en generar el audio."
        }
    }
}

@MainActor
final class KokoroModelStore: ObservableObject {
    enum Status: Equatable {
        case missing, downloading, ready, failed(String)
    }

    private struct Asset: Sendable {
        let name: String
        let size: Int64
        let sha256: String
    }

    private nonisolated static let assets = [
        Asset(name: "model.int8.onnx", size: 114_202_993, sha256: "75635ea3b85a32d00094dcdd61a258aba87c160f7c264c304a7b3ae9d734195e"),
        Asset(name: "voices.bin", size: 28_200_960, sha256: "1c5a5b983d3d50d8586d437a51f3faa2da7919ce76a013c081e65671a3447c29"),
        Asset(name: "tokens.txt", size: 687, sha256: "6ebb6bb288f20f3ae8d004d3c2ca27697da27c037d75e81a60e2a6a663f95425")
    ]

    @Published private(set) var status: Status
    private var downloadTask: Task<Void, Never>?
    private let folder = URL.applicationSupportDirectory.appendingPathComponent("Kokoro-v1.0-int8", isDirectory: true)

    var installedFolder: URL? {
        Self.filesPresent(in: folder) ? folder : nil
    }

    init() {
        status = Self.filesPresent(in: folder) ? .ready : .missing
    }

    func download() {
        guard downloadTask == nil, installedFolder == nil else { return }
        status = .downloading
        downloadTask = Task { [folder] in
            defer { downloadTask = nil }
            do {
                try await Self.install(in: folder)
                status = .ready
            } catch is CancellationError {
                status = .missing
            } catch {
                status = Task.isCancelled ? .missing : .failed(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func remove() {
        guard downloadTask == nil else { return }
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            status = .missing
        } catch {
            status = .failed("No se pudieron eliminar los archivos de Kokoro. \(error.localizedDescription)")
        }
    }

    private nonisolated static func filesPresent(in folder: URL) -> Bool {
        assets.allSatisfy { asset in
            let file = folder.appendingPathComponent(asset.name)
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && values?.fileSize == Int(asset.size)
        }
    }

    private nonisolated static func install(in folder: URL) async throws {
        let files = FileManager.default
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: temporary) }

        let base = URL(string: "https://huggingface.co/csukuangfj/kokoro-int8-multi-lang-v1_0/resolve/57adb37fc0e8d4bd430cfc1b8f8c2294945b9af2/")!
        for asset in assets {
            try Task.checkCancellation()
            let url = base.appendingPathComponent(asset.name)
            let (download, response) = try await URLSession.shared.download(from: url)
            defer { try? files.removeItem(at: download) }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw KokoroError.download
            }
            let values = try download.resourceValues(forKeys: [.fileSizeKey])
            guard values.fileSize == Int(asset.size), try digest(of: download) == asset.sha256 else {
                throw KokoroError.invalidFile(asset.name)
            }
            try files.moveItem(at: download, to: temporary.appendingPathComponent(asset.name))
        }
        try Task.checkCancellation()
        try files.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        var staged = temporary
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try staged.setResourceValues(resourceValues)
        if files.fileExists(atPath: folder.path) {
            _ = try files.replaceItemAt(folder, withItemAt: staged, options: .usingNewMetadataOnly)
        } else {
            try files.moveItem(at: staged, to: folder)
        }
    }

    private nonisolated static func digest(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var sha = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            sha.update(data: data)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
