// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import Foundation
import PencilKit
import PDFKit
import UIKit

enum StoreError: LocalizedError {
    case invalidPDF
    case lockedPDF

    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "That file isn't a readable PDF."
        case .lockedPDF: return "This PDF is password protected. Remove the password and try again."
        }
    }
}

/// File-backed storage. Each notebook is a folder:
///
///     Notebooks/<uuid>/notebook.json
///     Notebooks/<uuid>/pages/<page-uuid>.drawing   (PKDrawing data)
///     Notebooks/<uuid>/source.pdf                  (only for imported PDFs)
final class NotebookStore: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []

    let root: URL
    private let fm = FileManager.default
    private var pdfCache: [UUID: PDFDocument] = [:]
    private let thumbnailCache = NSCache<NSString, UIImage>()

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.root = documents.appendingPathComponent("Notebooks", isDirectory: true)
        }
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Paths

    func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func pagesDirectory(_ id: UUID) -> URL {
        directory(for: id).appendingPathComponent("pages", isDirectory: true)
    }

    private func drawingURL(_ notebookID: UUID, _ pageID: UUID) -> URL {
        pagesDirectory(notebookID).appendingPathComponent("\(pageID.uuidString).drawing")
    }

    // MARK: - Loading

    func load() {
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Notebook] = []
        for folder in folders {
            let meta = folder.appendingPathComponent("notebook.json")
            guard let data = try? Data(contentsOf: meta),
                  let notebook = try? decoder.decode(Notebook.self, from: data) else { continue }
            loaded.append(notebook)
        }
        notebooks = loaded.sorted { $0.modified > $1.modified }
    }

    func notebook(_ id: UUID) -> Notebook? {
        notebooks.first { $0.id == id }
    }

    private func write(_ notebook: Notebook) {
        let dir = directory(for: notebook.id)
        try? fm.createDirectory(at: pagesDirectory(notebook.id), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(notebook) else { return }
        try? data.write(to: dir.appendingPathComponent("notebook.json"), options: .atomic)
    }

    private func mutate(_ id: UUID, touch: Bool = true, _ body: (inout Notebook) -> Void) {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        var notebook = notebooks[index]
        body(&notebook)
        if touch { notebook.modified = Date() }
        notebooks[index] = notebook
        write(notebook)
    }

    // MARK: - Notebooks

    @discardableResult
    func createNotebook(title: String? = nil, background: PageBackground, coverHex: String? = nil) -> Notebook {
        let notebook = Notebook(
            title: title ?? "Notebook \(notebooks.count + 1)",
            coverColorHex: coverHex ?? Notebook.coverColors.randomElement() ?? "#5856D6",
            pages: [NotebookPage(background: background, size: PageRenderer.defaultSize)]
        )
        write(notebook)
        notebooks.append(notebook)
        return notebook
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id) { $0.title = trimmed }
    }

    func touch(_ id: UUID) {
        mutate(id) { _ in }
    }

    func delete(_ id: UUID) {
        try? fm.removeItem(at: directory(for: id))
        pdfCache[id] = nil
        notebooks.removeAll { $0.id == id }
    }

    // MARK: - Pages

    @discardableResult
    func addPage(to id: UUID, after index: Int, background: PageBackground) -> NotebookPage? {
        guard let current = notebook(id) else { return nil }
        let reference = current.pages.indices.contains(index) ? current.pages[index] : current.pages.last
        let page = NotebookPage(background: background, size: reference?.size ?? PageRenderer.defaultSize)
        mutate(id) { $0.pages.insert(page, at: min(index + 1, $0.pages.count)) }
        return page
    }

    func duplicatePage(in id: UUID, at index: Int) {
        guard let current = notebook(id), current.pages.indices.contains(index) else { return }
        var copy = current.pages[index]
        let sourceID = copy.id
        copy.id = UUID()
        let source = drawingURL(id, sourceID)
        if fm.fileExists(atPath: source.path) {
            try? fm.copyItem(at: source, to: drawingURL(id, copy.id))
        }
        mutate(id) { $0.pages.insert(copy, at: index + 1) }
    }

    func deletePage(in id: UUID, at index: Int) {
        guard let current = notebook(id),
              current.pages.count > 1,
              current.pages.indices.contains(index) else { return }
        let pageID = current.pages[index].id
        try? fm.removeItem(at: drawingURL(id, pageID))
        mutate(id) { $0.pages.remove(at: index) }
    }

    // MARK: - Drawings

    func loadDrawing(notebookID: UUID, pageID: UUID) -> PKDrawing {
        guard let data = try? Data(contentsOf: drawingURL(notebookID, pageID)),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func saveDrawing(_ drawing: PKDrawing, notebookID: UUID, pageID: UUID) {
        try? fm.createDirectory(at: pagesDirectory(notebookID), withIntermediateDirectories: true)
        try? drawing.dataRepresentation().write(to: drawingURL(notebookID, pageID), options: .atomic)
    }

    // MARK: - PDF

    func pdfDocument(for notebook: Notebook) -> PDFDocument? {
        guard let name = notebook.sourcePDFName else { return nil }
        if let cached = pdfCache[notebook.id] { return cached }
        let document = PDFDocument(url: directory(for: notebook.id).appendingPathComponent(name))
        pdfCache[notebook.id] = document
        return document
    }

    /// Copies the PDF into a new notebook with one page per PDF page, ready to annotate.
    @discardableResult
    func importPDF(from url: URL) throws -> Notebook {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw StoreError.invalidPDF
        }
        if document.isLocked { throw StoreError.lockedPDF }

        let id = UUID()
        let folder = directory(for: id)
        try fm.createDirectory(at: pagesDirectory(id), withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: folder.appendingPathComponent("source.pdf"))

        var pages: [NotebookPage] = []
        for index in 0..<document.pageCount {
            guard let pdfPage = document.page(at: index) else { continue }
            pages.append(NotebookPage(
                background: .pdf,
                size: PageRenderer.size(of: pdfPage),
                pdfPageIndex: index
            ))
        }
        guard !pages.isEmpty else {
            try? fm.removeItem(at: folder)
            throw StoreError.invalidPDF
        }

        let notebook = Notebook(
            id: id,
            title: url.deletingPathExtension().lastPathComponent,
            coverColorHex: Notebook.coverColors.randomElement() ?? "#5856D6",
            pages: pages,
            sourcePDFName: "source.pdf"
        )
        write(notebook)
        notebooks.append(notebook)
        return notebook
    }

    // MARK: - Thumbnails

    func thumbnail(notebookID: UUID, pageIndex: Int, pixelWidth: CGFloat) -> UIImage? {
        guard let current = notebook(notebookID), current.pages.indices.contains(pageIndex) else { return nil }
        let page = current.pages[pageIndex]
        let url = drawingURL(notebookID, page.id)
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let stamp = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(page.id.uuidString)-\(Int(pixelWidth))-\(stamp)" as NSString

        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let drawing = loadDrawing(notebookID: notebookID, pageID: page.id)
        let image = PageRenderer.render(
            page: page,
            drawing: drawing,
            pdf: pdfDocument(for: current),
            pixelWidth: pixelWidth
        )
        thumbnailCache.setObject(image, forKey: key)
        return image
    }
}
