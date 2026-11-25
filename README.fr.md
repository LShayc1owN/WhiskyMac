<p align="center"><img src="Assets/icon.png" width="112" alt="Icône de WhiskyMac"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Retrouvez facilement ce que vous avez copié.<br>Un gestionnaire de presse-papiers pour macOS 15 et versions ultérieures.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac est un projet indépendant dérivé de [Whisk](https://github.com/nathan-poncet/whisk), toujours en développement. Les fonctionnalités ci-dessous décrivent le code source actuel. Les notes de chaque version précisent les fonctionnalités incluses et le statut de la signature.

## Télécharger et démarrer

**[Dernière version sur GitHub](https://github.com/LShayc1owN/WhiskyMac/releases/latest)**

1. Dans **Assets**, téléchargez le fichier `WhiskyMac-v*.zip`. Décompressez-le, puis déplacez `WhiskyMac.app` dans le dossier Applications.
2. Ouvrez WhiskyMac et suivez le guide de bienvenue. Si l’accès au presse-papiers est requis, faites un clic droit sur l’icône de WhiskyMac dans la barre des menus et choisissez **Autoriser l’accès au presse-papiers…**.
3. Copiez un contenu dans une autre application, puis cliquez sur l’icône de WhiskyMac dans la barre des menus ou choisissez **Afficher l’historique**. Vous pouvez activer un raccourci global dans les réglages.

## En bref

- **Retrouver ses copies.** Le texte, le texte enrichi, le code, les liens, les images, les fichiers et les couleurs sont conservés localement. Recherchez par contenu ou application source, par correspondance approximative, sous-chaîne, mot entier, début ou fin du texte. Filtrez par application, type, épingle, étiquette de couleur ou origine Handoff. Utilisez `type:path` pour retrouver les chemins de fichiers copiés sous forme de texte.
- **Réutiliser les copies.** Prévisualisez, modifiez, glissez, copiez, collez directement ou en texte brut, et utilisez la file de collage. Choisissez parmi les versions de texte enrichi regroupées et naviguez au clavier ou avec les raccourcis Vim facultatifs.
- **Découper le texte.** Découpez le texte par ligne, paragraphe ou séparateur, ou extrayez les liens HTTP(S). Vérifiez les parties avant d’ajouter des cartes, de remplacer l’original ou d’enregistrer un groupe. Au moment de copier ou de coller un groupe, choisissez l’original ou les parties souhaitées.
- **Organiser l’historique.** Épinglez des éléments avec des notes consultables, sept étiquettes de couleur et une option pour toujours masquer le contenu. Ouvrez les épingles dans l’historique ou dans une fenêtre distincte. Masquez temporairement les entrées anciennes selon la date et l’heure, le type de contenu ou l’origine Handoff. Réglez la durée et la capacité de l’historique non épinglé, ou effacez-le avec possibilité d’annuler.
- **Maîtriser l’affichage.** Le mode de confidentialité manuel masque les cartes. La recherche, les filtres et la révélation près du pointeur se règlent séparément. Le menu d’une carte permet aussi de la révéler sur place. La détection facultative du partage d’écran couvre les barres de partage Zoom et Teams prises en charge. Les copies issues d’applications sensibles expirent en mémoire. Les applications exclues sont ignorées.
- **Masquer les secrets probables.** La reconnaissance locale recherche les formats courants de clés API, de jetons, de cookies et d’empreintes. Le masquage des cartes et leur classement dans la catégorie des secrets se règlent séparément. Le masquage agit sur l’affichage des cartes.
- **Adapter l’interface à son Mac.** À partir de macOS 26, les commandes de l’historique et des réglages utilisent Liquid Glass. Sous macOS 15, l’interface utilise un effet de verre dépoli. Choisissez séparément pour l’historique et les réglages un mode clair, sombre ou conforme au système.
- **Personnaliser les commandes.** Ajustez la taille des cartes, l’icône de la barre des menus, les actions, les raccourcis et les sons de copie facultatifs. Recherchez dans les réglages et réinitialisez les raccourcis par catégorie avec possibilité d’annuler. L’interface est disponible en français, anglais, allemand, italien, chinois simplifié, chinois traditionnel et japonais.

Pour les comportements précis et les limites, consultez le [périmètre du projet](docs/PROJECT.md) et le [journal des changements](CHANGELOG.md).

## Confidentialité et données

- L'historique reste dans `~/Library/Application Support/WhiskMay-Dev` avec l'identifiant `dev.whisky.maclx`. Le changement de nom ne déplace ni n'efface les données de développement existantes ; l'historique de Whisk d'origine n'est pas importé automatiquement. `WHISK_MAY_DATA_DIR` permet d'isoler les tests.
- Raccourcis globaux, aperçus de liens, détection du partage et recherche de mises à jour au démarrage sont désactivés par défaut. Les aperçus activés demandent les métadonnées au site copié. Les vérifications manuelles ou activées par l'utilisateur utilisent les versions stables de WhiskyMac sur GitHub ; les versions App Store omettent cette vérification externe.
- Le collage direct et la détection facultative du partage peuvent nécessiter des autorisations macOS. L'attribution Handoff est une indication approximative, sans identification vérifiée de l'appareil ou de l'application. Le mode de confidentialité ne peut pas retirer un contenu déjà transmis à une autre application.

Voir les [notes de développement](docs/DEVELOPMENT.md).

## Origine et licence

WhiskyMac est une modification indépendante de [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) (révision de départ `1ebcee1e0735e957777c599017ee411d8046c7e7`). Le [projet original](https://github.com/nathan-poncet/whisk) est dû à Nathan Poncet et ses contributeurs. WhiskyMac est maintenu par **LinShay (琳曦)** ; ce n'est pas une version officielle de Whisk et cela n'implique aucune approbation de l'équipe d'origine.

Le logiciel est sous **GPL-3.0-or-later**, sauf les éléments tiers sous licence distincte. Conservez la [licence](LICENSE), la [notice du projet](NOTICE) et les [mentions des tiers](THIRD_PARTY_NOTICES.md). Parties de Whisk d'origine : © 2026 Nathan Poncet et contributeurs. Ajouts de WhiskyMac : © 2026 LinShay (琳曦), dans la limite des droits détenus.

L'[autorisation App Store/TestFlight d'origine](LICENSE-EXCEPTION-APP-STORE.md) est conservée telle quelle. L'[autorisation distincte de LinShay](LICENSE-EXCEPTION-WHISKYMAC.md) ne couvre que les ajouts que LinShay est en droit de placer sous licence. La distribution de binaires exige le code source complet correspondant à la version distribuée ; sous ces exceptions, il doit rester publiquement accessible. L'examen par Apple, la signature et les droits des tiers restent des exigences distinctes. La marque Neovim est sous CC BY 3.0 ; les sons fournis de Kenney UI Audio et Wyzowl SFX Kit sont sous CC0. Détails dans la [vérification des licences](docs/LICENSING.md).

## Publications et soutien

Retrouvez les notes et les téléchargements des versions précédentes sur [GitHub Releases](https://github.com/LShayc1owN/WhiskyMac/releases). Les documents juridiques fournis avec l’application s’ouvrent depuis **Licences et mentions légales…** dans le menu de WhiskyMac.

Si WhiskyMac vous est utile, vous pouvez soutenir son développement indépendant par un don volontaire :

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

## En savoir plus

[Périmètre du projet](docs/PROJECT.md) · [Guide de développement](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md) · [Journal des changements](CHANGELOG.md) · [Contributions](CONTRIBUTING.md)
