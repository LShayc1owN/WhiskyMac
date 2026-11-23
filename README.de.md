<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac-App-Symbol"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Kopierte Inhalte schnell wiederfinden.<br>Zwischenablagenverlauf für macOS 15 und neuer.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac ist eine unabhängige Bearbeitung von [Whisk](https://github.com/nathan-poncet/whisk). Das Projekt befindet sich in Entwicklung: Dieses Repository ist privat; öffentliche App-Downloads sind noch nicht eingerichtet. Die folgenden Schritte gelten für einen Build aus dieser Projektkopie.

## Funktionen im Überblick

- **Kopien finden.** Der lokale Verlauf speichert Text, Rich Text, Links, Bilder, Dateien und Farben. Suche nach Inhalt oder Quell-App; Filter nach App, Typ, Pins, Farbmarkierungen und Handoff-Zuordnung. Dateipfade als Text haben einen eigenen Filter und lassen sich mit `type:path` suchen.
- **Inhalte wiederverwenden.** Kopieren, direkt oder als Klartext einfügen, in andere Apps ziehen, Vorschau öffnen, bearbeiten und eine Einfügereihenfolge nutzen. Rich-Text-Versionen mit gleichem Klartext werden gruppiert. Tastatursteuerung und optionale Vim-Navigation stehen bereit.
- **Aufteilen und ordnen.** Text nach Zeilen, Absätzen oder Trennzeichen aufteilen oder HTTP(S)-Links extrahieren. Teile prüfen und anschließend als neue Karten, Ersatz oder dauerhafte Gruppe speichern. Beim Kopieren und Einfügen Original oder einzelne Gruppenteile auswählen.
- **Wichtiges behalten.** Pins bieten durchsuchbare Notizen, sieben Farbmarkierungen und auf Wunsch dauerhaft verdeckten Inhalt. Sie erscheinen im Verlauf oder in einem eigenen Fenster. Aufbewahrungsdauer und Kapazität nicht angehefteter Einträge sind einstellbar; Löschen lässt sich rückgängig machen.
- **Anzeige kontrollieren.** Der manuelle Datenschutzmodus verdeckt Inhalte. Die optionale Erkennung von Zoom-/Teams-Freigabe-Symbolleisten ist begrenzt. Suche, Filter und Sichtbereich am Mauszeiger lassen sich getrennt einschalten. Sensible Apps verwenden einen ablaufenden Speicherbereich; ausgeschlossene Apps werden nicht erfasst.
- **Persönlich einstellen.** Kartengröße, matte Oberfläche, Menüleistensymbol, Interaktionen, Tastenkürzel und optionale Kopiergeräusche lassen sich anpassen. Einstellungssuche und Rückgängig nach dem Zurücksetzen von Kürzeln helfen dabei. Der Übungsbereich beim ersten Start verändert weder die echte Zwischenablage noch den Verlauf. Die Oberfläche ist auf Englisch, Französisch, Deutsch, Italienisch, vereinfachtem und traditionellem Chinesisch sowie Japanisch verfügbar.

Genaues Verhalten und Grenzen stehen im [Projektumfang](docs/PROJECT.md) und [Änderungsprotokoll](CHANGELOG.md).

## Aus dem Quellcode bauen

Erforderlich sind macOS 15 oder neuer, das macOS 26 SDK und eine vollständige Xcode-Installation. In dieser Projektkopie ausführen:

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

Das Skript erzeugt `dist/WhiskyMac.app` und `dist/WhiskyMac.zip`. Das interne Swift-Target und die ausführbare Datei heißen weiter `Whisk`. Ohne Signaturidentität wird ad hoc signiert; die App ist damit weder notarisiert noch bereit für eine App-Store-Einreichung.

## Datenschutz und Daten

