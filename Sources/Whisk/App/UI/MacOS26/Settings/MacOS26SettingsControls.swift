// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26SettingLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    init(_ title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 7))
                .accessibilityHidden(true)
        }
    }
}

@available(macOS 26, *)
struct MacOS26MenuRow<Value: Hashable, Label: View, Options: View>: View {
    @Binding var selection: Value
    @ViewBuilder let options: () -> Options
    @ViewBuilder let label: () -> Label

    init(
        selection: Binding<Value>, @ViewBuilder options: @escaping () -> Options,
        @ViewBuilder label: @escaping () -> Label
    ) {
        _selection = selection
        self.options = options
        self.label = label
    }

    init(_ title: String, selection: Binding<Value>, @ViewBuilder options: @escaping () -> Options)
    where Label == Text {
        self.init(selection: selection, options: options) { Text(title) }
    }

    var body: some View {
        HStack(spacing: 16) {
            label().fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Picker(selection: $selection, content: options, label: label)
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }
}

@available(macOS 26, *)
struct MacOS26SizeSettingEditor<Preview: View>: View {
    let title: String
    let symbol: String
    let savedValue: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    var usesPercentage = false
    @Binding var draft: SizeSettingDraft
    let save: (Double) -> Void
    let previewOnScreen: () -> Void
    @ViewBuilder let preview: () -> Preview

    private var value: Double { draft.value(saved: savedValue) }
    private var hasChanges: Bool { draft.hasChanges(saved: savedValue) }

    private var valueLabel: String {
        if usesPercentage { return value.formatted(.percent.precision(.fractionLength(0))) }
        let points = Int(value.rounded())
        return localized("\(points) pt")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MacOS26SettingLabel(title, symbol: symbol, tint: .indigo)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Slider(value: Binding(get: { value }, set: { draft.proposedValue = $0 }), in: range)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueLabel)
                    .frame(minWidth: 100, maxWidth: 220)
                Text(valueLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            if hasChanges {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { editActions }
                    VStack(alignment: .leading, spacing: 10) { editActions }
                }
            } else if value != defaultValue {
                restoreDefault
            }

            Divider()
            Text(localized("Preview"))
                .font(.caption)
                .foregroundStyle(.secondary)
            preview()
            Button(localized("Preview on screen"), systemImage: "macwindow", action: previewOnScreen)
        }
    }

    @ViewBuilder
    private var editActions: some View {
        Button(localized("Restore last saved size")) { draft.revert() }
        Button(localized("Save current setting")) { draft.save(using: save) }
            .buttonStyle(.borderedProminent)
        if value != defaultValue { restoreDefault }
    }

    private var restoreDefault: some View {
        Button(localized("Restore default size")) { draft.proposedValue = defaultValue }
    }
}

@available(macOS 26, *)
struct MacOS26CardSizeSample: View {
    let side: CGFloat
    @Environment(\.colorScheme) private var clipboardScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var usesDarkPalette: Bool { clipboardScheme == .dark }
    private var primary: Color { Color(white: usesDarkPalette ? 0.94 : 0.10) }
    private var secondary: Color { Color(white: usesDarkPalette ? 0.72 : 0.36) }

    var body: some View {
        let points = Int(side.rounded())
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Label(AppIdentity.displayName, systemImage: "doc.on.clipboard")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondary)
                        .frame(width: 25, height: 25)
                        .background(primary.opacity(0.07), in: .circle)
                        .glassEffect(reduceTransparency ? .identity : .regular, in: .circle)
                }
                Text(localized("Preview"))
                    .font(.callout)
                Spacer(minLength: 8)
                HStack {
                    Text(localized("Clipboard cards"))
                    Spacer()
                    Image(systemName: "text.alignleft")
                }
                .font(.caption2)
                .foregroundStyle(secondary)
            }
            .foregroundStyle(primary)
            .padding(12)
            .frame(width: side, height: side, alignment: .topLeading)
            .background(MacOS26CardSurface.fill(in: clipboardScheme), in: MacOS26CardSurface.outline)
            .overlay { MacOS26CardSurface.outline.strokeBorder(MacOS26CardSurface.border(in: contrast)) }
            .padding(8)
        }
        .defaultScrollAnchor(.leading)
        .frame(height: side + 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Card size"))
        .accessibilityValue(localized("\(points) pt"))
    }
}

@available(macOS 26, *)
struct MacOS26FilterTagSizeSample: View {
    let scale: Double

    var body: some View {
        let metrics = FilterTagMetrics(scale: scale)
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                tag(localized("All"), symbol: "square.grid.2x2", metrics: metrics, active: true)
                tag(localized("Text"), symbol: "text.alignleft", metrics: metrics)
                tag(localized("Image"), symbol: "photo", metrics: metrics)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, metrics.rowVerticalPadding)
        }
        .frame(height: metrics.totalRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Tag size"))
        .accessibilityValue(scale.formatted(.percent.precision(.fractionLength(0))))
    }

    private func tag(_ name: String, symbol: String, metrics: FilterTagMetrics, active: Bool = false) -> some View {
        Label(name, systemImage: symbol)
            .font(.system(size: metrics.fontSize))
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(height: metrics.rowHeight)
            .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07), in: Capsule())
    }
}

@available(macOS 26, *)
struct MacOS26NumericField<Value: Equatable>: View {
    let title: String
    @Binding var value: Value
    let format: (Value) -> String
    let parse: (String) -> Value?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            .accessibilityLabel(title)
            .focused($focused)
            .onAppear { draft = format(value) }
            .onSubmit { commit() }
            .onChange(of: focused) { _, active in
                if !active { commit() }
            }
            .onChange(of: value) { _, value in draft = format(value) }
    }

    private func commit() {
        if let parsed = parse(draft) { value = parsed }
        draft = format(value)
    }
}

@available(macOS 26, *)
struct MacOS26VimKeyField: View {
    let action: VimAction
    @ObservedObject var store: VimBindingsStore
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(action.displayName, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 48)
            .focused($focused)
            .onAppear { text = store.key(for: action) }
            .onSubmit { commit() }
            .onChange(of: focused) { _, active in
                if !active { commit() }
            }
            .onChange(of: store.keys) { _, _ in
                if !focused { text = store.key(for: action) }
            }
    }

    private func commit() {
        store.set(text, for: action)
        text = store.key(for: action)
    }
}

@available(macOS 26, *)
struct MacOS26ShortcutRecorder: View {
    let action: KeyAction
    @ObservedObject var store: KeyBindingsStore

    private var isRecording: Bool { store.recordingAction == action }

    var body: some View {
        Button {
            isRecording ? store.endRecording() : store.beginRecording(action)
        } label: {
            Text(isRecording ? localized("Type shortcut…") : store.label(for: action))
                .monospaced()
                .frame(minWidth: 74)
        }
        .buttonStyle(.bordered)
        .background {
            if isRecording { Capsule().strokeBorder(.tint, lineWidth: 2) }
        }
        .accessibilityLabel(action.displayName)
        .accessibilityValue(isRecording ? localized("Type shortcut…") : store.label(for: action))
        .onDisappear {
            if isRecording { store.endRecording() }
        }
    }
}
