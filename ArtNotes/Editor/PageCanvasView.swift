// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import SwiftUI
import PencilKit
import PDFKit

/// Scroll/zoom container that hosts a page background and a PencilKit canvas.
///
/// Gestures:
/// - one finger or Apple Pencil: draw
/// - two fingers: pan and pinch-zoom
/// - two-finger tap: undo
/// - three-finger tap: redo
/// - Apple Pencil double-tap: toggle eraser
final class PageScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    let pageSize: CGSize
    let content = UIView()
    let backgroundView = UIImageView()
    let canvas = PKCanvasView()

    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onPencilDoubleTap: (() -> Void)?

    private var lastBoundsSize: CGSize = .zero
    private var isFitted = true

    init(pageSize: CGSize) {
        self.pageSize = pageSize
        super.init(frame: .zero)

        delegate = self
        backgroundColor = .systemGray5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        delaysContentTouches = false
        // One finger belongs to the canvas; scrolling needs two.
        panGestureRecognizer.minimumNumberOfTouches = 2

        content.frame = CGRect(origin: .zero, size: pageSize)
        addSubview(content)
        contentSize = pageSize

        backgroundView.frame = content.bounds
        backgroundView.contentMode = .scaleToFill
        content.addSubview(backgroundView)

        canvas.frame = content.bounds
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        content.addSubview(canvas)

        let undoTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap))
        undoTap.numberOfTouchesRequired = 2
        undoTap.cancelsTouchesInView = false
        undoTap.delegate = self
        addGestureRecognizer(undoTap)

        let redoTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap))
        redoTap.numberOfTouchesRequired = 3
        redoTap.cancelsTouchesInView = false
        redoTap.delegate = self
        addGestureRecognizer(redoTap)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layout & zoom

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            let margin: CGFloat = 24
            let fit = min(
                max(bounds.width - margin, 1) / pageSize.width,
                max(bounds.height - margin, 1) / pageSize.height
            )
            minimumZoomScale = fit
            maximumZoomScale = fit * 8
            if isFitted {
                zoomScale = fit
            }
        }
        centerContent()
    }

    private func centerContent() {
        var frame = content.frame
        frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
        content.frame = frame
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        isFitted = abs(zoomScale - minimumZoomScale) < 0.01
        setNeedsLayout()
    }

    // MARK: Gestures

    @objc private func handleUndoTap() { onUndo?() }
    @objc private func handleRedoTap() { onRedo?() }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onPencilDoubleTap?()
    }
}

struct PageCanvasView: UIViewRepresentable {
    let page: NotebookPage
    let pdf: PDFDocument?
    /// Called once when the view is created, so the drawing isn't re-read on every SwiftUI update.
    let loadDrawing: () -> PKDrawing
    @ObservedObject var model: EditorModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, pageID: page.id)
    }

    func makeUIView(context: Context) -> PageScrollView {
        let view = PageScrollView(pageSize: page.size)
        view.backgroundView.image = PageRenderer.backgroundImage(page: page, pdf: pdf, scale: 3)

        // Set the drawing before the delegate so loading doesn't trigger an autosave.
        view.canvas.drawing = loadDrawing()
        view.canvas.delegate = context.coordinator

        view.onUndo = { [weak model] in model?.undo() }
        view.onRedo = { [weak model] in model?.redo() }
        view.onPencilDoubleTap = { [weak model] in model?.togglePencilEraser() }

        model.canvas = view.canvas
        view.canvas.tool = model.pkTool
        view.canvas.drawingPolicy = model.fingerDrawing ? .anyInput : .pencilOnly
        return view
    }

    func updateUIView(_ view: PageScrollView, context: Context) {
        view.canvas.tool = model.pkTool
        view.canvas.drawingPolicy = model.fingerDrawing ? .anyInput : .pencilOnly
        view.canvas.isRulerActive = model.rulerActive
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let model: EditorModel
        let pageID: UUID

        init(model: EditorModel, pageID: UUID) {
            self.model = model
            self.pageID = pageID
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            model.drawingChanged(canvasView.drawing, pageID: pageID)
            model.refreshUndoState()
        }
    }
}
