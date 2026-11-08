"""Dessine les sprites du jeu en pixel art et les enregistre dans assets/sprites.png.

Chaque sprite fait 12x12 pixels. Une lettre = une couleur de la palette, "." = transparent.
Pour changer un dessin : modifiez les lettres ci-dessous, puis relancez :
    python3 tools/make_sprites.py
"""
from pathlib import Path
import random

from PIL import Image

SIZE = 12
COLUMNS = 8

PALETTE = {
    ".": None,
    "k": "#1b1424",  # contour
    # pierre des murs
    "d": "#3b2f45", "s": "#5d4e66", "S": "#8a7a90",
    # sol
    "1": "#1f1e27", "2": "#2c2b36", "3": "#3a3946",
    # héros
    "T": "#c8d2de", "t": "#6f7c8c", "B": "#3a6fc4", "b": "#24467f", "Y": "#e8c547",
    "R": "#ff4030",  # yeux rouges
    "N": "#9a8a70", "n": "#5f5444",  # rat
    "V": "#6fbf4a", "v": "#3a7a2a",  # gobelin
    "W": "#e8e4d0", "w": "#a8a490",  # os
    "O": "#4f8f3a", "o": "#2f5f22",  # orc
    "L": "#8a5a3a", "l": "#5a3a22",  # cuir, bois
    "P": "#8f7f6f", "p": "#5f5244",  # troll
    "X": "#c0302a", "x": "#6a1a20",  # démon
    "Q": "#e05a8a", "q": "#8a2a52", "H": "#ffe0ec",  # potion
}

WALL_FACE = [
    "SSSSSSSSSSSS",
    "Sssssssdssss",
    "sssssssdssss",
    "dddddddddddd",
    "SssdSssssssd",
    "sssdssssssss",
    "dddddddddddd",
    "SsssssSdssss",
    "sssssssdssss",
    "dddddddddddd",
    "dddddddddddd",
    "kkkkkkkkkkkk",
]

STAIRS = [
    "322222222221",
    "2kkkkkkkkkk1",
    "2kTTTTTTTTk1",
    "2kddddddddk1",
    "2kkTTTTTTkk1",
    "2kkddddddkk1",
    "2kkkTTTTkkk1",
    "2kkkddddkkk1",
    "2kkkkTTkkkk1",
    "2kkkkkkkkkk1",
    "222222222221",
    "111111111111",
]

PLAYER = [
    "....kkkk....",
    "...kTTTTk...",
    "...ktkktk...",
    "...kTTTTk...",
    "..kbBBBBbk..",
    ".kTkBBBBkTk.",
    ".kTkBYYBkTk.",
    ".kkkBBBBkkk.",
    "...kbBBbk...",
    "...kTkkTk...",
    "...kTk.kTk..",
    "...kk..kk...",
]

RAT = [
    "............",
    "............",
    "............",
    "............",
    "............",
    "......kkk...",
    "....kkNNNkk.",
    "...kNNNNNNRk",
    "kk.kNNNNNNNk",
    ".kkknNNNNnk.",
    "...knk.knk..",
    "............",
]

GOBLIN = [
    "............",
    "....kkkk....",
    "kk.kVVVVk.kk",
    "kVkVVVVVVkVk",
    ".kVVRVVRVVk.",
    "..kVVVVVVk..",
    "..kVvkkvVk..",
    "...kLLLLk...",
    "..kVLLLLVk..",
    "...kLllLk...",
    "...kVk.kVk..",
    "...kk...kk..",
]

SKELETON = [
    "....kkkk....",
    "...kWWWWk...",
    "...kkWWkk...",
    "...kWWWWk...",
    "....kwwk....",
    "..kkkWWkkk..",
    ".kWkWwwWkWk.",
    ".kWkwWWwkWk.",
    "...kkWWkk...",
    "...kWkkWk...",
    "...kWk.kWk..",
    "...kk..kk...",
]

ORC = [
    "...kkkkkk...",
    "..kOOOOOOk..",
    ".kOROOOOROk.",
    ".kOOOOOOOOk.",
    ".kOWOOOOWOk.",
    "..kOOOOOOk..",
    "kkLLLLLLLLkk",
    "kOkLLllLLkOk",
    "kOkLLLLLLkOk",
    ".kklLLLLlkk.",
    "..kOOk.kOOk.",
    "..kkk..kkk..",
]

TROLL = [
    "...kkkkk..k.",
    "..kPPPPPkkLk",
    ".kPRPPPRPkLk",
    ".kPPPPPPPkLk",
    ".kPpkkkpPkLk",
    "kPPPPPPPPkLk",
    "kPkPPPPPkPPk",
    "kPkPPPPPkkk.",
    "kkkPPPPPk...",
    "..kPPkPPk...",
    ".kPPk.kPPk..",
    ".kkkk.kkkk..",
]

DEMON = [
    ".Yk......kY.",
    ".YYk....kYY.",
    "..kYkkkkYk..",
    "..kXXXXXXk..",
    ".kXYXXXXYXk.",
    ".kXXkkkkXXk.",
    "kxkXXXXXXkxk",
    "kxxkXXXXkxxk",
    "kxkXXxxXXkxk",
    ".k.kXXXXk.k.",
    "...kXk.kXk..",
    "...kk..kk...",
]

POTION = [
    "............",
    "....kkkk....",
    "....kLLk....",
    ".....kk.....",
    "....kHHk....",
    "...kQHQQk...",
    "..kQHQQQQk..",
    "..kQQQQQQk..",
    "..kqQQQQqk..",
    "...kqqqqk...",
    "....kkkk....",
    "............",
]

