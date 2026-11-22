// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import SwiftUI
import PencilKit

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct NotebookEditorView: View {
    @ObservedObject private var store: NotebookStore
    @StateObject private var model: EditorModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPages = false
    @State private var exportItem: ExportItem?
    @State private var errorMessage: String?

    private let notebookID: UUID

    init(notebookID: UUID, store: NotebookStore) {
        self.notebookID = notebookID
        _store = ObservedObject(wrappedValue: store)
        _model = StateObject(wrappedValue: EditorModel(store: store, notebookID: notebookID))
    }

    var body: some View {
        Group {
            if let notebook = store.notebook(notebookID), notebook.pages.indices.contains(model.pageIndex) {
                let page = notebook.pages[model.pageIndex]
                VStack(spacing: 0) {
                    PageCanvasView(
                        page: page,
                        pdf: store.pdfDocument(for: notebook),
                        loadDrawing: { store.loadDrawing(notebookID: notebookID, pageID: page.id) },
                        model: model
                    )
                    .id(page.id)

                    ToolbarView(model: model)
                        .padding(.vertical, 8)
                }
                .navigationTitle(notebook.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar(pageCount: notebook.pages.count, notebook: notebook) }
            } else {
                ContentUnavailableView("Notebook not found", systemImage: "questionmark.folder")
            }
        }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        .sheet(isPresented: $showPages) {
            PageGridSheet(model: model, store: store, notebookID: notebookID)
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private func editorToolbar(pageCount: Int, notebook: Notebook) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { model.goTo(model.pageIndex - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.pageIndex == 0)
            .accessibilityLabel("Previous page")

            Button { showPages = true } label: {
                Text("\(model.pageIndex + 1) / \(pageCount)")
                    .monospacedDigit()
            }
            .accessibilityLabel("Show all pages")

            Button { model.goTo(model.pageIndex + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.pageIndex >= pageCount - 1)
            .accessibilityLabel("Next page")

            Menu {
                Section("Add page after this one") {
                    ForEach(PageBackground.choosable) { background in
                        Button {
                            model.addPage(background)
                        } label: {
                            Label(background.title, systemImage: background.symbol)
                        }
                    }
                }
                Button {
                    export(notebook)
                } label: {
                    Label("Export as PDF", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func export(_ notebook: Notebook) {
        model.flush()
        do {
            exportItem = ExportItem(url: try PDFExporter.export(notebook, store: store))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Overview of every page with thumbnails; tap to jump, long-press to duplicate or delete.
struct PageGridSheet: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: NotebookStore
    let notebookID: UUID
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let notebook = store.notebook(notebookID) {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(Array(notebook.pages.enumerated()), id: \.element.id) { index, _ in
                            Button {
                                model.goTo(index)
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    thumbnail(index)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(
                                                    Color.accentColor,
                                                    lineWidth: index == model.pageIndex ? 3 : 0
                                                )
                                        )
                                    Text("\(index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    model.duplicatePage(at: index)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                if notebook.pages.count > 1 {
                                    Button(role: .destructive) {
                                        model.deletePage(at: index)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ index: Int) -> some View {
        if let image = store.thumbnail(notebookID: notebookID, pageIndex: index, pixelWidth: 360) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 2, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Color(.secondarySystemBackground))
                .aspectRatio(3 / 4, contentMode: .fit)
        }
    }
}