- Der Verlauf bleibt unter `~/Library/Application Support/WhiskMay-Dev` mit Bundle-ID `dev.whisky.maclx`. Die Umbenennung verschiebt oder löscht bestehende Entwicklungsdaten nicht; der ursprüngliche Whisk-Verlauf wird nicht automatisch importiert. `WHISK_MAY_DATA_DIR` dient isolierten Tests.
- Globale Kürzel, Linkvorschauen, Freigabeerkennung und Updateprüfungen beim Start sind anfangs aus. Aktivierte Linkvorschauen fragen Metadaten bei der kopierten Website ab. Manuelle und freiwillig aktivierte automatische Updateprüfungen verwenden stabile WhiskyMac-Versionen auf GitHub; App-Store-Builds verzichten auf externe Prüfungen.
- Direktes Einfügen und die optionale Freigabeerkennung können macOS-Berechtigungen benötigen. Die Handoff-Zuordnung ist ein Hinweis nach bestem Bemühen, keine verifizierte Geräte- oder App-Identität. Der Datenschutzmodus kann bereits an andere Apps übertragene Inhalte nicht zurückholen.

Weitere Einzelheiten: [Entwicklungshinweise](docs/DEVELOPMENT.md).

## Herkunft und Lizenz

WhiskyMac ist eine unabhängige Bearbeitung von [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) (Ausgangscommit `1ebcee1e0735e957777c599017ee411d8046c7e7`). Das [Ursprungsprojekt](https://github.com/nathan-poncet/whisk) stammt von Nathan Poncet und Mitwirkenden. WhiskyMac wird von **LinShay (琳曦)** gepflegt und ist weder eine offizielle Whisk-Version noch eine Billigung durch das Ursprungsprojekt.

Die Software steht unter **GPL-3.0-or-later**; gesondert lizenzierte Materialien Dritter behalten ihre eigenen Bedingungen. [LICENSE](LICENSE), [NOTICE](NOTICE) und [Hinweise zu Drittmaterial](THIRD_PARTY_NOTICES.md) sind beizubehalten. Ursprüngliche Whisk-Teile: © 2026 Nathan Poncet und Mitwirkende. WhiskyMac-Ergänzungen: © 2026 LinShay (琳曦), soweit entsprechende Rechte vorliegen.

Die [App-Store-/TestFlight-Ausnahme des Ursprungsprojekts](LICENSE-EXCEPTION-APP-STORE.md) bleibt unverändert. Die [separate Ausnahme von LinShay](LICENSE-EXCEPTION-WHISKYMAC.md) deckt nur Ergänzungen ab, für die LinShay Rechte zur Lizenzierung besitzt. Wer Binärdateien verteilt, muss den vollständigen, zu dieser Version gehörenden Quellcode bereitstellen; bei Nutzung dieser Ausnahmen muss er öffentlich zugänglich bleiben. Apple-Prüfung, Signierung und Rechte Dritter sind gesonderte Voraussetzungen. Das Neovim-Zeichen steht unter CC BY 3.0; mitgelieferte Kenney-UI-Audio- und Wyzowl-SFX-Kit-Töne unter CC0. Siehe [Lizenzprüfung](docs/LICENSING.md).

## Veröffentlichung und Unterstützung

Öffentliche Adressen für Quellcode, Support und Datenschutzerklärung fehlen in [release-config.json](release-config.json) noch; die Freigabeprüfung blockiert unvollständige Angaben. Installierbare Pakete sollen künftig zusammen mit dem zugehörigen Quellcode über GitHub Releases verteilt und nicht im Repository abgelegt werden. Rechtstexte liegen im App-Paket unter `Contents/Resources/Legal` und sind über **Lizenzen und Hinweise…** in der Menüleiste erreichbar.

Wenn WhiskyMac Ihnen hilft, können Sie die unabhängige Entwicklung freiwillig mit einer Spende unterstützen:

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

## Weitere Informationen

[Projektumfang](docs/PROJECT.md) · [Entwicklung](docs/DEVELOPMENT.md) · [Architektur](docs/ARCHITECTURE.md) · [Änderungsprotokoll](CHANGELOG.md) · [Mitwirken](CONTRIBUTING.md)
