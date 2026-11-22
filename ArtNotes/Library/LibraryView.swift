// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: NotebookStore

    @State private var path: [UUID] = []
    @State private var showImporter = false

    @State private var showRename = false
    @State private var renameTarget: UUID?
    @State private var newTitle = ""

    @State private var showDeleteConfirm = false
    @State private var deleteTarget: UUID?

    @State private var exportItem: ExportItem?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 24)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.notebooks.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("ArtNotes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("New notebook") {
                            ForEach(PageBackground.choosable) { background in
                                Button {
                                    let notebook = store.createNotebook(background: background)
                                    path.append(notebook.id)
                                } label: {
                                    Label(background.title, systemImage: background.symbol)
                                }
                            }
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import PDF…", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                NotebookEditorView(notebookID: id, store: store)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .alert("Rename notebook", isPresented: $showRename) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                if let id = renameTarget { store.rename(id, to: newTitle) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this notebook?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deleteTarget { store.delete(id) }
            }
        } message: {
            Text("This permanently removes the notebook and all of its drawings.")
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(
            "Something went wrong",
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

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(store.notebooks.sorted { $0.modified > $1.modified }) { notebook in
                    NavigationLink(value: notebook.id) {
                        NotebookCard(notebook: notebook)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renameTarget = notebook.id
                            newTitle = notebook.title
                            showRename = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button {
                            export(notebook)
                        } label: {
                            Label("Export as PDF", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            deleteTarget = notebook.id
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No notebooks yet", systemImage: "book.closed")
        } description: {
            Text("Create a notebook or import a PDF to annotate.")
        } actions: {
            HStack {
                Button("New notebook") {
                    let notebook = store.createNotebook(background: .blank)
                    path.append(notebook.id)
                }
                .buttonStyle(.borderedProminent)
                Button("Import PDF") { showImporter = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            var imported: [Notebook] = []
            for url in urls {
                do {
                    imported.append(try store.importPDF(from: url))
                } catch {
                    errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            if imported.count == 1, let notebook = imported.first {
                path.append(notebook.id)
            }
        }
    }

    private func export(_ notebook: Notebook) {
        do {
            exportItem = ExportItem(url: try PDFExporter.export(notebook, store: store))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NotebookCard: View {
    @EnvironmentObject private var store: NotebookStore
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if let image = store.thumbnail(notebookID: notebook.id, pageIndex: 0, pixelWidth: 480) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(uiColor: UIColor(hex: notebook.coverColorHex)))
                        .frame(width: 10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)

            Text(notebook.title)
                .font(.headline)
                .lineLimit(1)
            Text("\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s") · \(notebook.modified.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
