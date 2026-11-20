#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Minimal `FileDocument` carrying bytes already in memory, for `fileExporter`.
struct WorkspaceExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.item]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
