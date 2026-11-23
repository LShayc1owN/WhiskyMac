// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
struct MacOS26CardActionList: View {
    let card: CardViewState
    let keyBindings: KeyBindingsStore?
    let pinnedWorkspace: Bool
    let run: (CardMenuCommand) -> Void
    let transform: (TextTransform) -> Void
    let dismiss: () -> Void

    @State private var registration = UUID()
    @State private var showingTransforms = false
    @State private var selectedIndex = 0
    @Environment(\.cardPopoverKeyboard) private var keyboard

    private struct Row: Identifiable {
        let id: String
        let title: String
        let icon: String
        var shortcut: String? = nil
        var role: ButtonRole? = nil
        let perform: () -> Void
    }

    private var groups: [[Row]] {
        if showingTransforms {
            let back = Row(id: "back", title: localized("Paste as…"), icon: "chevron.left") {
                showingTransforms = false
            }
            return [
                [back],
                TextTransform.allCases.map { option in
                    Row(id: option.rawValue, title: option.label, icon: "textformat") { transform(option) }
                },
            ]
        }
        return CardMenuCommand.sections(for: card, pinnedWorkspace: pinnedWorkspace).map { group in
            group.map { command in
                Row(
                    id: command.rawValue, title: command.title(for: card), icon: command.symbol,
                    shortcut: command.keyAction.flatMap { keyBindings?.label(for: $0) },
                    role: command.isDestructive ? .destructive : nil
                ) {
                    if command == .pasteAs { showingTransforms = true } else { run(command) }
                }
            }
        }
    }

    var body: some View {
        let rows = groups
        let visible = rows.flatMap { $0 }
        let selectedID = visible.indices.contains(selectedIndex) ? visible[selectedIndex].id : nil
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !showingTransforms, card.variantIDs.count > 1 {
                        Text(localized("Pin, delete and stack actions apply to the newest format."))
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.bottom, 4)
                    }
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 { Divider().padding(.horizontal, 8) }
                        ForEach(rows[index]) { row in
                            Button(role: row.role, action: row.perform) {
                                HStack(spacing: 8) {
                                    Label(row.title, systemImage: row.icon).lineLimit(2)
                                    Spacer(minLength: 4)
                                    if let shortcut = row.shortcut {
                                        Text(shortcut).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(minHeight: 28)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(row.role == .destructive ? Color.red : Color.primary)
                            .background(row.id == selectedID ? Color.accentColor.opacity(0.16) : .clear, in: .capsule)
                            .onHover { inside in
                                if inside, let index = visible.firstIndex(where: { $0.id == row.id }) {
                                    selectedIndex = index
                                }
                            }
                            .id(row.id)
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: 300, height: min(480, CGFloat(visible.count) * 33 + 24))
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .onChange(of: showingTransforms) { _, _ in selectedIndex = 0 }
        .onAppear {
            keyboard?.install(registration) { code in
                let current = groups.flatMap { $0 }
                guard !current.isEmpty else { return false }
                switch code {
                case 125: selectedIndex = min(selectedIndex + 1, current.count - 1)
                case 126: selectedIndex = max(selectedIndex - 1, 0)
                case 36, 76:
                    if current.indices.contains(selectedIndex) { current[selectedIndex].perform() }
                case 53:
                    if showingTransforms { showingTransforms = false } else { dismiss() }
                default: return false
                }
                return true
            }
        }
        .onDisappear { keyboard?.remove(registration) }
    }
}

@available(macOS 26, *)
struct MacOS26CardPinEditor: View {
    @State var value: PinnedMetadata
    let save: (PinnedMetadata) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Pinned item details…")).font(.headline)
            TextField(localized("Note"), text: $value.note, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3)
            Toggle(localized("Always hide content"), isOn: $value.hidesContent).toggleStyle(.switch)
            Text(
                localized(
                    "The note stays visible. Copy and paste use the original; previews, editing, dragging and online link previews are blocked while hidden."
                )
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(localized("Color tags")).font(.subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading) {
                ForEach(PinTagColor.allCases) { tag in
                    Toggle(
                        isOn: Binding(
                            get: { value.tags.contains(tag) },
                            set: { enabled in
                                if enabled { value.tags.insert(tag) } else { value.tags.remove(tag) }
                            })
                    ) {
                        HStack(spacing: 5) {
                            Circle().fill(tag.color).frame(width: 8, height: 8)
                            Text(tag.label)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(localized("Save")) { save(value.normalized) }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 310)
    }
}
