extends Node2D
## Écran de combat au tour par tour, façon RPG japonais : attaques, compétences
## élémentaires, faiblesses, « Une de plus ! » et assaut général.
## Il s'affiche par-dessus la carte quand le héros rencontre un monstre.

const SPRITES = preload("res://assets/sprites.png")
const SPRITE_PX := 12
const SHEET_COLUMNS := 8
const SPR_HERO := 6
const SCREEN := Vector2(1440, 944)
const ACTION_DELAY := 0.75  # pause entre deux actions, pour avoir le temps de lire

const GOLD := Color("f2c94c")
const RED := Color("e8434f")
const INK := Color("120f24")

var ELEMENT_COLORS := {
	"physique": Color("e8e8e8"), "feu": Color("ff7a3a"), "glace": Color("7fd8ff"),
	"foudre": Color("ffe14a"), "vent": Color("7aff9a"), "soin": Color("6fe06f"),
}

# nom, élément, coût en PM, puissance, cible ("un", "tous", "soi"), niveau requis, description
var SKILLS := [
	["Flamme", "feu", 4, 9, "un", 1, "Dégâts de feu sur un ennemi."],
	["Givre", "glace", 4, 9, "un", 1, "Dégâts de glace sur un ennemi."],
	["Foudre", "foudre", 4, 9, "un", 1, "Dégâts de foudre sur un ennemi."],
	["Bourrasque", "vent", 4, 9, "un", 1, "Dégâts de vent sur un ennemi."],
	["Soin", "soin", 5, 15, "soi", 1, "Rend 15 PV au héros."],
	["Coup puissant", "physique", 6, 12, "un", 3, "Grosse attaque physique sur un ennemi."],
	["Tempête", "vent", 10, 8, "tous", 5, "Dégâts de vent sur tous les ennemis."],
	["Brasier", "feu", 10, 8, "tous", 6, "Dégâts de feu sur tous les ennemis."],
]

var main  # le script principal (main.gd), donné à la création
var active := false
var enemies: Array = []  # monstres de main.gd qui participent au combat
var downed := {}  # ennemis à terre
var phase := "busy"  # menu, skill, item, target, busy, end
var menu_index := 0
var skill_index := 0
var target_index := 0
var pending: Array = []  # compétence en attente d'une cible ([] = attaque normale)
var queue: Array[Callable] = []  # actions à jouer l'une après l'autre
var timer := 0.0
var guarding := false
var result := ""  # victoire, fuite, defaite
var xp_gained := 0

# Effets visuels
var time := 0.0
var intro := 0.0
var trauma := 0.0
var banner := ""
var banner_color := Color.WHITE
var banner_t := 0.0
var line := ""
var floaters := []  # {text, pos, color, t}
var bursts := []  # {pos, color, t}
var dying := []  # {sprite, pos, t}
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	visible = false


# ---------------------------------------------------------------- Déroulement

func start(group: Array, mode: String) -> void:
	enemies = group
	downed.clear()
	active = true
	visible = true
	phase = "busy"
	menu_index = 0
	skill_index = 0
	target_index = 0
	guarding = false
	result = ""
	xp_gained = 0
	queue.clear()
	floaters.clear()
	bursts.clear()
	dying.clear()
	intro = 1.0
	timer = 1.0
	if mode == "avantage":
		show_banner("AVANTAGE !", GOLD)
		say("Vous frappez en premier !")
		queue.append(open_menu)
	else:
		show_banner("EMBUSCADE !", RED)
		say("Les ennemis vous ont surpris !")
		queue_enemy_turns()


func open_menu() -> void:
	guarding = false
	phase = "menu"
	timer = 0.0
	menu_index = clampi(menu_index, 0, menu_options().size() - 1)
	if can_all_out():
		say("Tous les ennemis sont à terre : c'est le moment d'un assaut général !")
	else:
		say("Que faire ?")


func queue_enemy_turns() -> void:
	for e in enemies:
		queue.append(enemy_action.bind(e))
	queue.append(open_menu)


func after_player_action(one_more: bool) -> void:
	timer = ACTION_DELAY
	if enemies.is_empty():
		queue.append(victory)
		return
	if one_more:
		show_banner("UNE DE PLUS !", GOLD)
		queue.append(open_menu)
		return
	queue_enemy_turns()


