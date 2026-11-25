# Architecture

WhiskyMac est une application Swift qui suit la Clean Architecture :
les entités et les use cases seuls au centre de l'oignon, un ring
d'interface adapters complet autour d'eux (controllers, presenters,
gateways), et les frameworks tout au bord. Les rings vivent comme des
dossiers dans un module unique ; la Dependency Rule est appliquée par
`scripts/check-dependency-rule.sh`, exécuté par la CI à chaque push — les
rings intérieurs ne peuvent importer que ce que leur ring autorise, les
flèches pointent uniquement vers l'intérieur.
Le périmètre actuel et les priorités de maintenance figurent dans [PROJECT.md](../PROJECT.md).

## La carte

```
Sources/Whisk/
├── Entities/               History · ClipboardItem · Payload · BinaryContent · SplitContent · PinnedMetadata
├── UseCases/               CaptureClipboardChange · SelectItem · FilterHistory ·
│   └── Ports/              TogglePin · DeleteItem · ClearHistory · LoadHistory · EnforceRetention
│                           Pasteboard · HistoryStore · SharingDetector · Clock · Logger  (Foundation seulement)
├── Adapters/
│   ├── Controllers/        ClipboardController                     (Foundation seulement)
│   ├── Presenters/         HistoryPresenter · HistoryViewState     (Foundation seulement)
│   └── Gateways/           SQLiteHistoryStore · LegacyJSONHistory · VolatileHistoryStore ·
│                           AppKitPasteboard · ConsoleLogger        (Foundation + AppKit + SQLite3 + CryptoKit)
├── Components/             vues et modificateurs SwiftUI réutilisables dans l'application
└── App/                    frameworks & drivers + racine de composition (tout est permis)
    ├── Composition/        AppIdentity · Distribution · AppUISelector · PanelWiring
    ├── Panel/              PanelController · PanelKeyRouter · PanelActions ·
    │                       HistoryViewStateStore · HotKey · SplitSession
    ├── Settings/           AppearanceSettings · GeneralSettings · SettingsPage ·
    │                       KeyBindings · VimBindings · LegalDocuments
    ├── Privacy/            PrivacyController · SensitiveSessionStore · SharingMonitor
    ├── StatusMenu/         StatusBarSymbol · SymbolCatalog
    ├── Infrastructure/     HistoryStorage · SystemClock · CopySound · UpdateChecker · Debouncer
    ├── Presentation/       Fenêtre visible, guide et services d’aperçu communs
    ├── UI/
    │   ├── Contracts/      AppUIFactory · AppWindowHandle · PanelLayout
    │   ├── Shared/         Ressources de symboles et données d’accessibilité
    │   ├── MacOS15/        Settings · Clipboard · Preview · Onboarding · Styling
    │   └── MacOS26/        Settings · Clipboard · Preview · Onboarding · Styling
    └── …                   AppDelegate · WhiskyMacMain
```

## Les rings

1. **Noyau (entités + use cases).** `Entities/` et `UseCases/` avec ses
   `UseCases/Ports/` n'importent que Foundation — jamais AppKit, jamais
   SwiftUI. Les ports sont des protocoles aux noms de rôle (`Pasteboard`,
   `HistoryStore`, `Clock`, `Logger`), un fichier par port, chacun
   possédant son type d'erreur. Les use cases sont génériques sur leurs
   ports et restent synchrones et purs ; le temps entre par `Clock`.
2. **Interface adapters.**
   - *Controllers* : traduisent les événements UI et OS en invocations de
     use cases. `ClipboardController` reçoit les gateways, construit les
     use cases, possède l'`History` courant, la requête de recherche et la
     sélection clavier, et signale les échecs de stockage au `Logger` sans
     tuer la session.
     `pollTick` ne soumet qu'une lecture du presse-papiers à la fois, avec
     retour par callback. Une session en pause consomme les changements sans
     les enregistrer. Les tests utilisent ce même chemin avec des ports
     scriptés ou différés.
   - *Presenters* : transformation pure entités → view state.
     `HistoryPresenter` décide chaque chaîne et symbole d'affichage (labels
     de type, temps relatifs, phrase de l'état vide, icônes des puces,
     détection de couleurs hex, troncature des listes de fichiers) et émet
     un `HistoryViewState` que les vues rendent tel quel. Il ne lit jamais
     l'horloge système — `now` est un argument. `ChipEntry.row` décide une
     seule fois l'ordre des puces de filtre ; le controller pilote le
     clavier le long de cette même liste.
   - *Gateways* : implémentent les ports du noyau. `SQLiteHistoryStore`
     possède le schéma de production ; `LegacyJSONHistory` lit l'index
     JSON d'avant SQLite pour l'import unique ; `VolatileHistoryStore`
     garde une session vivante quand aucune base ne peut s'ouvrir ;
     `AppKitPasteboard` possède la frontière NSPasteboard ;
     `ConsoleLogger` écrit dans le journal unifié. C'est le seul dossier
     du ring autorisé à importer AppKit.
     SQLite utilise CryptoKit pour identifier les révisions immuables des
     images et du RTF. Les listes portent des références `BinaryContent` ;
     les chargements complets et les opérations explicites lisent les octets.
