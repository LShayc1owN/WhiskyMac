// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Bounded display preferences. Blur is the soft edge inside the reveal circle,
/// never a filter that draws or blurs a full unmasked clipboard preview.
struct SpotlightPreferences: Codable, Equatable {
    static let defaultDiameter = 150.0
    static let defaultBlurRadius = 50.0
    static let diameterRange = 40.0...320.0
    static let maximumBlurRadius = 80.0

    var diameter: Double {
        didSet {
            diameter = Self.validDiameter(diameter)
            blurRadius = Self.validBlur(blurRadius, diameter: diameter)
        }
    }
    var blurRadius: Double {
        didSet { blurRadius = Self.validBlur(blurRadius, diameter: diameter) }
    }

    var outerRadius: Double { diameter / 2 }
    var innerRadius: Double { outerRadius - blurRadius }
    var blurRange: ClosedRange<Double> { 0...min(Self.maximumBlurRadius, outerRadius) }

    init(
        diameter: Double = SpotlightPreferences.defaultDiameter,
        blurRadius: Double = SpotlightPreferences.defaultBlurRadius
    ) {
        self.diameter = Self.validDiameter(diameter)
        self.blurRadius = Self.validBlur(blurRadius, diameter: self.diameter)
    }

    private static func validDiameter(_ value: Double) -> Double {
        value.isFinite ? min(diameterRange.upperBound, max(diameterRange.lowerBound, value)) : defaultDiameter
    }

    private static func validBlur(_ value: Double, diameter: Double) -> Double {
        min(min(maximumBlurRadius, diameter / 2), max(0, value.isFinite ? value : defaultBlurRadius))
    }

    /// Draft text commits on Return or focus loss, so typing 150 never clamps
    /// the intermediate 1 to the minimum. Invalid drafts retain the old value.
    static func points(from input: String) -> Double? {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Double(value)
    }

    private enum CodingKeys: CodingKey { case diameter, blurRadius }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            diameter: try values.decodeIfPresent(Double.self, forKey: .diameter) ?? Self.defaultDiameter,
            blurRadius: try values.decodeIfPresent(Double.self, forKey: .blurRadius) ?? Self.defaultBlurRadius)
    }
}
