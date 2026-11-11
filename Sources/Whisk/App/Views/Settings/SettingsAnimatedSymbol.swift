// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Symbols

extension Notification.Name {
    static let settingsWindowOpened = Notification.Name("WhiskyMac.settingsWindowOpened")
    static let settingsWindowClosed = Notification.Name("WhiskyMac.settingsWindowClosed")
}

enum SettingsSymbolEffect: CaseIterable {
    case bounce
    case wiggle
    case pulse
    case scale
    case breathe
    case rotate
    case replace
}

struct SettingsSymbolEvent {
    var revision = 0
    var effect: SettingsSymbolEffect = .bounce
    var speed = 1.0
    var reversed = false
}

struct SettingsAnimatedSymbol: NSViewRepresentable {
    let symbolName: String
    let event: SettingsSymbolEvent
    let color: NSColor
    let reduceMotion: Bool
    var pointSize: CGFloat = 30

    final class Coordinator {
        var lastRevision = 0
        var symbolName = ""
        var pointSize: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = AppSymbol.image(named: symbolName, pointSize: pointSize)
        view.imageScaling = .scaleProportionallyDown
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.contentTintColor = color
        if context.coordinator.symbolName != symbolName || context.coordinator.pointSize != pointSize {
            view.image = AppSymbol.image(named: symbolName, pointSize: pointSize)
            context.coordinator.symbolName = symbolName
            context.coordinator.pointSize = pointSize
        }
        guard event.revision != context.coordinator.lastRevision else {
            return
        }
        context.coordinator.lastRevision = event.revision
        guard !reduceMotion, let image = AppSymbol.image(named: symbolName, pointSize: pointSize) else {
            return
        }
        view.removeAllSymbolEffects(animated: false)
        let options = SymbolEffectOptions.nonRepeating.speed(event.speed)
        switch event.effect {
        case .bounce:
            view.addSymbolEffect(event.reversed ? .bounce.byLayer.down : .bounce.byLayer.up, options: options)
        case .wiggle:
            view.addSymbolEffect(event.reversed ? .wiggle.byLayer.backward : .wiggle.byLayer.forward, options: options)
        case .pulse:
            view.addSymbolEffect(.pulse.byLayer, options: options)
        case .scale:
            view.addSymbolEffect(event.reversed ? .scale.byLayer.down : .scale.byLayer.up, options: options)
        case .breathe:
            view.addSymbolEffect(event.reversed ? .breathe.byLayer.plain : .breathe.byLayer.pulse, options: options)
        case .rotate:
            view.addSymbolEffect(
                event.reversed ? .rotate.byLayer.counterClockwise : .rotate.byLayer.clockwise,
                options: options)
        case .replace:
            view.setSymbolImage(image, contentTransition: .replace.byLayer, options: options)
        }
    }
}
