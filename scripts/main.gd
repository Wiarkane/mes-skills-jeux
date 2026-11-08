extends Node2D
## Roguelike au tour par tour : donjon généré, champ de vision, mort définitive.
## Les images viennent de assets/sprites.png (créée par tools/make_sprites.py).

const Dungeon = preload("res://scripts/dungeon.gd")
const SPRITES = preload("res://assets/sprites.png")
const SPRITE_PX := 12
const SHEET_COLUMNS := 8

# Numéros des images dans assets/sprites.png (même ordre que tools/make_sprites.py).
const SPR_WALL_TOP := 0
const SPR_WALL_FACE := 1
const SPR_FLOOR := 2
const SPR_FLOOR_CRACKED := 3
const SPR_FLOOR_PEBBLES := 4
const SPR_STAIRS := 5
const SPR_PLAYER := 6
const SPR_POTION := 13

const DIM := Color(0.38, 0.38, 0.52)

const TILE := 24
const MAP_W := 60
const MAP_H := 32
const UI_TOP := MAP_H * TILE
const UI_H := 176
const FOV_RADIUS := 8
const PROFILE_PATH := "user://profil.cfg"

const DIRS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## 0 = un donjon différent à chaque partie. Mettez un nombre pour rejouer toujours le même.
@export var graine_fixe: int = 0

var COL_BG := Color("0d0d10")

# nom, image, PV, attaque, défense, XP, profondeur minimale, fréquence
var MONSTERS := [
	["le rat", 7, 4, 2, 0, 2, 1, 6],
	["le gobelin", 8, 7, 3, 0, 4, 1, 4],
	["le squelette", 9, 10, 4, 1, 6, 2, 3],
	["l'orc", 10, 15, 5, 2, 9, 3, 3],
	["le troll", 11, 26, 7, 3, 16, 5, 2],
	["le démon", 12, 34, 9, 4, 25, 7, 2],
]

# type, image, fréquence
var ITEMS := [
	["potion", SPR_POTION, 6],
	["epee", 14, 2],
	["bouclier", 15, 2],
]


class Actor:
	var name: String
	var sprite: int
	var pos: Vector2i
	var hp: int
	var max_hp: int
	var atk: int
	var defense: int
	var xp: int
	var awake := false

	func _init(n: String, spr: int, p: Vector2i, h: int, a: int, d: int, x: int) -> void:
		name = n
		sprite = spr
		pos = p
		hp = h
		max_hp = h
		atk = a
		defense = d
		xp = x


class Item:
	var kind: String
	var sprite: int
	var pos: Vector2i

	func _init(k: String, spr: int, p: Vector2i) -> void:
		kind = k
		sprite = spr
		pos = p


var rng := RandomNumberGenerator.new()
var run_seed := 0
var depth := 1
var level := 1
var potions := 0
var kills := 0
var best_depth := 1
var game_over := false

var dungeon: Dungeon
var player: Actor
var monsters: Array[Actor] = []
var items: Array[Item] = []
var stairs := Vector2i.ZERO
var visible_cells := {}
var explored := PackedByteArray()
var messages: Array[String] = []
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	# Pixels nets quand les images sont agrandies (pas de flou).
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	load_profile()
	new_run()


# ---------------------------------------------------------------- Partie

func new_run() -> void:
	run_seed = graine_fixe if graine_fixe != 0 else randi()
	rng.seed = run_seed
	depth = 1
	level = 1
	potions = 1
	kills = 0
	game_over = false
	messages.clear()
	player = Actor.new("vous", SPR_PLAYER, Vector2i.ZERO, 30, 5, 1, 0)
	log_msg("Bienvenue dans le donjon. Trouvez l'escalier > pour descendre.")
	build_level()


func build_level() -> void:
	dungeon = Dungeon.new(MAP_W, MAP_H)
	dungeon.generate(rng, 30, 4, 10)
	while dungeon.rooms.size() < 5:
		dungeon.generate(rng, 30, 4, 10)

	explored = PackedByteArray()
	explored.resize(MAP_W * MAP_H)
	explored.fill(0)
	monsters.clear()
	items.clear()

	player.pos = dungeon.room_center(dungeon.rooms[0])
	stairs = dungeon.room_center(dungeon.rooms[-1])

	var n_monsters := mini(3 + depth * 2, 20)
	for i in n_monsters:
		var p := random_free_cell()
		if p.x >= 0:
			monsters.append(make_monster(p))

	var n_items := rng.randi_range(2, 4)
	for i in n_items:
		var p := random_free_cell()
		if p.x >= 0:
			items.append(make_item(p))

	update_fov()
	queue_redraw()


