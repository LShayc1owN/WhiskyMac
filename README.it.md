# WhiskyMac

[English](README.md) | [简体中文](README.zh-CN.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

Progetto originale: [Whisk — nathan-poncet/whisk](https://github.com/nathan-poncet/whisk).

Repository: [lshayc1own/WhiskyMac](https://github.com/lshayc1own/WhiskyMac).
Questo repository di sviluppo è privato; la distribuzione pubblica dei binari non è ancora configurata.

WhiskyMac è un gestore degli appunti per macOS derivato da
[Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7)
di Nathan Poncet e collaboratori. Commit di partenza:
`1ebcee1e0735e957777c599017ee411d8046c7e7`.
Questa versione modificata indipendente è mantenuta da **LinShay (琳曦)**.
Non è una versione ufficiale di Whisk e non implica l'approvazione degli autori originali.
Le modifiche attuali sono riportate in [CHANGELOG.md](CHANGELOG.md).

## Funzionalità

- Cronologia locale di testo, testo formattato, link, immagini, file e colori; ricerca nel contenuto o per app di origine e filtri per app, categoria, elementi fissati ed etichette colorate.
- Copia, incolla diretto o come testo semplice, trascinamento, anteprime, modifica del testo, coda di incolla e navigazione Vim facoltativa. I formati ricchi con lo stesso testo semplice vengono raggruppati.
- Divisione del testo per righe, paragrafi o separatori ed estrazione dei link HTTP(S). Le parti possono diventare nuove schede, sostituire l'originale o formare un gruppo persistente; si possono scegliere singole parti durante copia e incolla.
- Elementi fissati con note ricercabili, sette etichette colorate e contenuto sempre nascosto su richiesta. Si possono aprire nella cronologia o in una finestra separata; durata e capienza della cronologia non fissata sono configurabili, con annullamento dopo la cancellazione.
- Modalità privacy manuale, rilevamento facoltativo e limitato delle barre di condivisione, area di visualizzazione regolabile vicino al puntatore, ricerca e filtri facoltativi mantenendo il contenuto oscurato. Le azioni sulle schede si configurano separatamente per le due modalità.
- App sensibili: copie temporanee in memoria che scadono dopo un intervallo configurabile. Le app escluse non vengono registrate.
- Acquisizione sospendibile, avvio all'accesso e dimensione delle schede, aspetto vetro, icona di menu, lingua, scorciatoie e azioni personalizzabili. Ricerca nelle impostazioni e ripristino delle scorciatoie per categoria con annullamento. Suoni di copia facoltativi da Kenney UI Audio, SFX Kit e macOS.
- Interfaccia in inglese, francese, tedesco, italiano e cinese semplificato.

Per dettagli e limiti, consultare le [note di sviluppo](docs/DEVELOPMENT.md) e il [registro modifiche](CHANGELOG.md). Il software è ancora una versione di sviluppo.

## Compilazione e verifica

Servono macOS 15 o successivo e l'SDK macOS 26. I test e la generazione delle risorse richiedono l'installazione completa di Xcode.

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

Lo script crea `dist/WhiskyMac.app` e `dist/WhiskyMac.zip`. Il target Swift e l'eseguibile interni conservano il nome `Whisk` per mantenere la struttura dei moduli e delle risorse. Senza un'identità di firma, l'app viene firmata ad hoc: questo non costituisce notarizzazione né idoneità per l'App Store.

## Dati e privacy

L'ID del bundle è `dev.whisky.maclx`. La cronologia di sviluppo esistente rimane in `~/Library/Application Support/WhiskMay-Dev`; il nuovo nome non la sposta né la elimina. `WHISK_MAY_DATA_DIR` consente di isolare i test. La cronologia del progetto Whisk originale non viene importata automaticamente.

Le scorciatoie globali e le anteprime dei link sono inizialmente disattivate. Attivando le anteprime, l'app richiede metadati al sito copiato. Il controllo degli aggiornamenti è disattivato per questa distribuzione di sviluppo. L'incolla diretto e il rilevamento facoltativo della condivisione possono richiedere permessi macOS. La protezione privacy non può richiamare contenuti già inviati ad altre app.

## Licenza e attribuzioni

Il software è distribuito con licenza **GPL-3.0-or-later**, salvo i materiali di terze parti con licenza separata. Conservare [LICENSE](LICENSE), [NOTICE](NOTICE) e le [informazioni sulle terze parti](THIRD_PARTY_NOTICES.md).

- Whisk originale: © 2026 Nathan Poncet e collaboratori.
- Modifiche WhiskyMac: © 2026 LinShay (琳曦), nei limiti dei diritti posseduti.
- Autorizzazione aggiuntiva originale per App Store e TestFlight: [testo originale](LICENSE-EXCEPTION-APP-STORE.md), conservato invariato.
- Autorizzazione di LinShay per le aggiunte di cui può disporre: [testo separato](LICENSE-EXCEPTION-WHISKYMAC.md).

L'eccezione originale include esplicitamente le opere derivate da Whisk. Queste autorizzazioni riguardano il diritto d'autore per tali canali di distribuzione; la revisione Apple, la firma e i diritti sui materiali di terzi restano questioni distinte. Il marchio Neovim di Jason Long è CC BY 3.0; i suoni inclusi di Kenney UI Audio e Wyzowl SFX Kit sono CC0. Consultare le informazioni sulle terze parti.

Quando si distribuiscono binari, occorre fornire il codice sorgente completo corrispondente a quella versione, comprese le modifiche, le risorse in forma modificabile e gli script di compilazione necessari. Un collegamento al solo codice originale non basta. La distribuzione su App Store o TestFlight con queste eccezioni richiede che il codice corrispondente resti accessibile pubblicamente. Per mantenere questo progetto derivato non servono cessione del copyright, licenze a pagamento o un «certificato GPL».

## Pubblicazione

Il repository di sviluppo è privato. Gli indirizzi pubblici del codice sorgente, dell'assistenza e dell'informativa sulla privacy non sono ancora configurati. Compilare [release-config.json](release-config.json) prima di distribuire binari all'esterno; i campi vuoti bloccano la verifica di rilascio. Questo progetto non usa account o siti dell'autore originale come destinazione di pubblicazione.

I documenti legali vengono copiati in `Contents/Resources/Legal`. La voce **Licenze e avvisi…** della barra dei menu apre Impostazioni → Informazioni → Licenze e avvisi, dove si può aprire il file o mostrarlo nel Finder. Vedere la [verifica delle licenze](docs/LICENSING.md). Pacchetti e verbali locali sono esclusi dal repository; i pacchetti installabili sono distribuiti tramite GitHub Releases.

Contributi: [CONTRIBUTING.md](CONTRIBUTING.md). Architettura: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