func victory() -> void:
	phase = "end"
	result = "victoire"
	show_banner("VICTOIRE !", GOLD, 99.0)
	main.player.sp = mini(main.player.max_sp, main.player.sp + 3)
	say("Victoire ! +%d XP.   (Entrée pour continuer)" % xp_gained)


func defeat() -> void:
	phase = "end"
	result = "defaite"
	show_banner("DÉFAITE...", RED, 99.0)
	say("Vous êtes tombé au combat.   (Entrée pour continuer)")


func finish() -> void:
	active = false
	visible = false
	position = Vector2.ZERO
	main.on_battle_end(result, xp_gained, enemies)


# ---------------------------------------------------------------- Actions du héros

func player_attack(target) -> void:
	phase = "busy"
	say("Vous attaquez %s !" % target.name)
	var dmg := maxi(1, main.player.atk + main.rng.randi_range(-1, 2) - target.defense)
	after_player_action(hit(target, dmg, "physique"))


func use_skill(row: Array, target) -> void:
	phase = "busy"
	main.player.sp -= int(row[2])
	var elem: String = row[1]
	say("Vous lancez %s !" % row[0])
	if elem == "soin":
		var heal := mini(int(row[3]), main.player.max_hp - main.player.hp)
		main.player.hp += heal
		pop(player_pos(), "+%d" % heal, ELEMENT_COLORS["soin"])
		burst(player_pos(), ELEMENT_COLORS["soin"])
		after_player_action(false)
		return
	var targets: Array = enemies.duplicate() if row[4] == "tous" else [target]
	var one_more := false
	for t in targets:
		var dmg: int
		if elem == "physique":
			dmg = maxi(1, int(row[3]) + main.player.atk - t.defense + main.rng.randi_range(-1, 2))
		else:
			dmg = int(row[3]) + main.level * 2 + main.rng.randi_range(-1, 2)
		if hit(t, dmg, elem):
			one_more = true
	after_player_action(one_more)


func use_potion() -> void:
	if main.potions <= 0:
		say("Vous n'avez pas de potion.")
		return
	if main.player.hp >= main.player.max_hp:
		say("Vous êtes déjà en pleine forme.")
		return
	phase = "busy"
	main.potions -= 1
	var heal := mini(15, main.player.max_hp - main.player.hp)
	main.player.hp += heal
	say("Vous buvez une potion : +%d PV." % heal)
	pop(player_pos(), "+%d" % heal, ELEMENT_COLORS["soin"])
	burst(player_pos(), ELEMENT_COLORS["soin"])
	after_player_action(false)


func do_guard() -> void:
	phase = "busy"
	guarding = true
	say("Vous vous mettez en garde : dégâts divisés par deux.")
	timer = 0.5
	queue_enemy_turns()


func do_flee() -> void:
	phase = "busy"
	timer = ACTION_DELAY
	if main.rng.randf() < 0.6:
		say("Vous prenez la fuite !")
		result = "fuite"
		queue.append(finish)
	else:
		say("Impossible de fuir !")
		queue_enemy_turns()


func do_all_out() -> void:
	phase = "busy"
	show_banner("ASSAUT GÉNÉRAL !", RED)
	say("Vous vous jetez sur les ennemis à terre !")
	trauma = 0.9
	for t in enemies.duplicate():
		var dmg: int = main.player.atk * 2 + main.level * 3 + main.rng.randi_range(0, 4)
		damage(t, dmg, Color.WHITE)
		burst(enemy_pos(t), RED)
		if t.hp <= 0:
			defeat_enemy(t)
	downed.clear()
	after_player_action(false)


## Inflige des dégâts d'un élément. Renvoie vrai si on a touché une faiblesse
## (ce qui donne un tour en plus).
func hit(target, dmg: int, elem: String) -> bool:
	var pos := enemy_pos(target)
	var color: Color = ELEMENT_COLORS.get(elem, Color.WHITE)
	var weak: bool = elem == target.weak
	burst(pos, color)
	if weak:
		dmg = int(dmg * 1.5)
		main.known_weak[target.name] = true
		pop(pos + Vector2(0, -50), "FAIBLE !", GOLD)
	elif elem == target.resist:
		dmg = maxi(1, int(dmg * 0.5))
		main.known_resist[target.name] = true
		pop(pos + Vector2(0, -50), "RÉSISTE", Color("9aa4c0"))
	damage(target, dmg, color)
	var one_more: bool = weak and not downed.has(target)
	if target.hp <= 0:
		defeat_enemy(target)
	elif weak:
		downed[target] = true
	return one_more


