<p align="center"><img src="Assets/icon.png" width="112" alt="Icona di WhiskyMac"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Ritrova subito ciò che hai copiato.<br>Cronologia degli appunti per macOS 15 e successivi.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac è un progetto indipendente basato su [Whisk](https://github.com/nathan-poncet/whisk) e ancora in sviluppo. Le funzioni descritte qui si riferiscono al codice sorgente attuale. Le note di ciascuna versione indicano le funzioni incluse e lo stato della firma.

## Download e primi passi

**[Ultima versione su GitHub](https://github.com/LShayc1owN/WhiskyMac/releases/latest)**

1. Nella sezione **Assets**, scarica il pacchetto dell’app `WhiskyMac-v*.zip`. Estrailo e sposta `WhiskyMac.app` nella cartella Applicazioni.
2. Apri WhiskyMac e segui la guida di benvenuto. Se è necessario concedere l’accesso agli appunti, fai clic destro sull’icona di WhiskyMac nella barra dei menu e scegli **Consenti accesso agli appunti…**.
3. Copia qualcosa in un’altra app, poi fai clic sull’icona di WhiskyMac nella barra dei menu o scegli **Mostra la cronologia**. Nelle impostazioni puoi attivare una scorciatoia globale.

## Funzioni principali

- **Ritrovare le copie.** Testo, testo formattato, codice, link, immagini, file e colori sono salvati in locale. Cerca per contenuto o app di origine, con corrispondenza approssimativa, parziale, per parola intera, all’inizio o alla fine del testo. Filtra per app, tipo, elementi fissati, etichette colorate o Handoff. Usa `type:path` per trovare i percorsi di file copiati come testo.
- **Riutilizzare i contenuti.** Visualizza anteprime, modifica, trascina, copia, incolla direttamente o come testo semplice e accoda gli elementi da incollare. Scegli tra le versioni di testo formattato raggruppate e naviga da tastiera o con i comandi Vim facoltativi.
- **Dividere il testo.** Dividi il testo per righe, paragrafi o separatori oppure estrai i link HTTP(S). Dopo l’anteprima, aggiungi schede, sostituisci l’originale o salva un gruppo. Quando copi o incolli un gruppo, scegli l’originale o le parti desiderate.
- **Organizzare la cronologia.** Fissa gli elementi con note ricercabili, sette etichette colorate e un’opzione per oscurare sempre il contenuto. Aprili nella cronologia o in una finestra separata. Nascondi temporaneamente le voci meno recenti per data e ora, tipo di contenuto o origine Handoff. Imposta durata e capienza degli elementi non fissati, oppure cancellali con la possibilità di annullare l’operazione.
- **Scegliere cosa mostrare.** La modalità privacy manuale oscura le schede. Ricerca, filtri e area visibile vicino al puntatore si regolano separatamente. Dal menu di una scheda puoi anche mostrarla direttamente nella cronologia. Il rilevamento facoltativo della condivisione dello schermo riconosce le barre degli strumenti supportate di Zoom e Teams. Le copie delle app sensibili scadono in memoria. Le app escluse vengono ignorate.
- **Oscurare i possibili segreti.** Il rilevamento locale cerca formati comuni di chiavi API, token, cookie e hash. L’oscuramento delle schede e la classificazione nella categoria dei segreti si configurano separatamente. L’oscuramento agisce sulla visualizzazione della scheda.
- **Adattare l’aspetto al Mac.** Da macOS 26, i controlli della cronologia e delle impostazioni usano Liquid Glass. Su macOS 15, l’interfaccia usa un effetto vetro satinato. Puoi scegliere separatamente per cronologia e impostazioni l’aspetto chiaro, scuro o di sistema.
- **Personalizzare i comandi.** Regola la dimensione delle schede, l’icona nella barra dei menu, le azioni, le scorciatoie e i suoni di copia facoltativi. Cerca nelle impostazioni o ripristina le scorciatoie per categoria con la possibilità di annullare. L’interfaccia è disponibile in italiano, inglese, francese, tedesco, cinese semplificato, cinese tradizionale e giapponese.

Per comportamenti e limiti dettagliati, consulta l'[ambito del progetto](docs/PROJECT.md) e il [registro modifiche](CHANGELOG.md).

## Privacy e dati

- WhiskyMac salva la cronologia in `~/Library/Application Support/WhiskyMac` e usa l’ID bundle `dev.whisky.maclx`. La cronologia di Whisk originale non viene importata automaticamente. `WHISKYMAC_DATA_DIR` serve per i test isolati.
- Scorciatoie globali, anteprime dei link, rilevamento della condivisione e controllo degli aggiornamenti all'avvio sono disattivati inizialmente. Le anteprime attivate chiedono metadati al sito copiato. I controlli manuali o automatici attivati dall'utente usano le versioni stabili di WhiskyMac su GitHub; le build App Store non effettuano controlli esterni.
- L'incolla diretto e il rilevamento facoltativo della condivisione possono richiedere permessi macOS. L'attribuzione Handoff è un indizio approssimativo, non un'identificazione verificata del dispositivo o dell'app. La modalità privacy non può ritirare contenuti già inviati ad altre app.

Per altri dettagli: [note di sviluppo](docs/DEVELOPMENT.md).

## Origine e licenza

WhiskyMac è una modifica indipendente di [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) (commit iniziale `1ebcee1e0735e957777c599017ee411d8046c7e7`). Il [progetto originale](https://github.com/nathan-poncet/whisk) è di Nathan Poncet e collaboratori. WhiskyMac è mantenuto da **LinShay (琳曦)**; non è una versione ufficiale di Whisk né implica approvazione da parte degli autori originali.

Il software è distribuito con licenza **GPL-3.0-or-later**, salvo i materiali di terze parti con licenze separate. Conserva la [licenza](LICENSE), la [nota del progetto](NOTICE) e le [informazioni sulle terze parti](THIRD_PARTY_NOTICES.md). Parti originali di Whisk: © 2026 Nathan Poncet e collaboratori. Aggiunte di WhiskyMac: © 2026 LinShay (琳曦), nei limiti dei diritti posseduti.

L'[eccezione originale per App Store/TestFlight](LICENSE-EXCEPTION-APP-STORE.md) è conservata invariata. L'[eccezione separata di LinShay](LICENSE-EXCEPTION-WHISKYMAC.md) copre solo le aggiunte per cui LinShay dispone dei diritti necessari. Distribuire binari richiede il codice sorgente completo corrispondente a quella versione; con queste eccezioni deve restare pubblicamente accessibile. Revisione Apple, firma e diritti di terzi restano requisiti separati. Il marchio Neovim è CC BY 3.0; i suoni inclusi di Kenney UI Audio e Wyzowl SFX Kit sono CC0. Vedi la [verifica delle licenze](docs/LICENSING.md).

## Versioni e sostegno

Le note e i download delle versioni precedenti sono disponibili su [GitHub Releases](https://github.com/LShayc1owN/WhiskyMac/releases). I documenti legali inclusi nell’app si aprono da **Licenze e note legali…** nel menu di WhiskyMac.

Se WhiskyMac ti è utile, puoi sostenere lo sviluppo indipendente con una donazione volontaria:

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

## Altre informazioni

[Ambito del progetto](docs/PROJECT.md) · [Guida allo sviluppo](docs/DEVELOPMENT.md) · [Architettura](docs/ARCHITECTURE.md) · [Registro modifiche](CHANGELOG.md) · [Contributi](CONTRIBUTING.md)
