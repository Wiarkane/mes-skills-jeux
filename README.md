# Roguelike (Godot)

Un petit roguelike au tour par tour pour Godot 4 : chaque partie a un donjon différent,
et si vous mourez, vous recommencez au début.

## Lancer le jeu

1. Installez Godot 4 (version 4.5 ou plus récente) : https://godotengine.org/download
2. Ouvrez Godot, cliquez sur **Importer**, choisissez le fichier `project.godot` de ce dossier.
3. Appuyez sur **F5** (ou le bouton ▶ en haut à droite) pour jouer.

## Commandes

| Touche | Action |
|---|---|
| Flèches, ZQSD (ou WASD) | Se déplacer. Marcher sur un monstre l'attaque. |
| Pavé numérique (1-9) | Se déplacer, y compris en diagonale |
| Maj (Shift) + direction | Courir |
| Espace ou 5 | Attendre un tour |
| E | Boire une potion de soin |
| Molette, + ou - | Zoomer ou dézoomer |
| Entrée | Descendre l'escalier `>` |
| R | Nouvelle partie (après la mort) |

## Le jeu

- Vous êtes le chevalier bleu. L'escalier mène à l'étage suivant.
- Objets : potion de soin (rose), épée (attaque +1), bouclier (défense +1).
- Monstres : rat, gobelin, squelette, orc, troll, démon.
  Plus vous descendez, plus ils sont nombreux et forts.
- Chaque espèce a sa vitesse (100 = comme vous) : rat 150 et démon 135 (rapides),
  gobelin 120, orc 100, squelette 80 et troll 65 (lents, on peut les fuir).

## Combats

Toucher un monstre lance un combat au tour par tour (jusqu'à 3 ennemis).
Si vous le touchez en premier, vous avez l'**avantage** ; s'il vous attrape, c'est une **embuscade**.

- **Attaque** : coup physique. **Compétences** : sorts qui coûtent des PM.
- **Objets** : potion de soin. **Défense** : dégâts divisés par deux. **Fuir** : 60 % de chances.
- Chaque monstre a une **faiblesse** (et parfois une résistance). La toucher le met **à terre**
  et vous donne **UNE DE PLUS** : vous rejouez tout de suite.
- Quand tous les ennemis sont à terre, l'**assaut général** frappe tout le monde très fort.
- Les faiblesses découvertes s'affichent sous les monstres.
- Les PM reviennent en marchant, en descendant un étage et en montant de niveau.
- Nouvelles compétences : Coup puissant (niveau 3), Tempête (niveau 5), Brasier (niveau 6).

Commandes en combat : haut/bas pour choisir, gauche/droite pour la cible,
Entrée ou Espace pour valider, Échap pour revenir.

## Graphismes

Les images sont dans `assets/sprites.png` (pixel art 12×12, affiché en ×2).
Elles sont dessinées par `tools/make_sprites.py` : chaque lettre est une couleur.
Pour modifier un dessin, changez les lettres puis lancez `python3 tools/make_sprites.py`.
Vous pouvez aussi retoucher `assets/sprites.png` directement dans un logiciel de dessin
(Aseprite, Piskel, GIMP…), en gardant la même grille.
- Vaincre des monstres donne de l'expérience et fait monter de niveau.
- Votre record de profondeur est gardé d'une partie à l'autre.

Pour rejouer toujours le même donjon : sélectionnez le nœud **Main** dans Godot et mettez
un nombre dans **Graine Fixe** (0 = donjon aléatoire).

## Fichiers

- `scripts/main.gd` : la carte (déplacements, monstres, vision, affichage).
- `scripts/battle.gd` : l'écran de combat.
- `scripts/dungeon.gd` : la génération des donjons.
- `assets/sprites.png` et `tools/make_sprites.py` : les graphismes.
- `.agents/skills/` et `.claude/skills/` : les skills de développement de jeux pour Claude.