func damage(target, dmg: int, color: Color) -> void:
	target.hp -= dmg
	target.flash_t = 1.0
	pop(enemy_pos(target), "-%d" % dmg, color)


func defeat_enemy(target) -> void:
	dying.append({"sprite": target.sprite, "pos": enemy_pos(target), "t": 0.0})
	enemies.erase(target)
	downed.erase(target)
	xp_gained += target.xp
	main.remove_monster(target)
	say("%s est vaincu !" % main.capitalize_first(target.name))
	target_index = clampi(target_index, 0, maxi(0, enemies.size() - 1))


# ---------------------------------------------------------------- Tour des ennemis

func enemy_action(e) -> void:
	timer = ACTION_DELAY
	if not enemies.has(e):
		timer = 0.0
		return
	if downed.has(e):
		downed.erase(e)
		say("%s se relève." % main.capitalize_first(e.name))
		return
	var dmg := maxi(1, e.atk - main.player.defense + main.rng.randi_range(-1, 1))
	if guarding:
		dmg = maxi(1, int(dmg / 2.0))
	main.player.hp -= dmg
	main.player.flash_t = 1.0
	e.bump_t = 1.0
	trauma = minf(1.0, trauma + 0.5)
	say("%s vous attaque : %d dégâts." % [main.capitalize_first(e.name), dmg])
	pop(player_pos(), "-%d" % dmg, RED)
	if main.player.hp <= 0:
		main.player.hp = 0
		queue.clear()
		queue.append(defeat)


# ---------------------------------------------------------------- Commandes

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	get_viewport().set_input_as_handled()
	var code := key.physical_keycode
	var up := code in [KEY_UP, KEY_W, KEY_KP_8]
	var down := code in [KEY_DOWN, KEY_S, KEY_KP_2]
	var left := code in [KEY_LEFT, KEY_A, KEY_KP_4]
	var right := code in [KEY_RIGHT, KEY_D, KEY_KP_6]
	var ok := not key.echo and code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E]
	var back := not key.echo and code in [KEY_ESCAPE, KEY_BACKSPACE]

	match phase:
		"menu":
			var opts := menu_options()
			if up:
				menu_index = wrapi(menu_index - 1, 0, opts.size())
			elif down:
				menu_index = wrapi(menu_index + 1, 0, opts.size())
			elif ok:
				choose_menu(opts[menu_index])
		"skill":
			var skills := known_skills()
			if up:
				skill_index = wrapi(skill_index - 1, 0, skills.size())
			elif down:
				skill_index = wrapi(skill_index + 1, 0, skills.size())
			elif back:
				phase = "menu"
			elif ok:
				choose_skill(skills[skill_index])
		"item":
			if back:
				phase = "menu"
			elif ok:
				use_potion()
		"target":
			if left:
				target_index = wrapi(target_index - 1, 0, enemies.size())
			elif right:
				target_index = wrapi(target_index + 1, 0, enemies.size())
			elif back:
				phase = "skill" if not pending.is_empty() else "menu"
			elif ok:
				var target = enemies[target_index]
				if pending.is_empty():
					player_attack(target)
				else:
					use_skill(pending, target)
		"end":
			if ok:
				finish()


func choose_menu(option: String) -> void:
	match option:
		"ASSAUT GÉNÉRAL":
			do_all_out()
		"Attaque":
			pending = []
			begin_target()
		"Compétences":
			phase = "skill"
			skill_index = clampi(skill_index, 0, known_skills().size() - 1)
		"Objets":
			phase = "item"
		"Défense":
			do_guard()
		"Fuir":
			do_flee()


func choose_skill(row: Array) -> void:
	if main.player.sp < int(row[2]):
		say("Pas assez de PM pour %s." % row[0])
		return
	if row[4] == "un":
		pending = row
		begin_target()
	else:
		use_skill(row, null)


