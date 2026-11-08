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
# Images de marche : 5 par personnage à partir du numéro 16, dans l'ordre
# héros, rat, gobelin, squelette, orc, troll, démon (voir tools/make_sprites.py).
const SPR_WALK_BASE := 16
const WALK_FRAMES := 5

const DIM := Color(0.38, 0.38, 0.52)

# Durées des animations (en secondes).
const BUMP_TIME := 0.16
const FLASH_TIME := 0.22
const FLOAT_TIME := 0.8
const DEATH_TIME := 0.35
const FADE_TIME := 0.35
const STEP_TIME := 0.3  # durée d'un pas en marchant : plus grand = plus lent
const RUN_STEP_TIME := 0.15  # durée d'un pas en courant (Maj enfoncée)
const HOLD_WAIT := 0.25  # touche maintenue contre un monstre : délai entre deux coups

# Zoom de la caméra : 1 = toute la carte, 2 = deux fois plus près, etc.
const ZOOM_LEVELS := [1.0, 1.5, 2.0, 2.5, 3.0]
const DEFAULT_ZOOM_INDEX := 2
const VIEW_SIZE := Vector2(MAP_W * TILE, UI_TOP)

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
	# Animation : position affichée (en pixels), élan d'attaque, flash quand touché.
	var vis := Vector2.ZERO
	var bump_dir := Vector2.ZERO
	var bump_t := 0.0
	var flash_t := 0.0
	var phase := randf()
	var facing := 1  # 1 = regarde à droite, -1 = à gauche
	var step_t := 0.0  # > 0 pendant un pas
	var step_time := 0.3  # durée du pas en cours (marche ou course)

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

# Effets visuels en cours
var anim_time := 0.0
var hold_wait := 0.0  # attente avant la prochaine action quand une touche reste enfoncée
var zoom_index := DEFAULT_ZOOM_INDEX
var zoom := 2.0
var cam := Vector2.ZERO  # point de la carte (en pixels) au centre de l'écran
var trauma := 0.0  # secousse de l'écran, de 0 à 1
var fade := 0.0  # fondu au noir quand on change d'étage
var floaters := []  # nombres qui s'envolent : {text, pos, color, t}
var ghosts := []  # monstres qui disparaissent : {sprite, pos, t}


func _ready() -> void:
	font = ThemeDB.fallback_font
	# Pixels nets quand les images sont agrandies (pas de flou).
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	load_profile()
	zoom = ZOOM_LEVELS[zoom_index]
	new_run()


func _process(delta: float) -> void:
	anim_time += delta
	# Les personnages avancent vers leur case à vitesse régulière (un pas = step_time).
	# S'ils ont du retard, ils accélèrent pour le rattraper.
	var actors: Array[Actor] = [player]
	actors.append_array(monsters)
	for a in actors:
		var target := cell_px(a.pos)
		var speed := maxf(TILE / a.step_time, a.vis.distance_to(target) * 6.0)
		a.vis = a.vis.move_toward(target, speed * delta)
		a.bump_t = maxf(0.0, a.bump_t - delta / BUMP_TIME)
		a.flash_t = maxf(0.0, a.flash_t - delta / FLASH_TIME)
		a.step_t = maxf(0.0, a.step_t - delta / a.step_time)
	for fx: Dictionary in floaters:
		fx["t"] += delta
	floaters = floaters.filter(func(f: Dictionary) -> bool: return f["t"] < FLOAT_TIME)
	for g: Dictionary in ghosts:
		g["t"] += delta
	ghosts = ghosts.filter(func(g: Dictionary) -> bool: return g["t"] < DEATH_TIME)
	cam = cam.lerp(camera_target(), 1.0 - exp(-delta * 10.0))
	trauma = maxf(0.0, trauma - delta * 2.0)
	fade = maxf(0.0, fade - delta / FADE_TIME)
	handle_held_keys(delta)
	queue_redraw()


