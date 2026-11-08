extends RefCounted
## Génère un donjon de salles reliées par des couloirs.
## Chaque nouvelle salle est reliée à la précédente, donc tout le donjon est accessible.

const WALL := 0
const FLOOR := 1

var width: int
var height: int
var tiles := PackedByteArray()
var rooms: Array[Rect2i] = []


func _init(w: int, h: int) -> void:
	width = w
	height = h


func generate(rng: RandomNumberGenerator, max_rooms: int, min_size: int, max_size: int) -> void:
	tiles = PackedByteArray()
	tiles.resize(width * height)
	tiles.fill(WALL)
	rooms.clear()

	for i in max_rooms:
		var w := rng.randi_range(min_size, max_size)
		var h := rng.randi_range(min_size, max_size)
		var x := rng.randi_range(1, width - w - 2)
		var y := rng.randi_range(1, height - h - 2)
		var room := Rect2i(x, y, w, h)

		var overlaps := false
		for other in rooms:
			if room.grow(1).intersects(other):
				overlaps = true
				break
		if overlaps:
			continue

		_carve_room(room)
		if not rooms.is_empty():
			var a := room_center(rooms[-1])
			var b := room_center(room)
			if rng.randi() % 2 == 0:
				_carve_h(a.x, b.x, a.y)
				_carve_v(a.y, b.y, b.x)
			else:
				_carve_v(a.y, b.y, a.x)
				_carve_h(a.x, b.x, b.y)
		rooms.append(room)


func room_center(room: Rect2i) -> Vector2i:
	return room.position + room.size / 2


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and tiles[c.y * width + c.x] == FLOOR


func is_opaque(c: Vector2i) -> bool:
	return not is_walkable(c)


func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			tiles[y * width + x] = FLOOR


func _carve_h(x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		tiles[y * width + x] = FLOOR


func _carve_v(y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		tiles[y * width + x] = FLOOR