func begin_target() -> void:
	phase = "target"
	target_index = clampi(target_index, 0, enemies.size() - 1)
	say("Choisissez une cible (gauche / droite).")


func menu_options() -> Array:
	var opts := ["Attaque", "Compétences", "Objets", "Défense", "Fuir"]
	if can_all_out():
		opts.push_front("ASSAUT GÉNÉRAL")
	return opts


func can_all_out() -> bool:
	if enemies.is_empty():
		return false
	for e in enemies:
		if not downed.has(e):
			return false
	return true


func known_skills() -> Array:
	var list := []
	for row: Array in SKILLS:
		if int(row[5]) <= main.level:
			list.append(row)
	return list


# ---------------------------------------------------------------- Effets

func say(text: String) -> void:
	line = text


func show_banner(text: String, color: Color, duration := 1.3) -> void:
	banner = text
	banner_color = color
	banner_t = duration


func pop(pos: Vector2, text: String, color: Color) -> void:
	floaters.append({"text": text, "pos": pos, "color": color, "t": 0.0})


func burst(pos: Vector2, color: Color) -> void:
	bursts.append({"pos": pos, "color": color, "t": 0.0})


func _process(delta: float) -> void:
	if not active:
		return
	time += delta
	intro = maxf(0.0, intro - delta / 0.5)
	trauma = maxf(0.0, trauma - delta * 2.0)
	banner_t = maxf(0.0, banner_t - delta)
	for list: Array in [floaters, bursts, dying]:
		for fx: Dictionary in list:
			fx["t"] += delta
	floaters = floaters.filter(func(f: Dictionary) -> bool: return f["t"] < 1.0)
	bursts = bursts.filter(func(f: Dictionary) -> bool: return f["t"] < 0.45)
	dying = dying.filter(func(f: Dictionary) -> bool: return f["t"] < 0.6)

	# La secousse déplace tout l'écran de combat.
	var shake := trauma * trauma * 14.0
	position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)).round()

	if timer > 0.0:
		timer -= delta
	elif not queue.is_empty():
		var step: Callable = queue.pop_front()
		step.call()
	queue_redraw()


# ---------------------------------------------------------------- Dessin

func enemy_pos(e) -> Vector2:
	var i := enemies.find(e)
	var n := enemies.size()
	return Vector2(SCREEN.x * 0.5 + (i - (n - 1) * 0.5) * 320.0, 290.0)


func player_pos() -> Vector2:
	return Vector2(1010, 790)


func _draw() -> void:
	if not active:
		return
	draw_background()

	for i in enemies.size():
		draw_enemy(enemies[i], i)

	for d: Dictionary in dying:
		var p: float = d["t"] / 0.6
		draw_spr(d["sprite"], d["pos"], 144.0 * (1.0 - 0.6 * p), Color(3, 3, 3, 1.0 - p))

	for b: Dictionary in bursts:
		var p: float = b["t"] / 0.45
		var col: Color = b["color"]
		col.a = 1.0 - p
		draw_arc(b["pos"], 30.0 + p * 120.0, 0.0, TAU, 40, col, 10.0 * (1.0 - p) + 2.0)
		if p < 0.3:
			draw_circle(b["pos"], 60.0 * (1.0 - p / 0.3), Color(col.r, col.g, col.b, 0.5))

	draw_player_panel()
	if phase in ["menu", "skill", "item", "target"]:
		draw_menu()
	draw_message_bar()

	for f: Dictionary in floaters:
		var t: float = f["t"]
		var a := clampf((1.0 - t) / 0.4, 0.0, 1.0)
		var col: Color = f["color"]
		col.a = a
		var pos: Vector2 = f["pos"] + Vector2(-150, -60.0 - t * 50.0)
		draw_string_outline(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 300, 34, 8, Color(0, 0, 0, a))
		draw_string(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 300, 34, col)

	if banner_t > 0.0:
		var a := clampf(banner_t / 0.3, 0.0, 1.0)
		var band := Color(0, 0, 0, 0.7 * a)
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, 440), Vector2(SCREEN.x, 410), Vector2(SCREEN.x, 500), Vector2(0, 530)]), band)
		var col := banner_color
		col.a = a
		draw_string_outline(font, Vector2(0, 495), banner, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 72, 14,
			Color(0, 0, 0, a))
		draw_string(font, Vector2(0, 495), banner, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 72, col)

	if intro > 0.0:
		draw_rect(Rect2(Vector2(-20, -20), SCREEN + Vector2(40, 40)), Color(1, 1, 1, intro))


