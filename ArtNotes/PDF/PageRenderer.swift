// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import UIKit
import PDFKit
import PencilKit

/// Draws page backgrounds (paper styles and imported PDF pages) and composites ink on top.
enum PageRenderer {
    static let defaultSize = CGSize(width: 768, height: 1024)

    private static let paperColor = UIColor(red: 0.995, green: 0.99, blue: 0.975, alpha: 1)
    private static let lineColor = UIColor(red: 0.55, green: 0.66, blue: 0.82, alpha: 0.55)
    private static let dotColor = UIColor(red: 0.45, green: 0.50, blue: 0.58, alpha: 0.6)
    private static let spacing: CGFloat = 32

    /// The on-screen size of a PDF page, taking its rotation into account.
    static func size(of page: PDFPage) -> CGSize {
        let rect = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        return rotated ? CGSize(width: rect.height, height: rect.width) : rect.size
    }

    /// Draws the page background into a UIKit-oriented context (origin top-left).
    static func drawBackground(page: NotebookPage, pdf: PDFDocument?, in cg: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        cg.setFillColor(paperColor.cgColor)
        cg.fill(rect)

        switch page.background {
        case .blank:
            break

        case .ruled:
            cg.setStrokeColor(lineColor.cgColor)
            cg.setLineWidth(1)
            var y = spacing * 3
            while y < size.height - spacing {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            cg.strokePath()

        case .grid:
            cg.setStrokeColor(lineColor.cgColor)
            cg.setLineWidth(0.75)
            var x = spacing
            while x < size.width {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y = spacing
            while y < size.height {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            cg.strokePath()

        case .dotted:
            cg.setFillColor(dotColor.cgColor)
            var y = spacing
            while y < size.height {
                var x = spacing
                while x < size.width {
                    cg.fillEllipse(in: CGRect(x: x - 1.25, y: y - 1.25, width: 2.5, height: 2.5))
                    x += spacing
                }
                y += spacing
            }

        case .pdf:
            guard let index = page.pdfPageIndex,
                  let pdfPage = pdf?.page(at: index),
                  let ref = pdfPage.pageRef else { break }
            cg.saveGState()
            // Switch from UIKit's top-left origin to PDF's bottom-left origin.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            let transform = ref.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true)
            cg.concatenate(transform)
            cg.drawPDFPage(ref)
            cg.restoreGState()
        }
    }

    /// A raster of the background only, used behind the live canvas.
    static func backgroundImage(page: NotebookPage, pdf: PDFDocument?, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: page.size, format: format)
        return renderer.image { ctx in
            drawBackground(page: page, pdf: pdf, in: ctx.cgContext, size: page.size)
        }
    }

    /// Ink rendered with the light appearance so black ink never flips to white in dark mode.
    static func inkImage(_ drawing: PKDrawing, size: CGSize, scale: CGFloat) -> UIImage {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
        }
        return image
    }

    /// Background plus ink as a single image `pixelWidth` pixels wide (thumbnails, previews).
    static func render(page: NotebookPage, drawing: PKDrawing?, pdf: PDFDocument?, pixelWidth: CGFloat) -> UIImage {
        let factor = pixelWidth / page.size.width
        let pixelSize = CGSize(width: pixelWidth, height: (page.size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.scaleBy(x: factor, y: factor)
            drawBackground(page: page, pdf: pdf, in: cg, size: page.size)
            if let drawing, !drawing.strokes.isEmpty {
                inkImage(drawing, size: page.size, scale: factor)
                    .draw(in: CGRect(origin: .zero, size: page.size))
            }
        }
    }
}
