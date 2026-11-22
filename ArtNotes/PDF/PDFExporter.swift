// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import UIKit
import PDFKit
import PencilKit

/// Exports a notebook as a PDF. Paper styles and imported PDF pages stay vector; ink is rasterized.
enum PDFExporter {
    static func export(_ notebook: Notebook, store: NotebookStore) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(sanitizedFileName(notebook.title) + ".pdf")

        let pdf = store.pdfDocument(for: notebook)
        let firstSize = notebook.pages.first?.size ?? PageRenderer.defaultSize
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: firstSize))

        try renderer.writePDF(to: url) { context in
            for page in notebook.pages {
                let rect = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: rect, pageInfo: [:])
                PageRenderer.drawBackground(page: page, pdf: pdf, in: context.cgContext, size: page.size)
                let drawing = store.loadDrawing(notebookID: notebook.id, pageID: page.id)
                if !drawing.strokes.isEmpty {
                    PageRenderer.inkImage(drawing, size: page.size, scale: 3).draw(in: rect)
                }
            }
        }
        return url
    }

    static func sanitizedFileName(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = title.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Notebook" : cleaned
    }
}
