// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import SwiftUI

@main
struct ArtNotesApp: App {
    @StateObject private var store = NotebookStore()
    @State private var importError: String?

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                // "Open in ArtNotes" from Files or a share sheet imports the PDF.
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "pdf" else { return }
                    do {
                        try store.importPDF(from: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
                .alert(
                    "Couldn't import PDF",
                    isPresented: Binding(
                        get: { importError != nil },
                        set: { if !$0 { importError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(importError ?? "")
                }
        }
    }
}
