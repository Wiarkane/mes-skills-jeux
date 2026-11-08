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

- `scripts/main.gd` : le jeu (tours, combats, vision, affichage).
- `scripts/dungeon.gd` : la génération des donjons.
- `assets/sprites.png` et `tools/make_sprites.py` : les graphismes.
- `.agents/skills/` et `.claude/skills/` : les skills de développement de jeux pour Claude.