## Touche de direction maintenue : le héros continue d'avancer, un pas après l'autre.
func handle_held_keys(delta: float) -> void:
	hold_wait = maxf(0.0, hold_wait - delta)
	if game_over or player.step_t > 0.0 or hold_wait > 0.0:
		return
	var dir := held_direction()
	if dir == Vector2i.ZERO:
		return
	if try_move(dir):
		end_player_turn()
	if player.step_t <= 0.0:
		# Pas de déplacement (attaque ou mur) : petite pause avant de recommencer.
		hold_wait = HOLD_WAIT


func held_direction() -> Vector2i:
	var d := Vector2i.ZERO
	if is_any_pressed([KEY_UP, KEY_W, KEY_KP_8, KEY_KP_7, KEY_KP_9]):
		d.y -= 1
	if is_any_pressed([KEY_DOWN, KEY_S, KEY_KP_2, KEY_KP_1, KEY_KP_3]):
		d.y += 1
	if is_any_pressed([KEY_LEFT, KEY_A, KEY_KP_4, KEY_KP_7, KEY_KP_1]):
		d.x -= 1
	if is_any_pressed([KEY_RIGHT, KEY_D, KEY_KP_6, KEY_KP_9, KEY_KP_3]):
		d.x += 1
	return d


func is_any_pressed(keys: Array) -> bool:
	for k: Key in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func current_step_time() -> float:
	return RUN_STEP_TIME if Input.is_key_pressed(KEY_SHIFT) else STEP_TIME


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
	player.vis = cell_px(player.pos)
	stairs = dungeon.room_center(dungeon.rooms[-1])
	floaters.clear()
	ghosts.clear()
	fade = 1.0
	cam = camera_target()

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
	var m := Actor.new(r[0], r[1], p, hp, atk, r[4], r[5])
	m.vis = cell_px(p)
	return m


func make_item(p: Vector2i) -> Item:
	var weights := []
	for row: Array in ITEMS:
		weights.append(row[2])
	var r := weighted_pick(ITEMS, weights)
	return Item.new(r[0], r[1], p)


# ---------------------------------------------------------------- Commandes

func _unhandled_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed:
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(1)
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-1)
		return

	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	# Zoom : touches + et - (lettre réelle de la touche, pour marcher sur tous les claviers).
	if key.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]:
		change_zoom(1)
		return
	if key.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		change_zoom(-1)
		return

	if game_over:
		if key.physical_keycode == KEY_R:
			new_run()
		return

	# Les touches maintenues sont gérées dans handle_held_keys().
	if key.echo:
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
	if player.step_t <= 0.0:
		# Attaque, attente ou mur : on évite qu'une touche gardée enfoncée refasse l'action tout de suite.
		hold_wait = HOLD_WAIT


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
	start_step(player, dir, current_step_time())
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
	pop_text(player.pos, "+%d" % healed, Color("6fe06f"))
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
			pop_text(player.pos, "+1 potion", Color("e05a8a"))
		"epee":
			player.atk += 1
			log_msg("Vous trouvez une meilleure épée : attaque +1.")
			pop_text(player.pos, "+1 ATQ", Color("7fd0e0"))
		"bouclier":
			player.defense += 1
			log_msg("Vous trouvez un meilleur bouclier : défense +1.")
			pop_text(player.pos, "+1 DÉF", Color("6f8fe0"))


# ---------------------------------------------------------------- Combat

