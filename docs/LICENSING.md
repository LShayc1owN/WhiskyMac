# WhiskyMac licensing review

Reviewed on 2026-11-03. Upstream base: Whisk v1.0.3,
commit `1ebcee1e0735e957777c599017ee411d8046c7e7`.

## Verified requirements and implementation

1. GPLv3 sections 4–6 require retained notices, a license copy, prominent
   identification of modifications and their dates, and Corresponding Source
   when conveying object code. LICENSE remains the original GPLv3 text;
   NOTICE identifies this modified version and date. README and source notices
   state GPL-3.0-or-later. Packaging includes the legal documents.
2. GPLv3 section 7 permits additional permissions for material the grantor
   has authority to license. Nathan Poncet's exception expressly includes
   works based on Whisk. It remains unchanged; LinShay's separately authorized
   grant is in LICENSE-EXCEPTION-WHISKYMAC.md. CONTRIBUTING.md requires an
   explicit equivalent grant for new contributions.
3. The upstream exception requires the complete corresponding source to remain
   publicly available. The source for an upstream version alone does not satisfy
   this for a modified binary. Provide an exact release tag/archive and build
   instructions, including editable resources. Do not publish signing private
   keys, certificates containing private keys, API credentials or personal data.
4. Neovim's Jason Long logo attribution and CC BY 3.0 link are retained in
   THIRD_PARTY_NOTICES.md; the existing PNGs match the upstream copies.
   Kenney's supplied CC0 notice and source record remain in docs/licenses.
5. Apple review guidelines 5.2 and the Developer Program agreement require
   appropriate content rights. A GPL exception is not an Apple certificate,
   App Review approval, or a trademark grant.

## Publication details still needed

Set the actual public source, support and privacy URLs in release-config.json.
They are blank because no project-specific URLs have been supplied. App Store
metadata is a draft and cannot be uploaded until those locations are configured.
The publisher must verify the accuracy of privacy disclosures, asset provenance,
the released source and all third-party rights before submission. A LinShay
grant extends only to rights LinShay holds or can grant, including for artwork.

Existing website/demo material inherited from Whisk is historical upstream
material; it is not WhiskyMac's current privacy policy or marketing material.
Replace and review it before publishing a website or store listing. Local
acceptance reports, screenshots, editing workspaces and compiled packages
are excluded from the source repository. No release or upload was made
during the licensing review.

## Primary sources

- [GPLv3 text, sections 1 and 4–7](https://www.gnu.org/licenses/gpl-3.0.html)
- [GNU FAQ: modified binaries need corresponding modified source](https://www.gnu.org/licenses/gpl-faq.en.html#DistributeExtendedBinary)
- [GNU FAQ: stating the license](https://www.gnu.org/licenses/gpl-faq.en.html#LicenseCopyOnly)
- [Whisk's exact upstream exception](https://github.com/nathan-poncet/whisk/blob/1ebcee1e0735e957777c599017ee411d8046c7e7/LICENSE-EXCEPTION-APP-STORE.md)
- [Neovim's official logo attribution](https://store.neovim.io/products/neovim-sticker-logo-only)
- [CC BY 3.0 legal code](https://creativecommons.org/licenses/by/3.0/legalcode)
- [Kenney licensing FAQ](https://kenney.nl/support)
- [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)
- [Apple Developer Program agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
