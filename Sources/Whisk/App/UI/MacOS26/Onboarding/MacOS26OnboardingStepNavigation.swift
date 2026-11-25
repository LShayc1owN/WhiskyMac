// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26OnboardingStepNavigation: View {
    let current: OnboardingPage
    let permissionsComplete: Bool
    let allowsArrowNavigation: Bool
    var horizontal = false
    var select: (OnboardingPage) -> Void
    @Environment(\.interfaceTypography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedStep: OnboardingPage?
    @State private var visiblePages: Set<OnboardingPage> = []

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(horizontal ? .horizontal : .vertical) {
                if horizontal {
                    HStack(spacing: 8) {
                        ForEach(OnboardingPage.steps) { page in
                            stepButton(page).fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(OnboardingPage.steps) { page in
                            VStack(alignment: .leading, spacing: 6) {
                                stepButton(page)
                                if page != OnboardingPage.steps.last {
                                    Capsule()
                                        .fill(
                                            MacOS26OnboardingStyle.green.opacity(
                                                page.stepNumber < current.stepNumber ? 0.65 : 0.14)
                                        )
                                        .frame(width: 3, height: 10)
                                        .padding(.leading, 17.5)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .scrollIndicators(horizontal ? .visible : .hidden)
            .animation(reduceMotion ? nil : MacOS26OnboardingMotion.detail, value: current)
            .onAppear { reader.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, page in
                guard !visiblePages.contains(page) else { return }
                withAnimation(reduceMotion ? nil : MacOS26OnboardingMotion.detail) {
                    reader.scrollTo(page, anchor: .center)
                }
            }
        }
    }

    private func stepButton(_ page: OnboardingPage) -> some View {
        HStack(spacing: 8) {
            Text(String(page.stepNumber))
                .font(typography.font(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    current == page
                        ? .white
                        : MacOS26OnboardingStyle.green.opacity(
                            page.stepNumber < current.stepNumber ? 1 : 0.55)
                )
                .frame(width: max(26, typography.room(16)), height: max(26, typography.room(16)))
                .background(circleColor(page), in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        MacOS26OnboardingStyle.green.opacity(current == page ? 0 : 0.12))
                )
                .overlay(alignment: .bottomTrailing) {
                    if isComplete(page) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(typography.font(size: 11, weight: .medium))
                            .foregroundStyle(MacOS26OnboardingStyle.green)
                            .padding(1)
                            .background(MacOS26OnboardingStyle.paper, in: Circle())
                            .offset(x: typography.points(5), y: typography.points(3))
                            .accessibilityHidden(true)
                    }
                }
            Text(page.label)
                .font(typography.font(size: 13, weight: current == page ? .semibold : .regular))
                .foregroundStyle(current == page ? .primary : .secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 3)
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .beButton { select(page) }
        .buttonStyle(.plain)
        .focused($focusedStep, equals: page)
        .onKeyPress(.leftArrow) { moveFocus(from: page, by: -1) }
        .onKeyPress(.rightArrow) { moveFocus(from: page, by: 1) }
        .onScrollVisibilityChange(threshold: 0.98) { visible in
            if visible { visiblePages.insert(page) } else { visiblePages.remove(page) }
        }
        .accessibilityLabel(
            String(
                format: localized("Step %lld of %lld: %@"),
                Int64(page.stepNumber), Int64(OnboardingPage.steps.count), page.label)
        )
        .accessibilityValue(isComplete(page) ? localized("Completed") : "")
        .accessibilityAddTraits(current == page ? .isSelected : [])
        .accessibilityIdentifier("onboarding.page.\(page.rawValue)")
        .id(page)
    }

    private func moveFocus(from page: OnboardingPage, by offset: Int) -> KeyPress.Result {
        guard allowsArrowNavigation,
            let destination = page.advanced(by: offset),
            destination != .welcome
        else { return .ignored }
        focusedStep = destination
        select(destination)
        return .handled
    }

    private func isComplete(_ page: OnboardingPage) -> Bool {
        switch page {
        case .permissions: permissionsComplete
        default: false
        }
    }

    private func circleColor(_ page: OnboardingPage) -> Color {
        if page == current { return Color(red: 0.19, green: 0.43, blue: 0.36) }
        return MacOS26OnboardingStyle.green.opacity(isComplete(page) ? 0.18 : 0.065)
    }
}
