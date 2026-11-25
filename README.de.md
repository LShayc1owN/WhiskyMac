<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac-App-Symbol"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Kopierte Inhalte schnell wiederfinden.<br>Zwischenablagenverlauf für macOS 15 und neuer.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac ist ein eigenständiges Projekt auf Basis von [Whisk](https://github.com/nathan-poncet/whisk) und wird weiterentwickelt. Die Funktionen unten beziehen sich auf den aktuellen Quellcode. Was in einem Download enthalten ist und wie er signiert wurde, steht in den jeweiligen Versionshinweisen.

## Download und erste Schritte

**[Aktuelle Version auf GitHub](https://github.com/LShayc1owN/WhiskyMac/releases/latest)**

1. Lade unter **Assets** das App-Archiv `WhiskyMac-v*.zip` herunter. Entpacke es und verschiebe `WhiskyMac.app` in den Ordner „Programme“.
2. Öffne WhiskyMac und folge der Willkommensanleitung. Wenn Zugriff auf die Zwischenablage erforderlich ist, klicke mit der rechten Maustaste auf das WhiskyMac-Symbol in der Menüleiste und wähle **Zwischenablagezugriff erlauben…**.
3. Kopiere etwas in einer anderen App. Klicke dann auf das WhiskyMac-Symbol in der Menüleiste oder wähle **Verlauf anzeigen**. In den Einstellungen kannst du ein globales Tastenkürzel aktivieren.

## Funktionen im Überblick

- **Kopierte Inhalte finden.** Text, Rich Text, Code, Links, Bilder, Dateien und Farben werden lokal gespeichert. Suche nach Inhalt oder Quell-App, wahlweise unscharf, nach Teilzeichenfolge oder ganzem Wort sowie nach Textanfang oder Textende. Filtere nach App, Typ, angehefteten Einträgen, Farbmarkierungen oder Handoff. Mit `type:path` findest du Dateipfade, die als Text kopiert wurden.
- **Inhalte wiederverwenden.** Öffne die Vorschau, bearbeite, ziehe oder kopiere Inhalte, füge sie direkt oder als Klartext ein und stelle sie in die Einfügewarteschlange. Wähle zwischen gruppierten Rich-Text-Versionen und navigiere per Tastatur oder optional mit Vim-Tastenbelegungen.
- **Text aufteilen.** Teile Text nach Zeilen, Absätzen oder Trennzeichen auf oder extrahiere HTTP(S)-Links. Prüfe die Teile und speichere sie als neue Karten, als Ersatz oder als Gruppe. Beim Kopieren oder Einfügen einer Gruppe kannst du das Original oder ausgewählte Teile verwenden.
- **Den Verlauf organisieren.** Angeheftete Einträge können durchsuchbare Notizen, sieben Farbmarkierungen und auf Wunsch dauerhaft verdeckte Inhalte haben. Öffne sie im Verlauf oder in einem eigenen Fenster. Blende ältere Einträge nach Zeitpunkt, Inhaltstyp oder Handoff-Herkunft vorübergehend aus. Lege Aufbewahrungsdauer und Kapazität fest oder lösche nicht angeheftete Einträge mit der Möglichkeit, das Löschen rückgängig zu machen.
- **Die Anzeige steuern.** Der manuelle Datenschutzmodus verdeckt Karten. Suche, Filter und der Sichtbereich am Zeiger lassen sich einzeln einstellen. Über das Kartenmenü kannst du eine einzelne Karte an Ort und Stelle sichtbar machen. Die optionale Freigabeerkennung erfasst unterstützte Symbolleisten von Zoom und Teams. Kopien aus sensiblen Apps verfallen im Arbeitsspeicher. Ausgeschlossene Apps werden übersprungen.
- **Mögliche Geheimnisse verdecken.** Die lokale Erkennung sucht nach gängigen Formaten für API-Schlüssel, Tokens, Cookies und Hashwerte. Kartenmaskierung und Zuordnung zur Kategorie für Geheimnisse sind separat einstellbar. Die Maskierung betrifft die Anzeige auf der Karte.
- **Die passende Optik für deinen Mac.** Ab macOS 26 nutzen Bedienelemente im Verlauf und in den Einstellungen Liquid Glass. Unter macOS 15 kommt eine Milchglasoptik zum Einsatz. Wähle für den Verlauf und die Einstellungen getrennt zwischen hellem, dunklem und systemgesteuertem Erscheinungsbild.
- **Persönlich einstellen.** Passe Kartengröße, Menüleistensymbol, Kartenaktionen, Tastenkürzel und optionale Kopiergeräusche an. Durchsuche die Einstellungen oder setze Kürzel nach Kategorie zurück und mache das bei Bedarf rückgängig. Die Oberfläche ist auf Deutsch, Englisch, Französisch, Italienisch, vereinfachtem und traditionellem Chinesisch sowie Japanisch verfügbar.

Genaues Verhalten und Grenzen stehen im [Projektumfang](docs/PROJECT.md) und [Änderungsprotokoll](CHANGELOG.md).

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

Versionshinweise und Downloads für frühere Versionen findest du auf [GitHub Releases](https://github.com/LShayc1owN/WhiskyMac/releases). Die mitgelieferten Lizenzdokumente kannst du im WhiskyMac-Menü über **Lizenzen und Hinweise…** öffnen.

Wenn WhiskyMac Ihnen hilft, können Sie die unabhängige Entwicklung freiwillig mit einer Spende unterstützen:

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

## Weitere Informationen

[Projektumfang](docs/PROJECT.md) · [Entwicklungshandbuch](docs/DEVELOPMENT.md) · [Architektur](docs/ARCHITECTURE.md) · [Änderungsprotokoll](CHANGELOG.md) · [Mitwirken](CONTRIBUTING.md)
