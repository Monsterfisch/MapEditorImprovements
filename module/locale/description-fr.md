# Map Editor Improvements

**Auteurs** : Monsterfish, Heroesflorian
**Version** : 1.0.63

Enrichit l'éditeur de cartes avec davantage d'informations sur la carte en cours et des outils qui lui manquaient : stades de croissance des arbres, pommiers, buissons supplémentaires, arbres abattus, gravier et fer, variantes de rochers, taille des troupeaux, etc. Chaque fonctionnalité peut être désactivée séparément dans les paramètres.

## Compteurs de la carte

Dans l'éditeur de paysage :

- **Infobulles sur les boutons de catégories.** Survolez un bouton pour afficher le total actuel face à la limite du jeu :
  - **Animaux :** animaux et unités face à la limite réelle (2499, ou 9999 dans Extreme), troupeaux et groupes — chaque troupeau et chaque groupe d'unités occupe un emplacement sur une limite propre de 1249 — ainsi que les oiseaux : corbeaux (repères sur les arbres, sans limite dédiée) et mouettes (99 au maximum).
  - **Végétation :** arbres et buissons. Toutes les plantes partagent une limite de 1999.
  - **Rochers :** rochers.
- **Menu Animaux :** les boutons cerf, chameau, lapin et lion affichent chacun le nombre d'animaux présents sur la carte.
- **Menu Végétation :** chaque bouton d'arbre et de buisson affiche le nombre d'exemplaires présents sur la carte.

Un bouton **« i »** rouge se trouve au-dessus du bouton clé. Cliquez dessus pour tout masquer, puis de nouveau pour tout réafficher. Les paramètres définissent son état initial. La ligne de description des boutons se décale légèrement vers la droite pour lui laisser la place.

## Arbres et buissons

Les arbres du menu Végétation sont classés selon le terrain sur lequel ils se propagent : d'abord les trois qui se propagent sur sol fertile (herbe d'oasis, broussailles épaisses et fines) entourés d'un fin contour vert, puis celui qui se propage sur sol aride (terre, terre pierreuse, dunes) avec un fin contour beige.

