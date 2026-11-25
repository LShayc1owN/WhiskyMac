// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

enum TranslationCredits {
    struct Human: Identifiable {
        enum Kind {
            case person, organization

            var symbol: String {
                switch self {
                case .person: "person.fill"
                case .organization: "person.2.fill"
                }
            }
        }

        let name: String
        let kind: Kind
        let languages: [AppLanguage]
        let homepages: [ProfileHomepage]
        var id: String { name }
    }

    struct AIProduct: Identifiable {
        let product: ProfileHomepage
        let provider: ProfileHomepage
        let languages: [AppLanguage]
        var id: URL { product.destination }
    }

    private static var humans: [Human] {
        [
            Human(
                name: "LinShay 琳曦", kind: .person, languages: [.simplifiedChinese],
                homepages: ProfileHomepage.developerHomepages)
        ]
    }

    private static let aiProducts = [
        AIProduct(
            product: ProfileHomepage(title: "ChatGPT", destination: URL(string: "https://chatgpt.com/")!),
            provider: ProfileHomepage(title: "OpenAI", destination: URL(string: "https://openai.com/")!),
            languages: AppLanguage.allCases.filter { $0 != .system })
    ]

    static let aiProductSymbol: String = {
        let preferred = "cube.plane.bottom.right.detached"
        return NSImage(systemSymbolName: preferred, accessibilityDescription: nil) == nil ? "cube" : preferred
    }()

    struct LanguageGroup: Identifiable {
        let language: AppLanguage
        let products: [AIProduct]
        let humans: [Human]
        var id: AppLanguage { language }
    }

    static var byLanguage: [LanguageGroup] {
        let contributors = humans
        return AppLanguage.allCases.filter { $0 != .system }.map { language in
            LanguageGroup(
                language: language,
                products: aiProducts.filter { $0.languages.contains(language) },
                humans: contributors.filter { $0.languages.contains(language) })
        }
    }
}