func attack(attacker: Actor, target: Actor) -> void:
	var dmg := maxi(1, attacker.atk - target.defense + rng.randi_range(-1, 1))
	target.hp -= dmg
	attacker.bump_dir = Vector2(target.pos - attacker.pos).normalized()
	if target.pos.x != attacker.pos.x:
		attacker.facing = signi(target.pos.x - attacker.pos.x)
	attacker.bump_t = 1.0
	target.flash_t = 1.0
	if target == player:
		pop_text(target.pos, "-%d" % dmg, Color("ff5a4a"))
		trauma = minf(1.0, trauma + 0.45)
	else:
		pop_text(target.pos, "-%d" % dmg, Color("fff2c0"))
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
		trauma = 1.0
		return
	monsters.erase(target)
	ghosts.append({"sprite": target.sprite, "pos": target.vis, "t": 0.0})
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
		pop_text(player.pos + Vector2i.UP, "NIVEAU %d !" % level, Color("e8c547"))


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
		if best != m.pos:
			start_step(m, best - m.pos, player.step_time)
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

	# La caméra (zoom + suivi du héros) et la secousse changent seulement l'affichage.
	var shake := trauma * trauma * 8.0
	var shake_offset := Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	draw_set_transform((map_offset() + shake_offset).round(), 0.0, Vector2(zoom, zoom))

	# On ne dessine que les cases visibles à l'écran.
	var half := VIEW_SIZE / (2.0 * zoom)
	var x0 := maxi(0, floori((cam.x - half.x) / TILE) - 1)
	var x1 := mini(MAP_W, ceili((cam.x + half.x) / TILE) + 1)
	var y0 := maxi(0, floori((cam.y - half.y) / TILE) - 1)
	var y1 := mini(MAP_H, ceili((cam.y + half.y) / TILE) + 1)
	for y in range(y0, y1):
		for x in range(x0, x1):
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
			var item_phase := float((it.pos.x * 7 + it.pos.y * 3) % 10) / 10.0
			draw_sprite_px(cell_px(it.pos) + Vector2(0, bob(item_phase)), it.sprite)

	for g: Dictionary in ghosts:
		var p: float = g["t"] / DEATH_TIME
		var size := TILE * (1.0 - 0.5 * p)
		var center: Vector2 = g["pos"] + Vector2(TILE, TILE) * 0.5
		draw_sprite_rect(Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)),
			g["sprite"], Color(3, 3, 3, 1.0 - p))

	for m in monsters:
		if visible_cells.has(m.pos):
			draw_actor(m)
	draw_actor(player)

	draw_set_transform(Vector2.ZERO)

	# Les textes sont dessinés sans zoom pour rester nets.
	for fx: Dictionary in floaters:
		var t: float = fx["t"]
		var alpha := clampf((FLOAT_TIME - t) / (FLOAT_TIME * 0.5), 0.0, 1.0)
		var col: Color = fx["color"]
		col.a = alpha
		var head: Vector2 = fx["pos"] + Vector2(TILE * 0.5, 0.0)
		var pos := world_to_screen(head) + shake_offset + Vector2(-60.0, -6.0 - t * 40.0)
		draw_string_outline(font, pos, fx["text"], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, 6,
			Color(0, 0, 0, alpha))
		draw_string(font, pos, fx["text"], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, col)

	draw_ui()

	if fade > 0.0:
		draw_rect(Rect2(0, 0, MAP_W * TILE, UI_TOP), Color(0, 0, 0, fade))

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
	draw_sprite_px(cell_px(cell), index, tint)


func draw_sprite_px(px: Vector2, index: int, tint := Color.WHITE) -> void:
	draw_sprite_rect(Rect2(px, Vector2(TILE, TILE)), index, tint)


func draw_sprite_rect(rect: Rect2, index: int, tint := Color.WHITE) -> void:
	var src := Rect2(
		(index % SHEET_COLUMNS) * SPRITE_PX,
		floori(index / float(SHEET_COLUMNS)) * SPRITE_PX,
		SPRITE_PX, SPRITE_PX)
	draw_texture_rect_region(SPRITES, rect, src, tint)


