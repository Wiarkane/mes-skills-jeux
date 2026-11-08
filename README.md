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
| Espace ou 5 | Attendre un tour |
| E | Boire une potion de soin |
| Entrée | Descendre l'escalier `>` |
| R | Nouvelle partie (après la mort) |

## Le jeu

- `@` c'est vous. `>` est l'escalier vers l'étage suivant.
- Objets : `!` potion de soin, `/` épée (attaque +1), `[` bouclier (défense +1).
- Monstres : `r` rat, `g` gobelin, `s` squelette, `o` orc, `T` troll, `D` démon.
  Plus vous descendez, plus ils sont nombreux et forts.
- Vaincre des monstres donne de l'expérience et fait monter de niveau.
- Votre record de profondeur est gardé d'une partie à l'autre.

Pour rejouer toujours le même donjon : sélectionnez le nœud **Main** dans Godot et mettez
un nombre dans **Graine Fixe** (0 = donjon aléatoire).

## Fichiers

- `scripts/main.gd` : le jeu (tours, combats, vision, affichage).
- `scripts/dungeon.gd` : la génération des donjons.
- `.agents/skills/` et `.claude/skills/` : les skills de développement de jeux pour Claude.
