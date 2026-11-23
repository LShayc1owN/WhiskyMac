<p align="center"><img src="Assets/icon.png" width="112" alt="Icône de WhiskyMac"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Retrouvez facilement ce que vous avez copié.<br>Un gestionnaire de presse-papiers pour macOS 15 et versions ultérieures.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac est une modification indépendante de [Whisk](https://github.com/nathan-poncet/whisk). Ce projet est en cours de développement : le dépôt est privé et aucun téléchargement public de l'application n'est encore configuré. Les instructions ci-dessous concernent la compilation depuis cette copie du projet.

## En bref

- **Retrouver ses copies.** L'historique local conserve texte, texte enrichi, liens, images, fichiers et couleurs. Recherchez dans le contenu ou par application ; filtrez par application, type, épingle, étiquette de couleur ou attribution Handoff. Les chemins de fichiers en texte disposent d'un filtre et de la recherche `type:path`.
- **Réutiliser le contenu.** Copiez, collez directement ou en texte brut, glissez vers une autre application, prévisualisez, modifiez et utilisez la file de collage. Les versions de texte enrichi ayant le même texte brut sont regroupées. La navigation au clavier et le mode Vim sont disponibles.
- **Découper et organiser.** Découpez par ligne, paragraphe ou séparateur, ou extrayez des liens HTTP(S). Vérifiez les parties, puis ajoutez des cartes, remplacez l'original ou créez un groupe persistant. Choisissez l'original ou certaines parties lors de la copie ou du collage.
- **Garder l'essentiel.** Ajoutez aux épingles des notes consultables, sept étiquettes de couleur et un masquage permanent facultatif. Affichez-les dans l'historique ou dans une fenêtre distincte. Réglez la durée et la capacité des éléments non épinglés ; leur effacement est annulable.
- **Maîtriser l'affichage.** Le mode de confidentialité manuel masque le contenu. La détection facultative des barres de partage Zoom/Teams a une portée limitée. Recherche, filtres et révélation près du pointeur s'activent séparément. Les applications sensibles utilisent une session temporaire en mémoire ; les applications exclues ne sont pas enregistrées.
- **Personnaliser.** Modifiez la taille des cartes, l'aspect dépoli, l'icône de la barre des menus, les interactions, les raccourcis et les sons de copie facultatifs. Les réglages sont consultables par recherche et l'annulation suit la réinitialisation des raccourcis. L'exercice du guide initial ne touche pas au vrai presse-papiers ni à l'historique. L'interface existe en anglais, français, allemand, italien, chinois simplifié, chinois traditionnel et japonais.

Pour les comportements précis et les limites, consultez le [périmètre du projet](docs/PROJECT.md) et le [journal des changements](CHANGELOG.md).

## Compiler depuis les sources

Il faut macOS 15 ou plus récent, le SDK macOS 26 et une installation complète de Xcode. Depuis cette copie du projet :

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

Le script produit `dist/WhiskyMac.app` et `dist/WhiskyMac.zip`. La cible Swift et l'exécutable internes conservent le nom `Whisk`. Sans identité de signature, l'application est signée ad hoc ; elle n'est ni notarisée ni prête pour une soumission à l'App Store.

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

Les adresses publiques du code source, de l'assistance et de la politique de confidentialité sont encore vides dans [release-config.json](release-config.json) ; la validation bloque leur publication tant qu'elles ne sont pas renseignées. Les paquets installables devront être distribués via GitHub Releases avec le code source correspondant, et non ajoutés au dépôt. Les textes juridiques inclus dans l'application se trouvent dans `Contents/Resources/Legal`, accessibles depuis **Licences et mentions…** dans la barre des menus.

Si WhiskyMac vous est utile, vous pouvez soutenir son développement indépendant par un don volontaire :

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

## En savoir plus

[Périmètre du projet](docs/PROJECT.md) · [Développement](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md) · [Journal des changements](CHANGELOG.md) · [Contributions](CONTRIBUTING.md)
