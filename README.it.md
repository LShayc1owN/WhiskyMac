<p align="center"><img src="Assets/icon.png" width="112" alt="Icona di WhiskyMac"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Ritrova subito ciò che hai copiato.<br>Cronologia degli appunti per macOS 15 e successivi.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac è una modifica indipendente di [Whisk](https://github.com/nathan-poncet/whisk). Il progetto è in fase di sviluppo: questo repository è privato e i download pubblici dell'app non sono ancora configurati. Le istruzioni seguenti servono a compilare questa copia del progetto.

## Funzioni principali

- **Ritrovare le copie.** La cronologia locale conserva testo, testo formattato, link, immagini, file e colori. Cerca nel contenuto o per app di origine; filtra per app, tipo, elementi fissati, etichette colorate e attribuzione Handoff. I percorsi di file come testo hanno un filtro dedicato e la ricerca `type:path`.
- **Riutilizzare i contenuti.** Copia, incolla direttamente o come testo semplice, trascina in altre app, visualizza anteprime, modifica e usa la coda di incolla. Le versioni rich text con lo stesso testo semplice sono raggruppate. Sono disponibili comandi da tastiera e navigazione Vim facoltativa.
- **Dividere e organizzare.** Dividi il testo per righe, paragrafi o separatori, oppure estrai i link HTTP(S). Controlla le parti e salvale come nuove schede, sostituzione dell'originale o gruppo persistente. Durante copia e incolla scegli l'originale o singole parti del gruppo.
- **Conservare l'importante.** Gli elementi fissati possono avere note ricercabili, sette etichette colorate e contenuto sempre oscurato. Mostrali nella cronologia o in una finestra separata. Imposta durata e capienza degli elementi non fissati; la cancellazione si può annullare.
- **Controllare la visualizzazione.** La modalità privacy manuale oscura i contenuti. Il rilevamento facoltativo delle barre di condivisione Zoom/Teams ha copertura limitata. Ricerca, filtri e area visibile presso il puntatore si attivano separatamente. Le app sensibili usano una sessione temporanea in memoria; le app escluse non vengono registrate.
- **Personalizzare.** Regola dimensione delle schede, aspetto satinato, icona nella barra dei menu, interazioni, scorciatoie e suoni di copia facoltativi. Puoi cercare nelle impostazioni e annullare il ripristino delle scorciatoie. L'esercizio della guida iniziale non tocca gli appunti o la cronologia reali. L'interfaccia supporta inglese, francese, tedesco, italiano, cinese semplificato, cinese tradizionale e giapponese.

Per comportamenti e limiti dettagliati, consulta l'[ambito del progetto](docs/PROJECT.md) e il [registro modifiche](CHANGELOG.md).

## Compilare dai sorgenti

Occorrono macOS 15 o successivo, l'SDK macOS 26 e un'installazione completa di Xcode. In questa copia del progetto esegui:

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

Lo script genera `dist/WhiskyMac.app` e `dist/WhiskyMac.zip`. Il target Swift e l'eseguibile interni conservano il nome `Whisk`. Senza un'identità di firma si usa una firma ad hoc: l'app non risulta notarizzata né pronta per l'invio all'App Store.

## Privacy e dati

- La cronologia rimane in `~/Library/Application Support/WhiskMay-Dev` con ID bundle `dev.whisky.maclx`. Il nuovo nome non sposta né cancella i dati di sviluppo esistenti; la cronologia di Whisk originale non viene importata automaticamente. `WHISK_MAY_DATA_DIR` serve per i test isolati.
- Scorciatoie globali, anteprime dei link, rilevamento della condivisione e controllo degli aggiornamenti all'avvio sono disattivati inizialmente. Le anteprime attivate chiedono metadati al sito copiato. I controlli manuali o automatici attivati dall'utente usano le versioni stabili di WhiskyMac su GitHub; le build App Store non effettuano controlli esterni.
- L'incolla diretto e il rilevamento facoltativo della condivisione possono richiedere permessi macOS. L'attribuzione Handoff è un indizio approssimativo, non un'identificazione verificata del dispositivo o dell'app. La modalità privacy non può ritirare contenuti già inviati ad altre app.

Per altri dettagli: [note di sviluppo](docs/DEVELOPMENT.md).

## Origine e licenza

WhiskyMac è una modifica indipendente di [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) (commit iniziale `1ebcee1e0735e957777c599017ee411d8046c7e7`). Il [progetto originale](https://github.com/nathan-poncet/whisk) è di Nathan Poncet e collaboratori. WhiskyMac è mantenuto da **LinShay (琳曦)**; non è una versione ufficiale di Whisk né implica approvazione da parte degli autori originali.

Il software è distribuito con licenza **GPL-3.0-or-later**, salvo i materiali di terze parti con licenze separate. Conserva la [licenza](LICENSE), la [nota del progetto](NOTICE) e le [informazioni sulle terze parti](THIRD_PARTY_NOTICES.md). Parti originali di Whisk: © 2026 Nathan Poncet e collaboratori. Aggiunte di WhiskyMac: © 2026 LinShay (琳曦), nei limiti dei diritti posseduti.

L'[eccezione originale per App Store/TestFlight](LICENSE-EXCEPTION-APP-STORE.md) è conservata invariata. L'[eccezione separata di LinShay](LICENSE-EXCEPTION-WHISKYMAC.md) copre solo le aggiunte per cui LinShay dispone dei diritti necessari. Distribuire binari richiede il codice sorgente completo corrispondente a quella versione; con queste eccezioni deve restare pubblicamente accessibile. Revisione Apple, firma e diritti di terzi restano requisiti separati. Il marchio Neovim è CC BY 3.0; i suoni inclusi di Kenney UI Audio e Wyzowl SFX Kit sono CC0. Vedi la [verifica delle licenze](docs/LICENSING.md).

## Versioni e sostegno

Gli indirizzi pubblici per sorgenti, assistenza e informativa sulla privacy in [release-config.json](release-config.json) sono ancora vuoti; la verifica blocca la pubblicazione finché non vengono configurati. I pacchetti installabili dovranno essere distribuiti tramite GitHub Releases insieme ai sorgenti corrispondenti, senza aggiungerli al repository. I documenti legali nell'app si trovano in `Contents/Resources/Legal`, accessibili da **Licenze e avvisi…** nella barra dei menu.

Se WhiskyMac ti è utile, puoi sostenere lo sviluppo indipendente con una donazione volontaria:

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

## Altre informazioni

[Ambito del progetto](docs/PROJECT.md) · [Sviluppo](docs/DEVELOPMENT.md) · [Architettura](docs/ARCHITECTURE.md) · [Registro modifiche](CHANGELOG.md) · [Contributi](CONTRIBUTING.md)
