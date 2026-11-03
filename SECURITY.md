# WhiskyMac security policy

WhiskyMac handles clipboard content and stores history locally. Avoid posting
clipboard contents, database files or other sensitive information in public issues.

## Reporting

Use **Security → Report a vulnerability** in the WhiskyMac repository if its
maintainer has enabled GitHub private vulnerability reporting. Otherwise ask the
maintainer for a private contact without disclosing the vulnerability publicly.
A private contact must be configured before a public release; do not send fork
reports to the upstream Whisk maintainer as if they maintained WhiskyMac.

Include the build version, macOS version and minimal reproduction steps using
synthetic content. No response-time or release-signing commitment is currently
made for this development build.

## Scope

Concealed clipboard data unexpectedly recorded, privacy-protected content
exposed, unexpected network transfers, and unsafe handling of crafted clipboard
data are relevant security reports. Accessibility permissions for direct paste
and same-account access to unencrypted local history are documented behavior.
See README.md and docs/DEVELOPMENT.md for development storage and privacy limits.