- **Stade de croissance selon la taille du pinceau.** Quand un arbre est choisi, la taille du pinceau détermine sa taille :

  | Pinceau | Arbre |
  |---|---|
  | 1 à 3 | jeunes arbres, du plus petit au plus grand |
  | 4 | adulte (ce que l'éditeur plaçait toujours) |
  | 5 | adulte ; les bûcherons le laissent tranquille jusqu'à ce qu'il redevienne un arbre normal |
  | 6 | arbre mort |
  | 7 | arbre mort qui disparaît plus vite |

  Les buissons restent toujours identiques.
- **Bouton Pommier** dans le menu Végétation (nommé sur la ligne de description comme les autres plantes : « Apple tree », ou « Apfelbaum » en allemand).
- **Plus de buissons.** Lorsque le buisson à cinq couleurs est choisi, une rangée au-dessus du menu Végétation propose les cinq teintes.
- **Arbres abattus.** Lorsqu'un arbre est choisi, une rangée au-dessus du menu Végétation le montre debout puis abattu pour chaque nombre de rondins possible : de 9 à 1 pour un arbre adulte, moins pour les plus petits, aucun pour les arbres morts (les plus petits arbres tombent avec 1 rondin, comme le stade suivant). Cliquez sur l'un d'eux pour placer des arbres abattus avec ce nombre de rondins ; cliquez de nouveau dessus, sur l'arbre debout ou dans le menu pour revenir aux arbres debout.
- **Mélanges aléatoires.** Les rangées au-dessus du menu Végétation reçoivent des boutons marqués « ? » :
  - **Arbre aléatoire**, premier de la rangée des arbres abattus : chaque arbre posé reçoit un stade de croissance aléatoire du plus petit jusqu'à celui du pinceau (absent pour le pinceau 1 et les arbres morts).
  - **Arbre abattu aléatoire**, dernier de la rangée des arbres abattus : arbres abattus avec un nombre aléatoire de rondins (de 1 au maximum de cet arbre).
  - **Buisson aléatoire**, dernier de la rangée des buissons : mélange aléatoire des cinq couleurs.

  Cliquez de nouveau ou sélectionnez un autre bouton pour arrêter le mélange.
- **Arbres près des obstacles.** Case à cocher à droite de la rangée du haut. Cochée, les arbres peuvent être posés juste à côté des bâtiments, rochers, murs et autres arbres (les buissons y sont déjà autorisés). Survolez-la pour voir son état.
- **Rangées ordonnées.** La rangée du haut regroupe les arbres (avec le pommier et la case à cocher) ; le buisson qui y figurait passe en bas avec les autres buissons triés.
- **Aperçu d'arbre.** Lorsqu'un arbre ou buisson est choisi, il s'affiche sur la case sous la souris au stade du pinceau ou abattu avec ses rondins — y compris pour la pipette. Invisible en vue dézoomée ou là où la plantation est impossible ; reste visible menu masqué (Tab).
- **Pas d'empilement de buissons.** Un arbre ou un buisson ne peut plus être posé sur une case déjà occupée. Certains buissons s'empilaient auparavant de manière invisible tout en consommant la limite d'arbres ; la gomme supprime désormais tous les buissons empilés sur une case.

La rangée au-dessus du menu Végétation se trouve au-dessus de la carte : cliquer dessus ne place rien sur la carte.

## Textures de terrain

Le menu Textures gagne **Gravier** au bout de la rangée du haut et **Fer** au bout de la rangée du bas (le même fer que dans le menu Reliefs, qui garde aussi son bouton). Les deux rangées sont réparties uniformément.

Une fois le fer présent dans le menu Textures, le bouton Fer du menu Reliefs disparaît (paramètre).

**Masque.** Bouton (carré à moitié rempli) en haut à gauche du menu de l'éditeur de paysage. Actif, les outils naturels (reliefs, textures, eau, arbres et buissons, rochers et pipette) ne modifient que les cases ayant la même texture que la première case cliquée, afin de peindre un type de sol sans déborder. Relâcher la souris permet au clic suivant de choisir une nouvelle texture cible.

## Eau

Le menu Eau retrouve deux décorations de rivière de l'éditeur du premier Stronghold, toujours prises en charge par Crusader mais sans bouton :

- **Écume** : eau vive et embruns comme sous une cascade, sur chaque case de rivière sous le pinceau. Peut aussi être posée sur l'océan, qui devient alors rivière avec écume (paramètre).
- **Petites vagues** : sur l'unique case de rivière sous la souris.

Les deux ne s'appliquent qu'aux rivières et sont enregistrées dans la carte (voir `docs/river-decorations.md` dans le dépôt du module).

## Rochers

- **Panneau indicateur sur les cartes d'escarmouche.** Elles obtiennent le même menu Rochers que les cartes de scénario, avec le panneau indicateur.
- **Rotation aléatoire dans l'aperçu.** Le rocher tourne une fois par seconde au lieu de chaque image, afin que l'aperçu montre exactement le rocher qui sera posé.
- **Rangée de variantes.** Affiche au-dessus du menu Rochers les quatre variantes de la taille choisie, dans l'orientation de pose (rotation aléatoire incluse). Cliquez sur une variante pour la verrouiller ; recliquez ou choisissez un bouton du menu Rochers pour revenir à l'alternance.
- **Rochers invisibles.** Case à cocher à droite du menu Rochers. Cochée, chaque rocher posé est immédiatement invisible (astuce des « 2k pierres ») sans devoir en poser 4000 : les cases sont bloquées mais aucun rocher n'est dessiné, laissant voir le terrain précédent. Décochez pour poser des rochers normaux. Sauvegardés dans la carte comme ceux générés après 4000 rochers.
- **Effacer les rochers invisibles.** La gomme du paysage efface aussi les rochers invisibles et libère chaque case touchée, sans plus avoir besoin de l'astuce du buisson.
- **Petit rocher supplémentaire.** Une cinquième variante pour les plus petits rochers, présente dans le jeu mais jamais placée par l'éditeur d'origine, sauvegardée comme les autres.
- **Supprimer les rochers perdus.** Bouton en bas à droite du menu Rochers retirant les rochers brisés par élever/abaisser puis entièrement recouverts de buissons, qui occupaient chacun l'un des 4000 emplacements sans aucune case restante ; son infobulle indique leur nombre.

## Reliefs

- **Hauteur maximale.** Restaure l'outil du premier Stronghold à droite de Hauteur minimale : met le terrain sous le pinceau à 156.
- **Options des outils de relief.** Panneau au-dessus du menu Reliefs (de bas en haut) :
  - **Réinitialiser les textures du sol** (désactivé au départ) : remet ou non le sol à sa texture simple (et les plateaux en terre). Désactivé, seule la hauteur change.
  - **Briser les cases de rochers** (désactivé au départ) : indique si élever, abaisser, égaliser, colline et montagne brisent les rochers touchés (cases invisibles et franchissables). Désactivé, les rochers restent intacts.
  - **Ignorer l'eau** et **Ignorer les terres fertiles** (désactivés au départ) : laisse intacts mer, rivière, gué, marais et douves, ou broussailles, broussailles épaisses et herbe d'oasis.
  - Pour élever, abaisser et égaliser : **Ajuster à la plage** (activé au départ ; désactivé, les cases hors plage sont laissées intactes), **Inverser** (égaliser uniquement : rend le sol accidenté et ajoute des bosses aléatoires sur terrain plat ; maintenir Ctrl fait de même, paramétrable), **plage de hauteur** (curseur double, 8 à 156 au départ, de 0 à 255) et **force** (amplitude par étape ; 7 correspond au rythme du jeu pour égaliser). Faites glisser les curseurs.
  - **Changement de hauteur des rochers** (liste, Rocher entier au départ) : *Case seule* ne bouge que les cases sous le pinceau, *Rocher entier* déplace toutes les cases du rocher ensemble, *Effacer le rocher* supprime le rocher (comme Hauteur minimale).
  La plage, Ajuster à la plage, Inverser et les exclusions reviennent par défaut en quittant l'éditeur. Élever et abaisser ne bouclent plus aux hauteurs extrêmes.

## Mode château

Dans le menu de construction du mode château de l'éditeur de cartes :

- **Compteurs de bâtiments** au-dessus de la minicarte :
  - tous les bâtiments sur la carte face à la limite du jeu (y compris donjons, bâtiments de décor et sous-éléments) ;
  - tous les bâtiments de joueurs réunis ;
  - les bâtiments du joueur sélectionné.

  Les bâtiments de joueurs sont ceux qu'un ennemi peut être envoyé détruire.
- **Ruines de tours.** Quand le menu Tours est ouvert, une rangée au-dessus propose les ruines des cinq tours.
- **Entrée de tunnel et tentes de siège.** Dans les bâtiments militaires : entrée de tunnel avec la guilde des tunneliers, les six tentes de siège avec la guilde des ingénieurs.
- **Statue et sanctuaires.** La statue 2×2, le sanctuaire 2×2 et le sanctuaire 1×1 inutilisés, à la fin de leurs variantes ou (si les variantes sont désactivées) au-dessus du menu des bons éléments.
- **Variantes de bâtiments.** Pour un jardin (2×2, 3×3, 4×4), une statue, un sanctuaire, une fosse d'aisances ou une masure, une rangée au-dessus du menu affiche toutes les variantes ; celle choisie reste fixe au lieu de défiler chaque seconde. Revenir dans le menu rétablit le défilement.
- **Plusieurs donjons.** Poser un donjon ne supprime plus l'ancien (ni son feu de camp). Le plus récent est actif ; les autres restent en tant que bâtiments.
- **Plusieurs bâtiments de stockage et de recrutement.** Casernes, camps de mercenaires, guildes et autres bâtiments uniques ne sont plus supprimés lors d'un nouveau placement, et réserves, greniers et armureries supplémentaires peuvent être placés n'importe où et rester vides en nombre illimité (contre 8 greniers/armureries vides et 32 réserves vides par joueur auparavant).
- **Mangonneaux et balistes de tour partout.** Peuvent être placés sur toute case libre sans unité (sol, murs, portes, toute tour, donjon). Sur les tours carrées et rondes du joueur ils fonctionnent comme avant.
- **Donjon sans feu de camp ni réserve.** Propose **Donjon seul** (donjon et entrée) et **Sans réserve** (donjon, entrée et feu de camp) avec aperçu et contrôle d'espace adaptés.
- **Murs endommagés.** Propose **Endommagé** pour escaliers, mur bas, mur haut et créneaux, en gardant leur hauteur.
- **Cathédrale en ruine.** Propose **Ruine** (visuel de la mission « Kerak »). En partie elle reste pleinement fonctionnelle. La pipette conserve cet état. Nécessite `gm/tile_churches.gm1` d'origine (les versions anciennes ou remplacées sans ruine posent une cathédrale intacte).
- **Douves creusées, prévues et permanentes.** Au-dessus du menu des portes : **Creusées**, **Prévues** (à creuser comme en jeu) et **Permanentes** (impossibles à combler ou effacer en jeu).
- **Douves sur marais.** Le marais reste dessous et réapparaît si les douves sont comblées.
- **Retirer les douves conserve le sol.** Ne touche qu'aux cases de douves creusées ou prévues et préserve la texture du sol au lieu de la changer en terre nue.
- **Noms de bâtiments plus à gauche.** Décalés de 100 pixels à gauche pour dégager les compteurs.
- **Barrière.** Bouton Barrière 1×1 supprimable dans l'emplacement libre en bas à droite du menu Ruines.

## Troupeaux

Avec cerf, lion, lapin ou chameau sélectionné, un panneau au-dessus du menu Animaux indique la taille du troupeau (part fixe + part aléatoire) et son comportement de groupe. Cocher sa case fixe la taille selon le pinceau : 2 × taille du pinceau − 1 animaux (1 seul animal au pinceau 1, troupeaux de 13 au pinceau 7).

Boutons corbeille rouges dans le menu Animaux : à droite des corbeaux **Effacer tous les corbeaux** (les arbres restent), à droite des mouettes **Effacer toutes les mouettes**, et à droite **Effacer tous les animaux** (comme Alt + E ; les oiseaux restent).

S'il reste moins de 200 troupeaux et groupes disponibles, une ligne en haut de l'écran l'indique comme pour les unités.

## Gomme

La gomme supprime aussi les mouettes au-dessus des cases gommées. Un panneau au-dessus du menu choisit ce qu'elle efface :

- **Tout** – tout, comme avant.
- **Animaux** – animaux, corbeaux (les arbres restent) et mouettes.
- **Unités** – toutes les autres unités.
- **Bâtiments** – bâtiments, donjons, ruines et murs.
- **Végétation** – arbres et buissons.
- **Rochers** – rochers, y compris les rochers invisibles.

## Paramètres de la carte

- **Afficher les cartes verrouillées :** case dans la fenêtre Charger de l'éditeur pour afficher aussi les cartes verrouillées (masquées par le jeu).
- **Bouton Paramètres de la carte** sur l'écran de menu de la carte (avec Sauvegarder et Quitter), à droite d'Équilibrée/Déséquilibrée ou Invasion/Économie. Ouvre le menu Alt + ,.
- **Menu Paramètres de la carte étendu :** titre, Solo et Multijoueur ; en Solo, Siège, Invasion, Économique et Construction libre ; en Multijoueur, tailles 160, 200, 300, 400 et Personnalisée plus curseur de 10 à 400 (appliqué au relâchement) ; Équilibrée et Roi de la colline ; Verrouiller la carte ; Retour (Échap et Alt + , le ferment aussi). Tout cela existait déjà dans le code du jeu ; seuls les boutons avaient été retirés. Verrouiller la carte applique le verrou « Mission » qui garde la carte dans la liste d'escarmouche tout en la masquant dans Charger sauf si « Afficher les cartes verrouillées » est coché.

## Images

Les boutons Pommier et Gravier utilisent les images du dossier `images` du module : `apple.png`, `apple_hover.png`, `apple_selected.png` et `gravel.png`, `gravel_hover.png`, `gravel_selected.png` (normal, survolé, sélectionné). Remplacez-les pour personnaliser les boutons.

## Pinceaux

Les pinceaux du jeu comptent deux fois la case sous la souris et omettent le coin supérieur gauche à l'écran, dans l'aperçu comme au placement. Avec cette option, chaque pinceau a sa forme complète.

## Annuler et rétablir

Deux boutons fléchés en haut à gauche de l'éditeur de cartes (menus paysage et château) : gauche annule la dernière action (bâtiments, arbres, rochers, animaux, textures, eau, reliefs), droite la rétablit. Grisé quand rien n'est disponible. Jusqu'à 20 étapes conservées. Chaque clic compte pour une étape, et un trait maintenu s'annule en une fois. Les clics sans effet ne créent pas d'étape. Une nouvelle action après annulation efface les rétablissements possibles ; charger une autre carte remet l'historique à zéro.

## Pipette

Bouton pipette dans la colonne gauche de l'éditeur de paysage, au-dessus de la taille du pinceau. En le choisissant, une rangée s'affiche au-dessus du menu — **Reliefs**, **Textures**, **Objets**, **Tout** — ainsi qu'une ligne indiquant ce que tient la pipette.

- **Prélever :** cliquez sur une case (la pipette affiche une seule case).
- **Appliquer :** cliquez ou glissez pour appliquer hauteurs, textures ou les deux sous le pinceau. Reliefs laisse la texture intacte et Textures laisse les hauteurs intactes.
- **Objets :** cliquez sur un bâtiment, mur, arbre ou rocher pour le prélever. Bâtiments et murs se placent comme via leur bouton de menu (avec aperçu et vérifications) pour leur joueur d'origine (son écusson est sélectionné) ; arbres (même type et stade, ou abattu avec ses rondins) et rochers (même type et rotation) comme avec leurs outils, clic ou glisser compris. Pinceau, rotation des rochers et choix d'arbre abattu sont restaurés une fois la pipette quittée. Le stade d'arbre suit l'option « La taille du pinceau définit le stade de croissance ».
- **Tout** prélève aussi un arbre ou rocher 1×1 et en pose un sur chaque case libre sous le pinceau.
- Les hauteurs ne s'appliquent pas à mer, plage, marais, douves, rochers, murs ou bâtiments ; les textures non plus aux rochers, murs ou bâtiments. Les rochers de falaise sur pentes raides sont nettoyés puis recréés là où la pente reste raide. Maintenir **Alt** force l'application sur toutes les cases (les rochers restent ; expérimental).
- Resélectionner la pipette ou un de ses modes la vide. **P** sélectionne la pipette et passe au mode suivant. Maintenir **Ctrl** prélève une nouvelle case alors que la pipette contient déjà quelque chose ; relâcher réapplique. Les trois touches sont modifiables ou désactivables.
- Annuler défait les actions de pipette comme toute autre modification.

## Toujours garder le menu à jour

Le jeu ne redessine le menu de l'éditeur que lorsque la souris est dessus. Si un état change pendant que la souris est sur la carte (raccourci clavier, compteurs d'animaux), le menu reste figé jusqu'au retour de la souris. Avec ce paramètre, le menu est redessiné en permanence dans l'éditeur de cartes, sans effet hors de l'éditeur.

## Bon à savoir

- Fonctionne avec Stronghold Crusader et Stronghold Crusader Extreme. Les limites sont lues directement depuis le jeu, donc Extreme affiche sa propre limite d'unités plus élevée.
- Arbres, buissons et rochers sont comptés selon les emplacements qu'ils occupent dans les listes du jeu, qui déterminent les limites. Un empilement de buissons sur une case compte chaque buisson individuellement.
- Rien n'est enregistré en plus dans la carte.
