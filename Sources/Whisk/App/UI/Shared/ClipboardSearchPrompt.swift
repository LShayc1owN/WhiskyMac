import AppKit
import SwiftUI

struct ClipboardSearchPrompt {
    static let fontSize: CGFloat = 14
    let label: String
    private let number: String
    private let numberFont: NSFont

    init(count: Int, typography: InterfaceTypography = .standard) {
        label = localized("Search in \(count) items")
        number = count.formatted(.number.locale(AppLocalization.interfaceLocale))
        numberFont = .monospacedSystemFont(ofSize: typography.points(Self.fontSize), weight: .regular)
    }

    var width: CGFloat {
        let text = NSMutableAttributedString(
            string: label, attributes: [.font: NSFont.systemFont(ofSize: numberFont.pointSize)])
        let range = (label as NSString).range(of: number)
        if range.location != NSNotFound { text.addAttribute(.font, value: numberFont, range: range) }
        return ceil(text.size().width)
    }

    func highlighted(accent: Color) -> AttributedString {
        styledCount(in: label, font: Font(numberFont), color: accent)
    }

    func styledCount(in label: String, font: Font, color: Color? = nil) -> AttributedString {
        var text = AttributedString(label)
        if let range = text.range(of: number) {
            text[range].font = font
            text[range].foregroundColor = color
        }
        return text
    }
}
