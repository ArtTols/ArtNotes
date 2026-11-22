// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import Foundation
import CoreGraphics
import UIKit

enum PageBackground: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, grid, dotted, pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Blank"
        case .ruled: return "Ruled"
        case .grid: return "Grid"
        case .dotted: return "Dotted"
        case .pdf: return "PDF"
        }
    }

    var symbol: String {
        switch self {
        case .blank: return "doc"
        case .ruled: return "text.alignleft"
        case .grid: return "square.grid.3x3"
        case .dotted: return "circle.grid.3x3"
        case .pdf: return "doc.richtext"
        }
    }

    /// Backgrounds a person can pick when creating a notebook or adding a page.
    static let choosable: [PageBackground] = [.blank, .ruled, .grid, .dotted]
}

struct NotebookPage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var background: PageBackground
    /// Page size in points.
    var size: CGSize
    /// Index into the notebook's source PDF, for `.pdf` pages.
    var pdfPageIndex: Int?
}

struct Notebook: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var coverColorHex: String
    var created: Date = Date()
    var modified: Date = Date()
    var pages: [NotebookPage]
    /// File name of the imported PDF inside the notebook folder, if any.
    var sourcePDFName: String?

    static let coverColors = [
        "#5856D6", "#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#8E5A3C", "#30B0C7"
    ]
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