func random_free_cell() -> Vector2i:
	for attempt in 100:
		var room: Rect2i = dungeon.rooms[rng.randi_range(1, dungeon.rooms.size() - 1)]
		var p := Vector2i(
			rng.randi_range(room.position.x, room.end.x - 1),
			rng.randi_range(room.position.y, room.end.y - 1))
		if p == stairs or p == player.pos or monster_at(p) != null or item_at(p) != null:
			continue
		return p
	return Vector2i(-1, -1)


func weighted_pick(rows: Array, weights: Array) -> Array:
	var total := 0
	for w in weights:
		total += int(w)
	var roll := rng.randi_range(1, total)
	for i in rows.size():
		roll -= int(weights[i])
		if roll <= 0:
			return rows[i]
	return rows[-1]


func make_monster(p: Vector2i) -> Actor:
	var rows := []
	var weights := []
	for row: Array in MONSTERS:
		var min_depth: int = row[6]
		if min_depth > depth:
			continue
		rows.append(row)
		# Les monstres forts deviennent plus fréquents en descendant.
		var w: int = row[7]
		if min_depth > 1:
			w += (depth - min_depth) * 2
		weights.append(w)
	var r := weighted_pick(rows, weights)
	var bonus := int((depth - 1) / 3.0)
	var hp: int = r[2] + depth - 1
	var atk: int = r[3] + bonus
	return Actor.new(r[0], r[1], p, hp, atk, r[4], r[5])


func make_item(p: Vector2i) -> Item:
	var weights := []
	for row: Array in ITEMS:
		weights.append(row[2])
	var r := weighted_pick(ITEMS, weights)
	return Item.new(r[0], r[1], p)


# ---------------------------------------------------------------- Commandes

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	if game_over:
		if key.physical_keycode == KEY_R:
			new_run()
		return

	# Touches « physiques » : ZQSD sur un clavier AZERTY = WASD sur un clavier QWERTY.
	var took_turn := false
	match key.physical_keycode:
		KEY_UP, KEY_W, KEY_KP_8:
			took_turn = try_move(Vector2i(0, -1))
		KEY_DOWN, KEY_S, KEY_KP_2:
			took_turn = try_move(Vector2i(0, 1))
		KEY_LEFT, KEY_A, KEY_KP_4:
			took_turn = try_move(Vector2i(-1, 0))
		KEY_RIGHT, KEY_D, KEY_KP_6:
			took_turn = try_move(Vector2i(1, 0))
		KEY_KP_7:
			took_turn = try_move(Vector2i(-1, -1))
		KEY_KP_9:
			took_turn = try_move(Vector2i(1, -1))
		KEY_KP_1:
			took_turn = try_move(Vector2i(-1, 1))
		KEY_KP_3:
			took_turn = try_move(Vector2i(1, 1))
		KEY_SPACE, KEY_KP_5:
			took_turn = true
		KEY_E:
			took_turn = drink_potion()
		KEY_ENTER, KEY_KP_ENTER:
			descend()
			return
		_:
			return

	get_viewport().set_input_as_handled()
	if took_turn:
		end_player_turn()


func end_player_turn() -> void:
	update_fov()
	monsters_act()
	queue_redraw()


func try_move(dir: Vector2i) -> bool:
	var target := player.pos + dir
	var m := monster_at(target)
	if m != null:
		attack(player, m)
		return true
	if not dungeon.is_walkable(target):
		return false
	player.pos = target
	pick_up()
	if target == stairs:
		log_msg("Un escalier descend ici. Appuyez sur Entrée.")
	return true


func drink_potion() -> bool:
	if potions <= 0:
		log_msg("Vous n'avez pas de potion.")
		queue_redraw()
		return false
	if player.hp >= player.max_hp:
		log_msg("Vous êtes déjà en pleine forme.")
		queue_redraw()
		return false
	potions -= 1
	var healed := mini(12, player.max_hp - player.hp)
	player.hp += healed
	log_msg("Vous buvez une potion : +%d PV." % healed)
	return true


func descend() -> void:
	if player.pos != stairs:
		log_msg("Il n'y a pas d'escalier ici.")
		queue_redraw()
		return
	depth += 1
	player.hp = mini(player.max_hp, player.hp + 5)
	if depth > best_depth:
		best_depth = depth
		save_profile()
	log_msg("Vous descendez à la profondeur %d." % depth)
	build_level()


