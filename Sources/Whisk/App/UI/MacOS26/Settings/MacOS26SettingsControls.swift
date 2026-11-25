// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26SettingLabel: View {
    @Environment(\.interfaceTypography) private var typography

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
                .font(typography.font(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: typography.room(24), height: typography.room(24))
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 7))
                .accessibilityHidden(true)
        }
    }
}

@available(macOS 26, *)
struct MacOS26MenuRow<Selection: Hashable, Options: View>: View {
    @Environment(\.interfaceTypography) private var typography
    let title: String
    @Binding var selection: Selection
    let display: (Selection) -> String
    @ViewBuilder let options: () -> Options

    init(
        _ title: String, selection: Binding<Selection>, display: @escaping (Selection) -> String,
        @ViewBuilder options: @escaping () -> Options
    ) {
        self.title = title
        _selection = selection
        self.display = display
        self.options = options
    }

    var body: some View {
        if typography.isStandard {
            HStack(spacing: 16) {
                Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                Spacer(minLength: 8)
                picker.labelsHidden().pickerStyle(.menu).fixedSize()
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    Text(title).fixedSize().accessibilityHidden(true)
                    Spacer(minLength: 0)
                    menuButton.fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                    menuButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection, content: options)
    }

    private var menuButton: some View {
        MenuButton(title: title, value: display(selection), options: picker.pickerStyle(.inline))
    }

    private struct MenuButton<MenuOptions: View>: View {
        @Environment(\.interfaceTypography) private var typography
        @State private var presenter = SettingsMenuPresenter()
        let title: String
        let value: String
        let options: MenuOptions

        var body: some View {
            Button {
                presenter.present(options, typography: typography)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: value)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(typography.font(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(typography.font(.body))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .background(MenuAnchor(presenter: presenter).allowsHitTesting(false).accessibilityHidden(true))
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }
    }

    private struct MenuAnchor: NSViewRepresentable {
        let presenter: SettingsMenuPresenter

        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ view: NSView, context: Context) {
            presenter.anchor = view
        }
    }
}

@available(macOS 26, *)
struct MacOS26SizeSettingEditor<Preview: View>: View {
    @Environment(\.interfaceTypography) private var typography

    let title: String
    let savedValue: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    var usesPercentage = false
    @Binding var draft: SizeSettingDraft
    let save: (Double) -> Void
    let previewOnScreen: () -> Void
    @ViewBuilder let preview: () -> Preview

    private var size: Binding<Double> {
        Binding(get: { draft.value(saved: savedValue) }, set: { draft.proposedValue = $0 })
    }

    private var value: Double { size.wrappedValue }

    private var sizeLayout: AnyLayout {
        typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    }
    private var hasChanges: Bool { draft.hasChanges(saved: savedValue) }

    private var valueLabel: String {
        if usesPercentage {
            return value.formatted(.percent.locale(AppLocalization.interfaceLocale).precision(.fractionLength(0)))
        }
        let points = Int(value.rounded())
        return localized("\(points) pt")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sizeLayout {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                if !typography.usesLargeLayout { Spacer(minLength: 8) }
                HStack(spacing: 10) {
                    Slider(value: size, in: range)
                        .accessibilityLabel(title)
                        .accessibilityValue(valueLabel)
                        .frame(minWidth: 100, maxWidth: 220)
                    if usesPercentage {
                        Text(valueLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 64, alignment: .trailing)
                            .accessibilityHidden(true)
                    } else {
                        let input = CardSizeInput()
                        HStack(spacing: 6) {
                            MacOS26NumericField(title: title, value: size, format: input.format, parse: input.parse)
                                .accessibilityIdentifier("card-size-input")
                            Text(localized("pt")).foregroundStyle(.secondary)
                        }
                        .fixedSize()
                    }
                }
            }
            if hasChanges {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { editActions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { editActions }
                }
            } else if value != defaultValue {
                restoreDefault
            }

            Divider()
            Text(localized("Preview"))
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
            preview()
            Button(localized("Preview on screen"), systemImage: "macwindow", action: previewOnScreen)
                .macOS26SettingsAction()
        }
    }

    @ViewBuilder
    private var editActions: some View {
        editButton(localized("Restore last saved size"), symbol: "arrow.uturn.backward") {
            draft.revert()
        }
        .buttonStyle(.bordered)
        editButton(localized("Save current setting"), symbol: "checkmark") {
            draft.save(using: save)
        }
        .buttonStyle(.borderedProminent)
        if value != defaultValue { restoreDefault }
    }

    private var restoreDefault: some View {
        editButton(localized("Restore default size"), symbol: "arrow.counterclockwise") {
            draft.proposedValue = defaultValue
        }
        .buttonStyle(.bordered)
    }

    private func editButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(verbatim: title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).imageScale(.small)
            }
            .labelStyle(.titleAndIcon)
            .padding(.vertical, typography.points(2))
        }
    }
}

@available(macOS 26, *)
struct MacOS26CardSizeSample: View {
    @Environment(\.interfaceTypography) private var typography

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
                        .font(typography.font(.callout).weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis")
                        .font(typography.font(.caption).weight(.semibold))
                        .foregroundStyle(secondary)
                        .frame(width: 25, height: 25)
                        .background(primary.opacity(0.07), in: .circle)
                        .glassEffect(reduceTransparency ? .identity : .regular, in: .circle)
                }
                Text(localized("Preview"))
                    .font(typography.font(.callout))
                Spacer(minLength: 8)
                HStack {
                    Text(localized("Clipboard cards"))
                    Spacer()
                    Image(systemName: "text.alignleft")
                }
                .font(typography.font(.caption2))
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
    @Environment(\.interfaceTypography) private var typography

    let scale: Double

    var body: some View {
        let metrics = MacOS26FilterTagMetrics(scale: scale, typography: typography)
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

    private func tag(_ name: String, symbol: String, metrics: MacOS26FilterTagMetrics, active: Bool = false)
        -> some View
    {
        Label(name, systemImage: symbol)
            .font(typography.font(size: metrics.fontSize))
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(height: metrics.rowHeight)
            .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07), in: Capsule())
    }
}

@available(macOS 26, *)
struct MacOS26NumericField<Value: Equatable>: View {
    @Environment(\.interfaceTypography) private var typography
    let title: String
    @Binding var value: Value
    let format: (Value) -> String
    let parse: (String) -> Value?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.plain)
            .font(typography.font(.body).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: typography.room(64))
            .background(.background, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? Color.accentColor : .secondary.opacity(0.35))
            )
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
        if draft != format(value), let parsed = parse(draft) { value = parsed }
        draft = format(value)
    }
}

@available(macOS 26, *)
struct MacOS26VimKeyField: View {
    @Environment(\.interfaceTypography) private var typography

    let action: VimAction
    @ObservedObject var store: VimBindingsStore
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(action.displayName, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(typography.font(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: max(48, typography.points(24)))
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
        Text(isRecording ? localized("Type shortcut…") : store.label(for: action))
            .monospaced()
            .frame(minWidth: 74)
            .beButton { isRecording ? store.endRecording() : store.beginRecording(action) }
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

@available(macOS 26, *)
extension View {
    /// AppKit's bordered button is single-line. Use the wrapping action style when the title needs more room.
    func macOS26SettingsAction(prominent: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            if prominent {
                self.buttonStyle(.borderedProminent).fixedSize()
            } else {
                self.buttonStyle(.bordered).fixedSize()
            }
            self.buttonStyle(MacOS26DialogActionStyle(prominent: prominent))
        }
    }
}
