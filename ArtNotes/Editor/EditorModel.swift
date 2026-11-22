// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import SwiftUI
import PencilKit

enum ToolKind: String, CaseIterable, Identifiable {
    case pen, fountain, pencil, marker, watercolor, crayon, eraser, lasso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .fountain: return "Fountain pen"
        case .pencil: return "Pencil"
        case .marker: return "Marker"
        case .watercolor: return "Watercolor"
        case .crayon: return "Crayon"
        case .eraser: return "Eraser"
        case .lasso: return "Lasso"
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .fountain: return "pencil.tip.crop.circle"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .watercolor: return "paintbrush.pointed"
        case .crayon: return "scribble.variable"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        }
    }

    var inkType: PKInkingTool.InkType? {
        switch self {
        case .pen: return .pen
        case .fountain: return .fountainPen
        case .pencil: return .pencil
        case .marker: return .marker
        case .watercolor: return .watercolor
        case .crayon: return .crayon
        case .eraser, .lasso: return nil
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pen: return 4
        case .fountain: return 6
        case .pencil: return 4
        case .marker: return 20
        case .watercolor: return 14
        case .crayon: return 12
        case .eraser: return 16
        case .lasso: return 1
        }
    }
}

enum EraserMode: String, CaseIterable, Identifiable {
    case vector, bitmap

    var id: String { rawValue }
    var title: String { self == .vector ? "Stroke" : "Pixel" }
}

/// State for one open notebook: current page, active tool, undo state and debounced autosave.
final class EditorModel: ObservableObject {
    let store: NotebookStore
    let notebookID: UUID

    @Published var pageIndex = 0
    @Published var tool: ToolKind = .pen
    @Published var colorHex = "#1C1C1E"
    @Published var widths: [ToolKind: CGFloat] = Dictionary(
        uniqueKeysWithValues: ToolKind.allCases.map { ($0, $0.defaultWidth) }
    )
    @Published var eraserMode: EraserMode = .vector
    /// When false, only Apple Pencil draws and fingers are free for navigation.
    @Published var fingerDrawing = true
    @Published var rulerActive = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    weak var canvas: PKCanvasView?

    private var previousTool: ToolKind = .pen
    private var pendingDrawing: PKDrawing?
    private var pendingPageID: UUID?
    private var saveWork: DispatchWorkItem?

    init(store: NotebookStore, notebookID: UUID) {
        self.store = store
        self.notebookID = notebookID
    }

    // MARK: - Tools

    var uiColor: UIColor { UIColor(hex: colorHex) }

    var width: CGFloat {
        get { widths[tool] ?? tool.defaultWidth }
        set { widths[tool] = newValue }
    }

    var pkTool: PKTool {
        switch tool {
        case .eraser:
            let type: PKEraserTool.EraserType = eraserMode == .vector ? .vector : .bitmap
            return PKEraserTool(type)
        case .lasso:
            return PKLassoTool()
        default:
            return PKInkingTool(tool.inkType ?? .pen, color: uiColor, width: width)
        }
    }

    /// Apple Pencil double-tap: flip between the eraser and the previous tool.
    func togglePencilEraser() {
        if tool == .eraser {
            tool = previousTool
        } else {
            previousTool = tool
            tool = .eraser
        }
    }

    func select(_ newTool: ToolKind) {
        if newTool != .eraser { previousTool = newTool }
        tool = newTool
    }

    // MARK: - Undo / redo

    func undo() {
        canvas?.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        canvas?.undoManager?.redo()
        refreshUndoState()
    }

    func refreshUndoState() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.canUndo = self.canvas?.undoManager?.canUndo ?? false
            self.canRedo = self.canvas?.undoManager?.canRedo ?? false
        }
    }

    // MARK: - Pages

    var pageCount: Int { store.notebook(notebookID)?.pages.count ?? 0 }

    func goTo(_ index: Int) {
        flush()
        guard store.notebook(notebookID)?.pages.indices.contains(index) == true else { return }
        pageIndex = index
        canUndo = false
        canRedo = false
    }

    func addPage(_ background: PageBackground) {
        flush()
        if store.addPage(to: notebookID, after: pageIndex, background: background) != nil {
            pageIndex += 1
            canUndo = false
            canRedo = false
        }
    }

    func duplicatePage(at index: Int) {
        flush()
        store.duplicatePage(in: notebookID, at: index)
    }

    func deletePage(at index: Int) {
        flush()
        guard pageCount > 1 else { return }
        store.deletePage(in: notebookID, at: index)
        if index < pageIndex {
            pageIndex -= 1
        }
        pageIndex = min(pageIndex, max(pageCount - 1, 0))
    }

    // MARK: - Saving

    func drawingChanged(_ drawing: PKDrawing, pageID: UUID) {
        pendingDrawing = drawing
        pendingPageID = pageID
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        guard let drawing = pendingDrawing, let pageID = pendingPageID else { return }
        store.saveDrawing(drawing, notebookID: notebookID, pageID: pageID)
        pendingDrawing = nil
        pendingPageID = nil
    }

    func close() {
        flush()
        store.touch(notebookID)
    }
}