3. **Frameworks & drivers (`Components/` et `App/`).** `Components/` contient
   les petits éléments SwiftUI réutilisables réellement employés par
   l'application. Les packages privés PetaToolKit et PetaKitUIX ne sont pas
   des dépendances. `App/` contient la racine de composition et tout ce
   qui a la forme d'un framework : vues SwiftUI (rendus muets du
   `HistoryViewState`), le `NSPanel` flottant, l'icône de barre de menus,
   le `Timer` de polling, le raccourci Carbon, la simulation de collage.
   `HistoryStorage` ouvre la base, la lit une fois avant de lui faire
   confiance, met de côté une base illisible, se replie sur la mémoire,
   importe l'historique legacy et transmet la liste validée au controller
   sans la relire. `PanelActions` définit les actions des vues et leur garde
   de confidentialité dans son propre fichier ; `HistoryViewStateStore`
   possède l'état observable et les brouillons. Deux autres morceaux portent
   des règles et restent testables séparément :
   `PanelWiring` construit la table d'actions du panneau (quelles actions
   vident le debounce de recherche, lesquelles ferment et collent), et
   `PanelKeyRouter` transforme les touches en actions — mode normal de
   vim, raccourcis de l'utilisateur, ⌘chiffres. `AppDelegate` assemble les
   dépendances et les cycles de vie. Les files de travail et tâches des
   frameworks vivent dans les gateways et le ring externe. Le controller
   coordonne les callbacks via son port Foundation ; les mutations du noyau
   restent synchrones.

## Générations de l’interface

`WhiskyMacMain` appelle `AppUISelector.make()` une fois sur l’acteur principal
et injecte la fabrique dans `AppDelegate`. Le delegate transmet la même
instance à `PanelController`. Chaque fabrique possède ses vues SwiftUI, ses
styles et ses règles de disposition. Les poignées de fenêtre conservent
les barres d’outils et appliquent la taille avant l’affichage.

Le clavier, le cycle de vie, les données, les actions, la protection et
les services d’aperçu restent communs. Un seul target SwiftPM `Whisk` contient
les deux arborescences. Le contrôle de dépendances de la CI appelle
`scripts/check-ui-boundaries.py` pour vérifier l’isolation des sources et
la sélection au démarrage. L’option `--self-test` vérifie les cas valides
et invalides du script.

## Invariants

- **Newtypes plutôt que primitives ; états illégaux irreprésentables.**
  `HistoryCapacity` rejette zéro à la construction ; `SourceApp` garantit
  au moins un champ identifiant ; `History` fait respecter son invariant
  d'éviction dans chaque mutation.
- **Fail closed.** Aucun force-unwrap dans les chemins de production. Un
  échec de stockage est journalisé et l'historique en mémoire continue de
  fonctionner ; une entrée persistée corrompue est ignorée, jamais
  fatale ; une base qui ne s'ouvre pas est mise de côté et la session
  tourne en mémoire plutôt que de refuser de démarrer.
- **Le contenu opaque est différé.** La capture transporte d'abord des `Data` ;
  l'historique persisté, l'annulation et le view state portent des références
  immuables `BinaryContent` / `StoredBytes`. Les filtres, regroupements et listes
  ne chargent pas les originaux. Les aperçus montés et exports explicites les
  lisent à la demande. Le gateway presse-papiers normalise le PNG ; SQLite
  possède le schéma, vérifie les octets et fixe les dates à la milliseconde.
- **Les durées de rétention sont bornées.** La fermeture du panneau et les
  changements de confidentialité invalident les requêtes et libèrent les caches.
  Les sessions sensibles restent séparées de l'historique, de SQLite, de
  l'annulation et des aperçus. Les points d'observation des caches et de la
  libération des hôtes utilisés par les tests sont intentionnels.

## Tests

Une seule cible `WhiskTests` (`@testable import Whisk`) avec les doublures
déterministes dans `Fakes.swift` : `FakeClock`, `InMemoryHistoryStore`,
`FailingHistoryStore`, `SaveFailingHistoryStore`, `ScriptedPasteboard`,
`RecordingLogger`. Les noms de tests énoncent un comportement
(`a_storage_failure_is_logged_and_the_presented_state_stays_alive`).

- **Noyau et adaptateurs** sont couverts ligne à ligne : le comportement
  de l'historique, chaque use case, la navigation et les facettes du
  controller, les chaînes, icônes et libellés VoiceOver du presenter. Le
  contrat `HistoryStore` est une seule suite paramétrée, exécutée contre
  chaque gateway (SQLite, mémoire) dans un répertoire temporaire neuf par
  test ; une connexion brute sabote le schéma pour atteindre chaque chemin
  d'erreur. Le lecteur JSON legacy est testé contre une fixture de son
  format sur disque, le bootstrap de stockage contre des répertoires
  corrompus, dérivés ou legacy, le gateway presse-papiers contre un
  presse-papiers privé, les catalogues de chaînes contre le code qui les
  lit.
- **Le ring des frameworks est testé sans écran.** Les vues sont dessinées
  hors écran avec `ImageRenderer` dans chaque état possible, et hébergées
  dans une fenêtre jamais affichée pour que le flou derrière la fenêtre
  reçoive un layer et une passe de layout ; le panneau reçoit des
  changements d'état et un tour de run loop pour que ses observateurs
  s'exécutent. Le routage clavier est piloté par des `NSEvent`
  synthétiques, le debouncer par un ordonnanceur à manivelle, la
  vérification de mise à jour par des réponses en conserve, QuickLook et
  LinkPresentation en attendant leurs valeurs publiées. Un test n'affiche
  jamais de fenêtre.
- **Hors de la suite, à dessein :** `AppDelegate` (icône de menu,
  raccourcis globaux, timers — la racine de composition que le smoke test
  de release couvre), `HotKey` (en enregistrer un détournerait le
  raccourci du testeur), `PasteSimulator` (envoie ⌘V à l'app au premier
  plan), `main`, et les parties de `PanelController` qui affichent des
  fenêtres. `scripts/coverage.sh` exécute la suite avec la couverture et
  affiche le rapport que la CI archive.