SWORD = [
    "..........kk",
    ".........kTk",
    "........kTtk",
    ".......kTtk.",
    "......kTtk..",
    ".....kTtk...",
    "..k.kTtk....",
    "..kkTtk.....",
    "...kYk......",
    "..kLkYk.....",
    ".kLk.kk.....",
    ".kk.........",
]

SHIELD = [
    "............",
    "..kkkkkkkk..",
    ".kYBBBBBBYk.",
    ".kBBBYYBBBk.",
    ".kBBBYYBBBk.",
    ".kBYYYYYYBk.",
    ".kBBBYYBBBk.",
    "..kBBYYBBk..",
    "..kbBBBBbk..",
    "...kbBBbk...",
    "....kbbk....",
    ".....kk.....",
]


def speckled(base, speck, seed, count, edges=None):
    """Une tuile unie avec quelques points, pour les sols et le dessus des murs."""
    rnd = random.Random(seed)
    rows = [[base] * SIZE for _ in range(SIZE)]
    for _ in range(count):
        rows[rnd.randrange(SIZE - 1)][rnd.randrange(SIZE - 1)] = speck
    if edges:
        light, dark = edges
        for i in range(SIZE):
            rows[SIZE - 1][i] = dark
            rows[i][SIZE - 1] = dark
        rows[0][0] = light
    return ["".join(r) for r in rows]


def cracked_floor():
    rows = [list(r) for r in speckled("2", "3", 2, 3, ("3", "1"))]
    for x, y in [(3, 4), (4, 5), (5, 5), (6, 6), (6, 7), (7, 8)]:
        rows[y][x] = "1"
    return ["".join(r) for r in rows]


# L'ordre compte : main.gd utilise ces numéros.
SPRITES = [
    ("mur (dessus)", speckled("d", "s", 1, 9)),
    ("mur (face)", WALL_FACE),
    ("sol", speckled("2", "3", 3, 4, ("3", "1"))),
    ("sol fissuré", cracked_floor()),
    ("sol caillouteux", speckled("2", "1", 4, 10, ("3", "1"))),
    ("escalier", STAIRS),
    ("héros", PLAYER),
    ("rat", RAT),
    ("gobelin", GOBLIN),
    ("squelette", SKELETON),
    ("orc", ORC),
    ("troll", TROLL),
    ("démon", DEMON),
    ("potion", POTION),
    ("épée", SWORD),
    ("bouclier", SHIELD),
]


# Images de marche : on part de l'image du personnage et on remplace quelques lignes
# (les jambes). A = jambes écartées, B = jambes qui se croisent.
WALK = [
    ("héros", PLAYER, {10: "..kTk..kTk..", 11: "..kk...kk..."},
                      {10: "...kTkkTk...", 11: "....kkkk...."}),
    ("rat", RAT, {10: "..knk...knk."},
                 {8: ".k.kNNNNNNNk", 9: "k.kknNNNNnk.", 10: "....knkknk.."}),
    ("gobelin", GOBLIN, {10: "..kVk...kVk.", 11: "..kk....kk.."},
                        {10: "...kVkkVk...", 11: "...kk..kk..."}),
    ("squelette", SKELETON, {10: "..kWk...kWk.", 11: "..kk....kk.."},
                            {10: "...kWkkWk...", 11: "...kk..kk..."}),
    ("orc", ORC, {10: ".kOOk...kOOk", 11: ".kkk.....kkk"},
                 {10: "...kOOkOOk..", 11: "...kkk.kkk.."}),
    ("troll", TROLL, {10: "kPPk...kPPk.", 11: "kkkk...kkkk."},
                     {10: "..kPPkPPk...", 11: "..kkkkkkk..."}),
    ("démon", DEMON, {10: "..kXk...kXk.", 11: "..kk....kk.."},
                     {10: "...kXkkXk...", 11: "....kkkk...."}),
]


def with_rows(art, changes):
    return [changes.get(i, line) for i, line in enumerate(art)]


def mirror(art):
    return [line[::-1] for line in art]


# À partir du numéro 16 : pour chaque personnage, 5 images
# (marche A, marche B, puis tourné vers la gauche : immobile, marche A, marche B).
for name, art, walk_a, walk_b in WALK:
    frame_a = with_rows(art, walk_a)
    frame_b = with_rows(art, walk_b)
    SPRITES.append((f"{name} marche A", frame_a))
    SPRITES.append((f"{name} marche B", frame_b))
    SPRITES.append((f"{name} gauche", mirror(art)))
    SPRITES.append((f"{name} gauche marche A", mirror(frame_a)))
    SPRITES.append((f"{name} gauche marche B", mirror(frame_b)))


def to_rgba(hex_color):
    h = hex_color.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def main():
    rows_count = (len(SPRITES) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * SIZE, rows_count * SIZE), (0, 0, 0, 0))
    for index, (name, art) in enumerate(SPRITES):
        assert len(art) == SIZE, f"{name} : {len(art)} lignes au lieu de {SIZE}"
        ox, oy = (index % COLUMNS) * SIZE, (index // COLUMNS) * SIZE
        for y, line in enumerate(art):
            assert len(line) == SIZE, f"{name}, ligne {y} : {len(line)} pixels au lieu de {SIZE}"
            for x, ch in enumerate(line):
                color = PALETTE[ch]
                if color:
                    sheet.putpixel((ox + x, oy + y), to_rgba(color))
    out = Path(__file__).resolve().parent.parent / "assets" / "sprites.png"
    out.parent.mkdir(exist_ok=True)
    sheet.save(out)
    print(f"{len(SPRITES)} sprites enregistrés dans {out}")


if __name__ == "__main__":
    main()