func draw_background() -> void:
	draw_rect(Rect2(Vector2(-20, -20), SCREEN + Vector2(40, 40)), Color("0c0a1f"))
	# Bandes en biais qui défilent lentement.
	var shift := fmod(time * 40.0, 320.0)
	for i in range(-2, 12):
		var x := i * 160.0 + shift
		var col := Color("16133a") if i % 2 == 0 else Color("1d1950")
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, -20), Vector2(x + 80, -20), Vector2(x - 220, SCREEN.y + 20), Vector2(x - 300, SCREEN.y + 20)]), col)
	# Grande bande rouge derrière les ennemis.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-20, 360), Vector2(SCREEN.x + 20, 300), Vector2(SCREEN.x + 20, 340), Vector2(-20, 400)]),
		Color(0.75, 0.12, 0.2, 0.6))


func draw_enemy(e, i: int) -> void:
	var c := enemy_pos(e)
	var off := Vector2(0, sin(time * 3.0 + i * 1.7) * 5.0)
	if e.bump_t > 0.0:
		off.y += sin(PI * (1.0 - e.bump_t)) * 50.0
	var rot := 0.0
	if downed.has(e):
		rot = PI / 2.0
		off = Vector2(0, 40)
	draw_ellipse(c + Vector2(0, 85), 75.0, 16.0, Color(0, 0, 0, 0.5))
	var tint := Color.WHITE
	if e.flash_t > 0.0:
		tint = Color(1.0 + 2.5 * e.flash_t, 1.0 + 0.8 * e.flash_t, 1.0 + 0.8 * e.flash_t)
	draw_spr(e.sprite, c + off, 144.0, tint, rot)

	if phase == "target" and i == target_index:
		var ty := c.y - 125.0 + sin(time * 7.0) * 6.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - 18, ty), Vector2(c.x + 18, ty), Vector2(c.x, ty + 24)]), GOLD)

	# Nom, PV et faiblesse sous l'ennemi.
	var y := c.y + 120.0
	draw_text_outlined(Vector2(c.x - 150, y), main.capitalize_first(e.name), 24, Color.WHITE, 300)
	var w := 170.0
	draw_rect(Rect2(c.x - w / 2, y + 10, w, 12), Color("2a1420"))
	draw_rect(Rect2(c.x - w / 2, y + 10, w * maxi(e.hp, 0) / e.max_hp, 12), RED)
	var weak_text := "Faible : %s" % (e.weak if main.known_weak.has(e.name) else "?")
	if main.known_resist.has(e.name):
		weak_text += "   Résiste : %s" % e.resist
	draw_text_outlined(Vector2(c.x - 150, y + 46), weak_text, 17, Color("c8c8e0"), 300)
	if downed.has(e):
		draw_text_outlined(Vector2(c.x - 150, y - 30), "À TERRE", 22, GOLD, 300)


