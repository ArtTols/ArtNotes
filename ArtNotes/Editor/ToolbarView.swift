// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ArtNotes contributors

import SwiftUI

struct ToolbarView: View {
    @ObservedObject var model: EditorModel

    private let palette = [
        "#1C1C1E", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#007AFF", "#5856D6", "#8E5A3C"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                undoRedo
                divider
                tools
                divider
                if model.tool.inkType != nil {
                    colors
                    divider
                }
                if model.tool == .eraser {
                    Picker("Eraser", selection: $model.eraserMode) {
                        ForEach(EraserMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                if model.tool != .lasso {
                    widthSlider
                }
                divider
                options
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .padding(.horizontal, 12)
    }

    private var divider: some View {
        Divider().frame(height: 26)
    }

    private var undoRedo: some View {
        HStack(spacing: 6) {
            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 34, height: 34)
            }
            .disabled(!model.canUndo)
            .accessibilityLabel("Undo")

            Button { model.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 34, height: 34)
            }
            .disabled(!model.canRedo)
            .accessibilityLabel("Redo")
        }
    }

    private var tools: some View {
        HStack(spacing: 4) {
            ForEach(ToolKind.allCases) { tool in
                Button { model.select(tool) } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 18))
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(model.tool == tool ? Color.accentColor.opacity(0.18) : .clear)
                        )
                        .foregroundStyle(model.tool == tool ? Color.accentColor : Color.primary)
                }
                .accessibilityLabel(tool.title)
            }
        }
    }

    private var colors: some View {
        HStack(spacing: 8) {
            ForEach(palette, id: \.self) { hex in
                Circle()
                    .fill(Color(uiColor: UIColor(hex: hex)))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                            .padding(-4)
                            .opacity(model.colorHex == hex ? 1 : 0)
                    )
                    .onTapGesture { model.colorHex = hex }
                    .accessibilityLabel("Color \(hex)")
            }
            ColorPicker(
                "Custom color",
                selection: Binding(
                    get: { Color(uiColor: model.uiColor) },
                    set: { model.colorHex = UIColor($0).hexString }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    private var widthSlider: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.tool == .eraser ? Color.secondary : Color(uiColor: model.uiColor))
                .frame(width: max(4, min(model.width, 28)), height: max(4, min(model.width, 28)))
                .frame(width: 30, height: 30)
            Slider(
                value: Binding(
                    get: { Double(model.width) },
                    set: { model.width = CGFloat($0) }
                ),
                in: 1...40
            )
            .frame(width: 130)
        }
    }

    private var options: some View {
        HStack(spacing: 6) {
            Button { model.rulerActive.toggle() } label: {
                Image(systemName: "ruler")
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(model.rulerActive ? Color.accentColor.opacity(0.18) : .clear)
                    )
            }
            .accessibilityLabel("Ruler")

            Button { model.fingerDrawing.toggle() } label: {
                Image(systemName: model.fingerDrawing ? "hand.draw" : "applepencil")
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(model.fingerDrawing ? "Finger drawing on" : "Pencil only")
        }
    }
}