func pick_up() -> void:
	var it := item_at(player.pos)
	if it == null:
		return
	items.erase(it)
	match it.kind:
		"potion":
			potions += 1
			log_msg("Vous ramassez une potion de soin.")
		"epee":
			player.atk += 1
			log_msg("Vous trouvez une meilleure épée : attaque +1.")
		"bouclier":
			player.defense += 1
			log_msg("Vous trouvez un meilleur bouclier : défense +1.")


# ---------------------------------------------------------------- Combat

func attack(attacker: Actor, target: Actor) -> void:
	var dmg := maxi(1, attacker.atk - target.defense + rng.randi_range(-1, 1))
	target.hp -= dmg
	if attacker == player:
		log_msg("Vous frappez %s : %d dégâts." % [target.name, dmg])
	else:
		log_msg("%s vous frappe : %d dégâts." % [capitalize_first(attacker.name), dmg])
	if target.hp <= 0:
		kill(target)


func kill(target: Actor) -> void:
	if target == player:
		game_over = true
		if depth > best_depth:
			best_depth = depth
		save_profile()
		log_msg("Vous êtes mort à la profondeur %d." % depth)
		return
	monsters.erase(target)
	kills += 1
	player.xp += target.xp
	log_msg("Vous avez vaincu %s ! (+%d XP)" % [target.name, target.xp])
	if rng.randf() < 0.15 and item_at(target.pos) == null:
		items.append(Item.new("potion", SPR_POTION, target.pos))
	while player.xp >= level * 10:
		player.xp -= level * 10
		level += 1
		player.max_hp += 6
		player.hp = mini(player.max_hp, player.hp + 10)
		player.atk += 1
		log_msg("Niveau %d ! PV max +6, attaque +1." % level)


func monsters_act() -> void:
	var dist := distance_map(player.pos)
	for m in monsters:
		if game_over:
			return
		# Vision symétrique : si vous voyez le monstre, il vous voit aussi.
		if visible_cells.has(m.pos):
			m.awake = true
		if not m.awake:
			continue
		var d := m.pos - player.pos
		if absi(d.x) <= 1 and absi(d.y) <= 1:
			attack(m, player)
			continue
		var best := m.pos
		var best_d: int = dist.get(m.pos, 9999)
		for dir: Vector2i in DIRS:
			var p := m.pos + dir
			if not dist.has(p) or monster_at(p) != null:
				continue
			var dp: int = dist[p]
			if dp < best_d:
				best_d = dp
				best = p
		m.pos = best


