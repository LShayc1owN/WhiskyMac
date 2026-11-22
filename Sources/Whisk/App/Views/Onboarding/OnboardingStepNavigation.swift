// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct OnboardingStepNavigation: View {
    let current: OnboardingPage
    var select: (OnboardingPage) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visiblePages: Set<OnboardingPage> = []

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(OnboardingPage.steps) { page in
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                select(page)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(String(page.rawValue))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(
                                            current == page
                                                ? .white
                                                : OnboardingStyle.green.opacity(
                                                    page.rawValue < current.rawValue ? 1 : 0.55)
                                        )
                                        .frame(width: 26, height: 26)
                                        .background(circleColor(page), in: Circle())
                                        .overlay(
                                            Circle().strokeBorder(
                                                OnboardingStyle.green.opacity(current == page ? 0 : 0.12)))
                                    Text(page.label)
                                        .font(.system(size: 12, weight: current == page ? .semibold : .regular))
                                        .foregroundStyle(current == page ? .primary : .secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 30)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(OnboardingButtonStyle(treatment: .quiet))
                            .onScrollVisibilityChange(threshold: 0.98) { visible in
                                if visible { visiblePages.insert(page) } else { visiblePages.remove(page) }
                            }
                            .accessibilityLabel(
                                String(
                                    format: localized("Step %lld of %lld: %@"),
                                    Int64(page.rawValue), Int64(OnboardingPage.steps.count), page.label)
                            )
                            .accessibilityAddTraits(current == page ? .isSelected : [])
                            .accessibilityIdentifier("onboarding.page.\(page.rawValue)")
                            .id(page)
                            if page != OnboardingPage.steps.last {
                                Capsule()
                                    .fill(OnboardingStyle.green.opacity(page.rawValue < current.rawValue ? 0.65 : 0.14))
                                    .frame(width: 4, height: 14)
                                    .padding(.leading, 11)
                                    .accessibilityHidden(true)
                            }
                        }
                        .animation(OnboardingMotion.detail, value: current)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onAppear { reader.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, page in
                guard !visiblePages.contains(page) else { return }
                withAnimation(reduceMotion ? nil : OnboardingMotion.detail) {
                    reader.scrollTo(page, anchor: .center)
                }
            }
        }
    }

    private func circleColor(_ page: OnboardingPage) -> Color {
        if page == current { return Color(red: 0.19, green: 0.43, blue: 0.36) }
        return OnboardingStyle.green.opacity(page.rawValue < current.rawValue ? 0.18 : 0.065)
    }
}
