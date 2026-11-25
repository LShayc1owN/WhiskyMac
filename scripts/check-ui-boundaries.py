#!/usr/bin/env python3
"""Check the source boundaries within the single Whisk target."""
import argparse
from pathlib import Path
import re
import sys
import unittest

SELECTOR = Path("App/Composition/AppUISelector.swift")
ENTRY_POINT = Path("App/WhiskyMacMain.swift")
FACTORIES = {"MacOS15UIFactory", "MacOS26UIFactory"}
SHARED_VIEWS = {
    (Path("App/Panel/PanelController.swift"), "FloatingPanel"),
    (Path("App/Panel/PanelController.swift"), "SplitDialogPanel"),
    (Path("App/StatusMenu/StatusBarSymbol.swift"), "ClickThroughSymbolView"),
    (Path("Components/IndexedForEach.swift"), "IndexedForEach"),
    (Path("Components/MarqueeText.swift"), "MarqueeText"),
    (Path("Components/SettingsRowLabel.swift"), "SettingsRowLabel"),
}

# Keep source locations stable when masking comments and literals.
NON_CODE = re.compile(r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\\n])*"', re.S)
GENERATION = re.compile(r"\b(?:MacOS|macOS)(15|26)\w*\b")
UI_CONFORMANCE = re.compile(
    r"\b(?:View|NS[A-Za-z]*View|NSWindow|NSPanel|NSPopover|NSViewRepresentable|"
    r"NSViewControllerRepresentable|ViewModifier|Layout|Shape|InsettableShape|"
    r"ButtonStyle|PrimitiveButtonStyle|ToggleStyle|MenuStyle)\b"
)
DECLARATION = re.compile(r"\b(?:struct|class|enum|actor)\s+(\w+)\s*([^{}=]*)\{")
OWNED_TYPE = re.compile(
    r"^(?:(?:private|fileprivate|final|public|indirect)\s+)*(?:class|struct|enum|actor|protocol|typealias)\s+(\w+)",
    re.M,
)
RENDERED_BODY = re.compile(r"\bvar\s+body\s*:\s*some\s+(?:SwiftUI\.)?View\b")
VERSION_SWITCH = re.compile(r"#(?:un)?available\s*\([^)]*\bmacOS\s+(?:15|26)(?:\.0)*(?=\s*[,)])")
LEGACY_FLAG = re.compile(r"\b\w*(?:MacOS|macOS)(?:15|26)Cards\b|\bMACOS(?:15|26)_UI\b")
VERSION_PROBE = re.compile(r"\b(?:operatingSystemVersion|isOperatingSystemAtLeast)\b")


def check_file(path, source):
    code = NON_CODE.sub(lambda match: re.sub(r"[^\n]", " ", match[0]), source)
    parts = path.parts
    target = parts[2][-2:] if parts[:2] == ("App", "UI") and len(parts) > 3 and parts[2] in {
        "MacOS15", "MacOS26"
    } else None
    problems = []

    def reject(offset, reason):
        problems.append(f"{path}:{code.count(chr(10), 0, offset) + 1}: {reason}")

    for match in GENERATION.finditer(code):
        if path == SELECTOR and match[0] in FACTORIES:
            continue
        if target != match[1]:
            reject(match.start(), f"invalid reference to generation-owned symbol {match[0]}")

    for match in LEGACY_FLAG.finditer(code):
        reject(match.start(), f"obsolete UI generation flag {match[0]}")

    if path != SELECTOR:
        for match in VERSION_SWITCH.finditer(code):
            reject(match.start(), "select the UI generation in AppUISelector")
        if path.parts[:1] == ("App",) and path != Path("App/StatusMenu/SymbolCatalog.swift"):
            for match in VERSION_PROBE.finditer(code):
                reject(match.start(), "use framework availability at the API boundary")
    if path != ENTRY_POINT:
        for match in re.finditer(r"\bAppUISelector\s*\.\s*make\s*\(", code):
            reject(match.start(), "select the factory once at application startup")

    if path.parts[:2] == ("App", "Views"):
        reject(0, "move the former Views source into a UI generation or Presentation")
    if target is not None:
        for match in OWNED_TYPE.finditer(code):
            if not match[1].startswith(f"MacOS{target}"):
                reject(match.start(), f"prefix top-level type {match[1]} with MacOS{target}")
    else:
        for match in DECLARATION.finditer(code):
            if UI_CONFORMANCE.search(match[2]) and (path, match[1]) not in SHARED_VIEWS:
                reject(match.start(), f"move {match[1]} into its owning UI generation")
        if not any(entry[0] == path for entry in SHARED_VIEWS):
            for match in RENDERED_BODY.finditer(code):
                reject(match.start(), "move the rendered body into its owning UI generation")
    return problems


class BoundaryTests(unittest.TestCase):
    def test_generation_references(self):
        legacy = Path("App/UI/MacOS15/Clipboard/History.swift")
        modern = Path("App/UI/MacOS26/Clipboard/History.swift")
        self.assertFalse(check_file(legacy, "struct MacOS15History: View { }"))
        self.assertFalse(check_file(modern, "@available(macOS 26, *) struct MacOS26History: View {}"))
        self.assertTrue(check_file(legacy, "let card = MacOS26History()"))
        self.assertTrue(check_file(legacy, "struct History: View {}"))
        self.assertTrue(check_file(modern, "let card = MacOS15History()"))
        for folder in ("UI/Contracts", "UI/Shared", "Presentation", "Panel"):
            self.assertTrue(check_file(Path(f"App/{folder}/State.swift"), "let view: MacOS15History"))

    def test_version_selection(self):
        path = Path("App/Panel/History.swift")
        self.assertTrue(check_file(path, "if #available(macOS 26, *) {}"))
        self.assertTrue(check_file(path, "guard #available(macOS 26.0, *) else { return }"))
        self.assertTrue(check_file(path, "let usesMacOS26Cards = true"))
        self.assertTrue(check_file(path, "let factory = AppUISelector.make()"))
        self.assertFalse(check_file(path, "if #available(macOS 15.4, *) {}"))
        self.assertFalse(check_file(SELECTOR, "if #available(macOS 26, *) { MacOS26UIFactory() }"))
        self.assertFalse(check_file(ENTRY_POINT, "let factory = AppUISelector.make()"))

    def test_placement(self):
        shared = Path("App/UI/Shared/NotShared.swift")
        self.assertTrue(check_file(shared, "struct Settings: SwiftUI.View { }"))
        self.assertTrue(check_file(shared, "struct Settings { var body: some View { Text(\"Title\") } }"))
        self.assertTrue(check_file(Path("App/Views/Settings.swift"), "struct Old {}"))
        self.assertFalse(check_file(Path("Components/MarqueeText.swift"), "struct MarqueeText: View {}"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(BoundaryTests)
        return 0 if unittest.TextTestRunner().run(suite).wasSuccessful() else 1
    root = Path(__file__).resolve().parents[1] / "Sources" / "Whisk"
    problems = [
        issue
        for path in sorted(root.rglob("*.swift"))
        for issue in check_file(path.relative_to(root), path.read_text(encoding="utf-8"))
    ]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("UI boundaries: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