func draw_player_panel() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(930, 690), Vector2(SCREEN.x + 20, 650), Vector2(SCREEN.x + 20, SCREEN.y + 20), Vector2(890, SCREEN.y + 20)]),
		Color(0, 0, 0, 0.78))
	draw_colored_polygon(PackedVector2Array([
		Vector2(930, 690), Vector2(SCREEN.x + 20, 650), Vector2(SCREEN.x + 20, 658), Vector2(929, 698)]), GOLD)
	var p = main.player
	var tint := Color.WHITE
	if p.flash_t > 0.0:
		tint = Color(1.0 + 2.5 * p.flash_t, 1.0 + 0.8 * p.flash_t, 1.0 + 0.8 * p.flash_t)
	draw_spr(SPR_HERO, player_pos() + Vector2(0, sin(time * 2.5) * 3.0), 120.0, tint)
	var x := 1090.0
	draw_string(font, Vector2(x, 745), "HÉROS   Niv. %d" % main.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	draw_bar(Vector2(x, 762), "PV", p.hp, p.max_hp, RED)
	draw_bar(Vector2(x, 806), "PM", p.sp, p.max_sp, Color("4a8cff"))
	if guarding:
		draw_string(font, Vector2(x, 880), "EN GARDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GOLD)


func draw_bar(pos: Vector2, label: String, value: int, max_value: int, color: Color) -> void:
	var w := 300.0
	draw_rect(Rect2(pos, Vector2(w, 26)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(pos, Vector2(w * clampf(float(value) / max_value, 0.0, 1.0), 26)), color)
	draw_string(font, pos + Vector2(8, 20), "%s  %d / %d" % [label, value, max_value],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)


func draw_menu() -> void:
	var opts := menu_options()
	for i in opts.size():
		var y := 600.0 + i * 52.0 - (52.0 if opts.size() > 5 else 0.0)
		var x := 50.0 + i * 14.0
		var selected := i == menu_index
		var bg := Color(0, 0, 0, 0.75)
		var fg := Color.WHITE
		if selected:
			bg = GOLD if phase == "menu" else Color(0.55, 0.47, 0.2)
			fg = INK
		if opts[i] == "ASSAUT GÉNÉRAL" and not selected:
			fg = RED
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y), Vector2(x + 330, y), Vector2(x + 310, y + 44), Vector2(x - 20, y + 44)]), bg)
		draw_string(font, Vector2(x + 18, y + 32), opts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, fg)

	if phase in ["skill", "target"] and not (phase == "target" and pending.is_empty()):
		draw_skill_list()
	elif phase == "item":
		draw_side_panel(["Potion de soin   x%d" % main.potions], 0,
			"Rend 15 PV. (Entrée : utiliser, Échap : retour)", [main.potions > 0])


func draw_skill_list() -> void:
	var skills := known_skills()
	var names := []
	var usable := []
	for row: Array in skills:
		names.append("%s   (%s)   %d PM" % [row[0], row[1], row[2]])
		usable.append(main.player.sp >= int(row[2]))
	var desc: String = skills[skill_index][6] + "  (Échap : retour)"
	draw_side_panel(names, skill_index, desc, usable)


func draw_side_panel(rows: Array, selected: int, desc: String, usable: Array) -> void:
	var x := 440.0
	var y0 := 540.0
	var h := 40.0 * rows.size() + 70.0
	draw_rect(Rect2(x, y0, 460, h), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(x, y0, 6, h), GOLD)
	for i in rows.size():
		var y := y0 + 14 + i * 40.0
		var fg := Color.WHITE if usable[i] else Color(0.5, 0.5, 0.6)
		if i == selected:
			draw_rect(Rect2(x + 10, y, 440, 34), GOLD if phase != "target" else Color(0.55, 0.47, 0.2))
			fg = INK
		draw_string(font, Vector2(x + 22, y + 25), rows[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, fg)
	draw_string(font, Vector2(x + 16, y0 + h - 18), desc, HORIZONTAL_ALIGNMENT_LEFT, 430, 16, Color("c8c8e0"))


func draw_message_bar() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-20, 24), Vector2(SCREEN.x + 20, 24), Vector2(SCREEN.x + 20, 80), Vector2(-20, 92)]),
		Color(0, 0, 0, 0.75))
	draw_string(font, Vector2(40, 66), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)


func draw_text_outlined(pos: Vector2, text: String, size: int, color: Color, width: float) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(points, color)


## Dessine une image de la planche, centrée, à la taille voulue (et éventuellement tournée).
func draw_spr(index: int, center: Vector2, size: float, tint := Color.WHITE, rot := 0.0) -> void:
	var src := Rect2(
		(index % SHEET_COLUMNS) * SPRITE_PX,
		floori(index / float(SHEET_COLUMNS)) * SPRITE_PX,
		SPRITE_PX, SPRITE_PX)
	draw_set_transform(center, rot, Vector2.ONE)
	draw_texture_rect_region(SPRITES, Rect2(-size / 2.0, -size / 2.0, size, size), src, tint)
	draw_set_transform(Vector2.ZERO)
