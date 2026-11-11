# WhiskyMac

[English](README.md) | [简体中文](README.zh-CN.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

Ursprungsprojekt: [Whisk — nathan-poncet/whisk](https://github.com/nathan-poncet/whisk).

Repository: [lshayc1own/WhiskyMac](https://github.com/lshayc1own/WhiskyMac).
Dieses Entwicklungsrepository ist privat; die öffentliche Verteilung von Binärdateien ist noch nicht eingerichtet.

WhiskyMac ist ein macOS-Zwischenablagenmanager auf Grundlage von
[Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7)
von Nathan Poncet und Mitwirkenden. Ausgangscommit:
`1ebcee1e0735e957777c599017ee411d8046c7e7`.
Diese unabhängige, veränderte Fassung wird von **LinShay (琳曦)** gepflegt.
Sie ist keine offizielle Whisk-Version und bedeutet keine Billigung durch das Ursprungsprojekt.
Aktuelle Änderungen stehen in [CHANGELOG.md](CHANGELOG.md).

## Funktionen

- Lokaler Verlauf für Text, Rich Text, Links, Bilder, Dateien und Farben; Suche nach Inhalt oder Quellanwendung sowie Filter nach App, Kategorie, angehefteten Einträgen und Farbmarkierungen.
- Kopieren, direktes Einfügen oder Einfügen als Klartext, Drag-and-drop, Vorschau, Textbearbeitung, Einfügereihenfolge und optionale Vim-Navigation. Rich-Text-Formate mit gleichem Klartext werden zur Auswahl gruppiert.
- Text nach Zeilen, Absätzen oder Trennzeichen aufteilen oder HTTP(S)-Links extrahieren. Teile lassen sich als neue Karten, als Ersatz der ursprünglichen Karte oder als dauerhafte Gruppe speichern; beim Kopieren und Einfügen können einzelne Teile gewählt werden.
- Angeheftete Einträge mit durchsuchbaren Notizen, sieben Farbmarkierungen und optional dauerhaft verborgenem Inhalt. Anzeige im Verlauf oder in einem separaten Fenster; Aufbewahrungsdauer und Kapazität für nicht angeheftete Einträge sind einstellbar, das Löschen lässt sich rückgängig machen.
- Manueller Datenschutzmodus, optionale eingeschränkte Erkennung von Freigabe-Symbolleisten, einstellbarer Sichtbereich am Mauszeiger sowie optionale Suche und Filter bei verdecktem Inhalt. Kartenaktionen lassen sich je Modus getrennt einstellen.
- Sensible Apps: Kopien bleiben vorübergehend im Speicher und verfallen nach einer einstellbaren Zeit. Ausgeschlossene Apps werden gar nicht erfasst.
- Aufnahme pausieren, Start bei Anmeldung wählen und Kartengröße, Glasoptik, Menüleistensymbol, Sprache, Tastenkürzel sowie Kartenaktionen anpassen. Einstellungssuche und Zurücksetzen von Tastenkürzeln nach Kategorie mit Rückgängig-Funktion. Optionale Kopiergeräusche aus Kenney UI Audio, SFX Kit und macOS.
- Oberfläche auf Englisch, Französisch, Deutsch, Italienisch und vereinfachtem Chinesisch.

Weitere Einzelheiten und Einschränkungen stehen in den [Entwicklungshinweisen](docs/DEVELOPMENT.md) und im [Änderungsprotokoll](CHANGELOG.md). Die Software ist derzeit eine Entwicklungsversion.

## Bauen und prüfen

Erforderlich sind macOS 15 oder neuer und das macOS 26 SDK. Tests und Ressourcenerzeugung erfordern eine vollständige Xcode-Installation.

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

Das Skript erzeugt `dist/WhiskyMac.app` und `dist/WhiskyMac.zip`. Das interne Swift-Target und die ausführbare Datei heißen weiterhin `Whisk`, damit die bestehende Modul- und Ressourcenstruktur erhalten bleibt. Ohne Signaturidentität wird die App ad hoc signiert; dies ist weder eine Notarisierung noch eine App-Store-Zulassung.

## Daten und Datenschutz

Die Bundle-ID lautet `dev.whisky.maclx`. Der bestehende Entwicklungsverlauf bleibt unter `~/Library/Application Support/WhiskMay-Dev`; die Umbenennung verschiebt oder löscht ihn nicht. Mit `WHISK_MAY_DATA_DIR` lassen sich Tests isolieren. Der Verlauf des ursprünglichen Whisk wird nicht automatisch importiert.

Globale Tastenkürzel und Linkvorschauen sind anfangs ausgeschaltet. Bei aktivierten Linkvorschauen werden Metadaten von der kopierten Website abgerufen. Die Updateprüfung ist für diese Entwicklungsdistribution deaktiviert. Direktes Einfügen und die optionale Freigabeerkennung können macOS-Berechtigungen benötigen. Der Datenschutz kann bereits an andere Apps übertragene Inhalte nicht zurückholen.

## Lizenz und Namensnennung

Die Software steht unter **GPL-3.0-or-later**; gesondert lizenzierte Materialien Dritter behalten ihre eigenen Bedingungen. [LICENSE](LICENSE), [NOTICE](NOTICE) und [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) sind beizubehalten.

- Ursprüngliches Whisk: © 2026 Nathan Poncet und Mitwirkende.
- WhiskyMac-Änderungen: © 2026 LinShay (琳曦), soweit entsprechende Rechte vorliegen.
- Zusätzliche Erlaubnis des Ursprungsprojekts für App Store und TestFlight: [unveränderter Originaltext](LICENSE-EXCEPTION-APP-STORE.md).
- Erlaubnis von LinShay für berechtigt lizenzierte Ergänzungen: [eigenständiger Text](LICENSE-EXCEPTION-WHISKYMAC.md).

Die ursprüngliche Ausnahme umfasst ausdrücklich Werke auf Grundlage von Whisk. Diese Erlaubnisse betreffen das Urheberrecht für die genannten Vertriebswege; Apple-Prüfung, Signierung und Rechte an Material Dritter sind gesondert zu klären. Das Neovim-Zeichen von Jason Long steht unter CC BY 3.0; mitgelieferte Töne von Kenney UI Audio und Wyzowl SFX Kit stehen unter CC0. Einzelheiten enthalten die Hinweise zu Drittmaterial.

Wer Binärdateien weitergibt, muss den vollständigen, genau zu dieser Fassung gehörenden Quellcode bereitstellen, einschließlich Änderungen, bearbeitbarer Ressourcen und erforderlicher Build-Skripte. Ein Verweis allein auf den unveränderten Quellcode des Ursprungsprojekts genügt nicht. Für App Store oder TestFlight unter diesen Ausnahmen muss der entsprechende Quellcode öffentlich zugänglich bleiben. Für die Pflege dieses Derivats sind weder eine Urheberrechtsübertragung noch ein Lizenzkauf oder ein „GPL-Zertifikat“ nötig.

## Veröffentlichung

Das Entwicklungsrepository ist privat. Öffentliche Adressen für Quellcode, Support und Datenschutzerklärung fehlen noch. Vor der externen Binärverteilung [release-config.json](release-config.json) ausfüllen; leere Felder lassen die Freigabeprüfung scheitern. Konten und Websites des Ursprungsprojekts sind keine Veröffentlichungsziele dieses Projekts.

Rechtstexte werden nach `Contents/Resources/Legal` ins App-Paket kopiert. **Lizenzen und Hinweise…** in der Menüleiste öffnet Einstellungen → Über → Lizenzen und Hinweise; dort lassen sich die Dateien öffnen oder im Finder anzeigen. Siehe [Lizenzprüfung](docs/LICENSING.md). Pakete und lokale Abnahmeunterlagen gehören nicht ins Repository; installierbare Pakete werden über GitHub Releases verteilt.

Beiträge: [CONTRIBUTING.md](CONTRIBUTING.md). Architektur: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
