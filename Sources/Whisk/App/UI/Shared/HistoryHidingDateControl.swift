// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
final class HistoryHidingDateControl: NSObject {
    private var date: Binding<Date>
    private(set) lazy var picker = makePicker()

    init(date: Binding<Date>) { self.date = date }

    private func makePicker() -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.presentsCalendarOverlay = true
        picker.font = .systemFont(ofSize: NSFont.systemFontSize)
        picker.target = self
        picker.action = #selector(edited(_:))
        return picker
    }

    func update(date: Binding<Date>, locale: Locale, typography: InterfaceTypography) {
        self.date = date
        if picker.locale != locale {
            picker.locale = locale
            picker.calendar = locale.calendar
        }
        picker.timeZone = .current
        picker.setAccessibilityLabel(localized("Date and time"))
        picker.maxDate = .now
        if picker.dateValue != date.wrappedValue { picker.dateValue = date.wrappedValue }
        // Enlarging the cell font clips single-digit minutes inside AppKit's date segments.
        // Draw the native cell in its own coordinates so input, digits and stepper scale together.
        guard let cellSize = picker.cell?.cellSize else { return }
        let native = NSSize(width: ceil(cellSize.width), height: ceil(cellSize.height))
        let scaled = NSSize(width: native.width * typography.scale, height: native.height * typography.scale)
        if picker.frame.size != scaled || picker.bounds.size != native {
            picker.setFrameSize(scaled)
            picker.setBoundsSize(native)
        }
    }

    @objc private func edited(_ picker: NSDatePicker) {
        let now = Date()
        let selected = min(picker.dateValue, now)
        picker.maxDate = now
        if picker.dateValue != selected { picker.dateValue = selected }
        date.wrappedValue = selected
    }
}