func distance_map(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		var cd: int = dist[c]
		if cd >= 30:
			continue
		for dir: Vector2i in DIRS:
			var n := c + dir
			if dist.has(n) or not dungeon.is_walkable(n):
				continue
			dist[n] = cd + 1
			queue.append(n)
	return dist


# ---------------------------------------------------------------- Vision

func update_fov() -> void:
	visible_cells.clear()
	var o := player.pos
	var r2 := FOV_RADIUS * FOV_RADIUS + FOV_RADIUS
	for y in range(o.y - FOV_RADIUS, o.y + FOV_RADIUS + 1):
		for x in range(o.x - FOV_RADIUS, o.x + FOV_RADIUS + 1):
			var c := Vector2i(x, y)
			if not dungeon.in_bounds(c) or (c - o).length_squared() > r2:
				continue
			# Tester la ligne dans les deux sens rend la vision symétrique.
			if line_clear(o, c) or line_clear(c, o):
				visible_cells[c] = true
				explored[y * MAP_W + x] = 1


func line_clear(a: Vector2i, b: Vector2i) -> bool:
	var x := a.x
	var y := a.y
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	while not (x == b.x and y == b.y):
		if not (x == a.x and y == a.y) and dungeon.is_opaque(Vector2i(x, y)):
			return false
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return true


# ---------------------------------------------------------------- Outils

func monster_at(p: Vector2i) -> Actor:
	for m in monsters:
		if m.pos == p:
			return m
	return null


func item_at(p: Vector2i) -> Item:
	for it in items:
		if it.pos == p:
			return it
	return null


func log_msg(text: String) -> void:
	messages.append(text)
	if messages.size() > 50:
		messages.pop_front()


func capitalize_first(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		best_depth = int(cfg.get_value("profil", "meilleure_profondeur", 1))


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profil", "meilleure_profondeur", best_depth)
	cfg.save(PROFILE_PATH)


# ---------------------------------------------------------------- Dessin

func _draw() -> void:
	draw_rect(Rect2(0, 0, MAP_W * TILE, UI_TOP + UI_H), COL_BG)

	for y in MAP_H:
		for x in MAP_W:
			var c := Vector2i(x, y)
			var lit := visible_cells.has(c)
			if not lit and explored[y * MAP_W + x] == 0:
				continue
			var tint := Color.WHITE if lit else DIM
			draw_sprite(c, tile_sprite(c), tint)

	if explored[stairs.y * MAP_W + stairs.x] == 1:
		draw_sprite(stairs, SPR_STAIRS, Color.WHITE if visible_cells.has(stairs) else DIM)

	for it in items:
		if visible_cells.has(it.pos):
			draw_sprite(it.pos, it.sprite)

	for m in monsters:
		if visible_cells.has(m.pos):
			draw_sprite(m.pos, m.sprite)
			if m.hp < m.max_hp:
				var w := float(TILE - 4) * m.hp / m.max_hp
				draw_rect(Rect2(m.pos.x * TILE + 2, m.pos.y * TILE, TILE - 4, 3), Color("1b1424"))
				draw_rect(Rect2(m.pos.x * TILE + 2, m.pos.y * TILE, w, 3), Color("e04030"))

	draw_sprite(player.pos, player.sprite)
	draw_ui()

	if game_over:
		draw_rect(Rect2(0, 0, MAP_W * TILE, UI_TOP), Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(0, UI_TOP / 2.0 - 10), "VOUS ÊTES MORT",
			HORIZONTAL_ALIGNMENT_CENTER, MAP_W * TILE, 56, Color("d04030"))
		draw_string(font, Vector2(0, UI_TOP / 2.0 + 40),
			"Profondeur %d  ·  %d monstres vaincus  ·  niveau %d" % [depth, kills, level],
			HORIZONTAL_ALIGNMENT_CENTER, MAP_W * TILE, 22, Color("e0e0e0"))
		draw_string(font, Vector2(0, UI_TOP / 2.0 + 80), "Appuyez sur R pour une nouvelle partie",
			HORIZONTAL_ALIGNMENT_CENTER, MAP_W * TILE, 20, Color("e8c547"))


func draw_sprite(cell: Vector2i, index: int, tint := Color.WHITE) -> void:
	var src := Rect2(
		(index % SHEET_COLUMNS) * SPRITE_PX,
		floori(index / float(SHEET_COLUMNS)) * SPRITE_PX,
		SPRITE_PX, SPRITE_PX)
	draw_texture_rect_region(SPRITES, Rect2(cell.x * TILE, cell.y * TILE, TILE, TILE), src, tint)


## Choisit l'image d'une case : mur vu de face s'il y a du sol juste en dessous,
## sinon dessus du mur ; pour le sol, une variante qui dépend de la position.
func tile_sprite(c: Vector2i) -> int:
	if dungeon.is_opaque(c):
		return SPR_WALL_FACE if dungeon.is_walkable(c + Vector2i.DOWN) else SPR_WALL_TOP
	var h := ((c.x * 73856093) ^ (c.y * 19349663)) % 10
	if h < 7:
		return SPR_FLOOR
	return SPR_FLOOR_CRACKED if h < 9 else SPR_FLOOR_PEBBLES


func draw_ui() -> void:
	var y0 := float(UI_TOP) + 10.0
	var bar_w := 240.0
	var hp := maxi(player.hp, 0)
	draw_rect(Rect2(12, y0, bar_w, 20), Color("3a1c1c"))
	draw_rect(Rect2(12, y0, bar_w * hp / player.max_hp, 20), Color("c0392b"))
	draw_string(font, Vector2(20, y0 + 15), "PV %d / %d" % [hp, player.max_hp],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

	var stats := "Profondeur %d    Niveau %d (XP %d/%d)    Attaque %d    Défense %d    Potions %d    Record %d" % [
		depth, level, player.xp, level * 10, player.atk, player.defense, potions, best_depth]
	draw_string(font, Vector2(270, y0 + 15), stats, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("d8d8d8"))

	var start := maxi(0, messages.size() - 5)
	for i in range(start, messages.size()):
		var age := messages.size() - 1 - i
		var shade := Color(0.95, 0.95, 0.95, 1.0 - age * 0.15)
		draw_string(font, Vector2(12, y0 + 48 + (i - start) * 20), messages[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, shade)

	draw_string(font, Vector2(12, y0 + 156),
		"Flèches / ZQSD / pavé numérique : bouger et attaquer   ·   Espace : attendre   ·   E : boire une potion   ·   Entrée : descendre   ·   Graine %d" % run_seed,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("8a8a96"))