## Dessine un personnage avec ses animations : respiration, élan d'attaque, flash.
func draw_actor(a: Actor) -> void:
	var offset := Vector2.ZERO
	if a.step_t > 0.0:
		# Le corps descend d'un pixel quand le pied se pose, puis remonte.
		offset.y = 2.0 if a.step_t > 0.5 else 0.0
	else:
		offset.y = bob(a.phase)
	if a.bump_t > 0.0:
		offset += a.bump_dir * TILE * 0.4 * sin(PI * (1.0 - a.bump_t))
	var tint := Color.WHITE
	if a.flash_t > 0.0:
		tint = Color(1.0 + 2.5 * a.flash_t, 1.0 + 0.8 * a.flash_t, 1.0 + 0.8 * a.flash_t)
	var px := a.vis + offset
	draw_sprite_px(px, actor_frame(a), tint)
	if a != player and a.hp < a.max_hp:
		var w := float(TILE - 4) * a.hp / a.max_hp
		draw_rect(Rect2(px.x + 2, px.y - 2, TILE - 4, 3), Color("1b1424"))
		draw_rect(Rect2(px.x + 2, px.y - 2, w, 3), Color("e04030"))


## Choisit l'image du personnage selon sa direction et s'il est en train de marcher.
func actor_frame(a: Actor) -> int:
	var base := SPR_WALK_BASE + (a.sprite - SPR_PLAYER) * WALK_FRAMES
	# Un pas : d'abord la jambe en avant (image A), puis les jambes qui se croisent (B).
	var walk := -1
	if a.step_t > 0.5:
		walk = 0
	elif a.step_t > 0.0:
		walk = 1
	if a.facing > 0:
		return a.sprite if walk < 0 else base + walk
	return base + 2 if walk < 0 else base + 3 + walk


func start_step(a: Actor, dir: Vector2i, duration: float) -> void:
	a.step_time = duration
	if dir.x != 0:
		a.facing = signi(dir.x)
	a.step_t = 1.0


## Petit mouvement de haut en bas (1 pixel du dessin), chacun à son rythme.
func bob(phase: float) -> float:
	return -2.0 if int(anim_time * 2.0 + phase * 2.0) % 2 == 0 else 0.0


func change_zoom(step: int) -> void:
	zoom_index = clampi(zoom_index + step, 0, ZOOM_LEVELS.size() - 1)
	zoom = ZOOM_LEVELS[zoom_index]
	cam = camera_target()
	queue_redraw()


## Point que la caméra vise : le héros, sans montrer le vide au-delà des bords de la carte.
func camera_target() -> Vector2:
	var target := player.vis + Vector2(TILE, TILE) * 0.5
	var half := VIEW_SIZE / (2.0 * zoom)
	var world := Vector2(MAP_W * TILE, MAP_H * TILE)
	target.x = clampf(target.x, half.x, world.x - half.x) if world.x > half.x * 2.0 else world.x * 0.5
	target.y = clampf(target.y, half.y, world.y - half.y) if world.y > half.y * 2.0 else world.y * 0.5
	return target


func map_offset() -> Vector2:
	return VIEW_SIZE * 0.5 - cam * zoom


func world_to_screen(p: Vector2) -> Vector2:
	return map_offset() + p * zoom


func cell_px(c: Vector2i) -> Vector2:
	return Vector2(c * TILE)


func pop_text(cell: Vector2i, text: String, color: Color) -> void:
	floaters.append({"text": text, "pos": cell_px(cell), "color": color, "t": 0.0})


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
	# Fond du panneau du bas (cache la carte qui dépasse quand on zoome).
	draw_rect(Rect2(0, UI_TOP, MAP_W * TILE, UI_H), COL_BG)
	draw_rect(Rect2(0, UI_TOP, MAP_W * TILE, 2), Color("2a2533"))
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
		"Flèches / ZQSD / pavé numérique : bouger et attaquer   ·   Maj : courir   ·   Espace : attendre   ·   E : boire une potion   ·   Entrée : descendre   ·   Molette ou +/- : zoom   ·   Graine %d" % run_seed,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("8a8a96"))
