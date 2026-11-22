// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import XCTest
import PDFKit
import PencilKit
@testable import ArtNotes

final class NotebookStoreTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtNotesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeStore() -> NotebookStore {
        NotebookStore(root: tmp.appendingPathComponent("Notebooks", isDirectory: true))
    }

    private func makePDF(pages: Int) throws -> URL {
        let url = tmp.appendingPathComponent("sample.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            for index in 0..<pages {
                context.beginPage()
                ("Page \(index + 1)" as NSString).draw(
                    at: CGPoint(x: 72, y: 72),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 24)]
                )
            }
        }
        return url
    }

    private func sampleDrawing() -> PKDrawing {
        let points = [
            PKStrokePoint(location: CGPoint(x: 10, y: 10), timeOffset: 0, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 80, y: 60), timeOffset: 0.1, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }

    func testCreateAndReload() {
        let store = makeStore()
        let notebook = store.createNotebook(title: "Sketches", background: .ruled)
        XCTAssertEqual(store.notebooks.count, 1)
        XCTAssertEqual(notebook.pages.count, 1)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.notebooks.count, 1)
        XCTAssertEqual(reloaded.notebooks.first?.title, "Sketches")
        XCTAssertEqual(reloaded.notebooks.first?.pages.first?.background, .ruled)
    }

    func testDrawingRoundTrip() {
        let store = makeStore()
        let notebook = store.createNotebook(background: .blank)
        let page = notebook.pages[0]

        store.saveDrawing(sampleDrawing(), notebookID: notebook.id, pageID: page.id)
        let loaded = store.loadDrawing(notebookID: notebook.id, pageID: page.id)
        XCTAssertEqual(loaded.strokes.count, 1)
    }

    func testAddDuplicateAndDeletePages() {
        let store = makeStore()
        let notebook = store.createNotebook(background: .blank)

        store.addPage(to: notebook.id, after: 0, background: .grid)
        XCTAssertEqual(store.notebook(notebook.id)?.pages.count, 2)
        XCTAssertEqual(store.notebook(notebook.id)?.pages[1].background, .grid)

        store.duplicatePage(in: notebook.id, at: 1)
        XCTAssertEqual(store.notebook(notebook.id)?.pages.count, 3)

        store.deletePage(in: notebook.id, at: 2)
        store.deletePage(in: notebook.id, at: 1)
        // The last remaining page can't be deleted.
        store.deletePage(in: notebook.id, at: 0)
        XCTAssertEqual(store.notebook(notebook.id)?.pages.count, 1)
    }

    func testImportPDFCreatesOnePagePerPDFPage() throws {
        let store = makeStore()
        let notebook = try store.importPDF(from: makePDF(pages: 3))

        XCTAssertEqual(notebook.pages.count, 3)
        XCTAssertTrue(notebook.pages.allSatisfy { $0.background == .pdf })
        XCTAssertEqual(notebook.pages.map(\.pdfPageIndex), [0, 1, 2])
        XCTAssertEqual(notebook.pages[0].size.width, 612, accuracy: 0.5)
        XCTAssertNotNil(store.pdfDocument(for: notebook))
    }

    func testImportRejectsNonPDF() throws {
        let store = makeStore()
        let bogus = tmp.appendingPathComponent("bogus.pdf")
        try Data("not a pdf".utf8).write(to: bogus)
        XCTAssertThrowsError(try store.importPDF(from: bogus))
        XCTAssertTrue(store.notebooks.isEmpty)
    }

    func testExportProducesPDFWithAllPages() throws {
        let store = makeStore()
        let notebook = try store.importPDF(from: makePDF(pages: 2))
        store.saveDrawing(sampleDrawing(), notebookID: notebook.id, pageID: notebook.pages[0].id)

        let url = try PDFExporter.export(notebook, store: store)
        let exported = PDFDocument(url: url)
        XCTAssertEqual(exported?.pageCount, 2)
    }

    func testDeleteRemovesFiles() {
        let store = makeStore()
        let notebook = store.createNotebook(background: .dotted)
        store.delete(notebook.id)
        XCTAssertTrue(store.notebooks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: notebook.id).path))
    }

    func testFileNameSanitizing() {
        XCTAssertEqual(PDFExporter.sanitizedFileName("a/b:c"), "a-b-c")
        XCTAssertEqual(PDFExporter.sanitizedFileName("  "), "Notebook")
    }
}
