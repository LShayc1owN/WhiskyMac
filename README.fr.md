# WhiskyMac

[English](README.md) | [简体中文](README.zh-CN.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

Projet d'origine : [Whisk — nathan-poncet/whisk](https://github.com/nathan-poncet/whisk).

Dépôt : [lshayc1own/WhiskyMac](https://github.com/lshayc1own/WhiskyMac).
Ce dépôt de développement est privé ; la distribution publique de binaires n'est pas encore configurée.

WhiskyMac est un gestionnaire de presse-papiers pour macOS dérivé de
[Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7),
créé par Nathan Poncet et ses contributeurs. Révision de départ :
`1ebcee1e0735e957777c599017ee411d8046c7e7`.
Cette version modifiée indépendante est maintenue par **LinShay (琳曦)**.
Elle n'est pas une version officielle de Whisk et n'implique pas l'approbation de ses auteurs.
Les changements actuels figurent dans [CHANGELOG.md](CHANGELOG.md).

## Fonctionnalités

- Historique local pour texte, texte enrichi, liens, images, fichiers et couleurs ; recherche dans le contenu ou par application source, filtres par application, catégorie, épingles et étiquettes de couleur.
- Copie, collage direct ou en texte brut, glisser-déposer, aperçus, édition du texte, file de collage et navigation Vim facultative. Les formats enrichis ayant le même texte brut sont regroupés.
- Découpage du texte par ligne, paragraphe ou séparateur, et extraction des liens HTTP(S). Les morceaux peuvent devenir de nouvelles cartes, remplacer l'original ou former un groupe persistant ; la copie et le collage permettent de choisir les morceaux.
- Épingles avec notes consultables, sept étiquettes de couleur et masquage permanent facultatif du contenu. Elles s'affichent dans l'historique ou une fenêtre séparée ; durée et capacité de l'historique non épinglé sont réglables, avec annulation après effacement.
- Mode de confidentialité manuel, détection facultative et limitée des barres d'outils de partage, zone de révélation réglable près du pointeur, recherche et filtres facultatifs avec contenu masqué. Les interactions des cartes se règlent séparément selon le mode.
- Applications sensibles : copies temporaires en mémoire qui expirent après la durée choisie. Les applications exclues ne sont jamais enregistrées.
- Capture pouvant être mise en pause, ouverture à la connexion et réglages de la taille des cartes, de l'apparence vitrée, de l'icône de menu, de la langue, des raccourcis et des actions. Recherche dans les réglages et réinitialisation des raccourcis par catégorie avec annulation. Sons de copie facultatifs issus de Kenney UI Audio, SFX Kit et macOS.
- Interface en anglais, français, allemand, italien et chinois simplifié.

Voir les [notes de développement](docs/DEVELOPMENT.md) et le [journal des changements](CHANGELOG.md) pour les détails et limites. Il s'agit encore d'une version de développement.

## Compilation et vérification

macOS 15 ou plus récent et le SDK macOS 26 sont requis. Les tests et la génération des ressources nécessitent une installation complète de Xcode.

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

Le script produit `dist/WhiskyMac.app` et `dist/WhiskyMac.zip`. La cible Swift et l'exécutable internes gardent le nom `Whisk` pour conserver la structure du module et des ressources. Sans identité de signature, la signature est ad hoc : elle ne constitue ni une notarisation ni une admissibilité à l'App Store.

## Données et confidentialité

L'identifiant de l'application est `dev.whisky.maclx`. L'historique de développement reste dans `~/Library/Application Support/WhiskMay-Dev` ; le changement de nom ne le déplace ni ne l'efface. `WHISK_MAY_DATA_DIR` permet d'isoler les tests. L'historique de Whisk d'origine n'est pas importé automatiquement.

Les raccourcis globaux et les aperçus de liens sont désactivés par défaut. Si les aperçus de liens sont activés, l'application demande les métadonnées du site copié. La recherche de mises à jour est désactivée pour cette distribution de développement. Le collage direct et la détection facultative du partage peuvent nécessiter des autorisations macOS. La protection ne peut pas retirer un contenu déjà transmis à une autre application.

## Licence et attributions

Le logiciel est sous **GPL-3.0-or-later**, sauf les éléments tiers assortis de leur propre licence. Conserver [LICENSE](LICENSE), [NOTICE](NOTICE) et les [mentions des tiers](THIRD_PARTY_NOTICES.md).

- Whisk d'origine : © 2026 Nathan Poncet et contributeurs.
- Modifications de WhiskyMac : © 2026 LinShay (琳曦), dans la limite des droits détenus.
- Autorisation supplémentaire de Whisk pour l'App Store et TestFlight : [texte d'origine](LICENSE-EXCEPTION-APP-STORE.md), conservé tel quel.
- Autorisation de LinShay pour ses ajouts autorisés : [texte distinct](LICENSE-EXCEPTION-WHISKYMAC.md).

L'autorisation d'origine couvre explicitement les œuvres basées sur Whisk. Ces textes règlent l'autorisation au titre du droit d'auteur pour ces canaux de distribution ; la validation par Apple, la signature et les droits sur les éléments tiers restent des questions distinctes. La marque Neovim de Jason Long est sous CC BY 3.0 ; les sons Kenney UI Audio et Wyzowl SFX Kit fournis sont sous CC0. Voir les mentions des tiers.

En cas de distribution binaire, fournir le code source complet correspondant à cette version, y compris les modifications, les ressources sous une forme modifiable et les scripts de compilation nécessaires. Un lien vers le seul code source d'origine ne suffit pas. La distribution via l'App Store ou TestFlight au titre de ces exceptions exige que ce code source reste publiquement accessible. Aucun transfert de droits, achat de licence ou « certificat GPL » n'est requis pour maintenir ce dérivé.

## Publication

Le dépôt de développement est privé. Les adresses publiques du code source, de l'assistance et de la politique de confidentialité ne sont pas encore configurées. Renseigner [release-config.json](release-config.json) avant une distribution binaire externe ; les champs vides font échouer la validation. Aucun compte ou site de l'auteur d'origine n'est utilisé comme destination de publication.

Les documents juridiques sont intégrés à `Contents/Resources/Legal`. L'élément **Licences et mentions…** de la barre des menus ouvre Réglages → À propos → Licences et mentions ; cette page permet d'ouvrir le document ou de le révéler dans le Finder. Voir la [vérification des licences](docs/LICENSING.md). Les paquets et comptes rendus locaux sont exclus du dépôt ; les paquets distribuables passent par GitHub Releases.

Contributions : [CONTRIBUTING.md](CONTRIBUTING.md). Architecture : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
