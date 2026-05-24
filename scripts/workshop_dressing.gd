# Workshop Dressing — procedurally spawns oversized industrial props
# so the play area feels like a giant workshop with the player tiny
# inside it.
#
# Props are placed on a deterministic seeded grid so runs feel the same
# from session to session. All props are static — no physics, no
# scripts — purely visual.

extends Node3D

# Tunables
@export var rng_seed:        int = 4242
@export var bolt_count:      int = 14
@export var screw_count:     int = 10
@export var pallet_count:    int = 22
@export var beam_count:      int = 6
@export var crate_count:     int = 18
@export var spawn_min_r:     float = 32.0   # stay beyond enemy spawn radius (29m) so AI doesn't snag
@export var spawn_max_r:     float = 110.0

# Material cache so we share materials across many MeshInstances
var _mat_iron:    StandardMaterial3D
var _mat_brass:   StandardMaterial3D
var _mat_wood:    StandardMaterial3D
var _mat_steel:   StandardMaterial3D
var _mat_hazard:  StandardMaterial3D
var _rng: RandomNumberGenerator

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = rng_seed
	_make_materials()
	_build_bolts()
	_build_screws()
	_build_pallets()
	_build_beams()
	_build_crates()
	_build_hazard_lanes()
	_build_workbench_perimeter()

func _make_materials() -> void:
	_mat_iron = StandardMaterial3D.new()
	_mat_iron.albedo_color = Color(0.38, 0.36, 0.34, 1)
	_mat_iron.metallic = 0.55
	_mat_iron.roughness = 0.55

	_mat_brass = StandardMaterial3D.new()
	_mat_brass.albedo_color = Color(0.65, 0.45, 0.18, 1)
	_mat_brass.metallic = 0.7
	_mat_brass.roughness = 0.42

	_mat_wood = StandardMaterial3D.new()
	_mat_wood.albedo_color = Color(0.42, 0.28, 0.16, 1)
	_mat_wood.metallic = 0.0
	_mat_wood.roughness = 0.92

	_mat_steel = StandardMaterial3D.new()
	_mat_steel.albedo_color = Color(0.55, 0.55, 0.58, 1)
	_mat_steel.metallic = 0.85
	_mat_steel.roughness = 0.3

	_mat_hazard = StandardMaterial3D.new()
	_mat_hazard.albedo_color = Color(0.92, 0.76, 0.18, 1)
	_mat_hazard.metallic = 0.0
	_mat_hazard.roughness = 0.85
	_mat_hazard.emission_enabled = true
	_mat_hazard.emission = Color(0.62, 0.48, 0.10, 1)
	_mat_hazard.emission_energy_multiplier = 0.15

# ── Bolts: tall iron cylinders capped with a wider hex head.
func _build_bolts() -> void:
	for i in range(bolt_count):
		var pos: Vector3 = _random_pos()
		var h: float = _rng.randf_range(7.0, 13.0)
		var shaft_r: float = _rng.randf_range(0.85, 1.4)
		var bolt_root := Node3D.new()
		bolt_root.position = pos
		add_child(bolt_root)
		# shaft
		var shaft := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = shaft_r
		sm.bottom_radius = shaft_r
		sm.height = h
		shaft.mesh = sm
		shaft.material_override = _mat_iron
		shaft.position = Vector3(0, h * 0.5, 0)
		bolt_root.add_child(shaft)
		# hex head — flat wide cylinder on top
		var head := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = shaft_r * 1.9
		hm.bottom_radius = shaft_r * 1.9
		hm.height = shaft_r * 0.8
		hm.radial_segments = 6
		head.mesh = hm
		head.material_override = _mat_iron
		head.position = Vector3(0, h + shaft_r * 0.4, 0)
		bolt_root.add_child(head)
		# random spin around Y
		bolt_root.rotation.y = _rng.randf() * TAU
		_add_static_collider_cylinder(bolt_root, shaft_r * 1.9, h)

# ── Screws: brass tapered cylinders standing point-down so the broad
# slotted head dominates. We render them upright like obelisks.
func _build_screws() -> void:
	for i in range(screw_count):
		var pos: Vector3 = _random_pos()
		var h: float = _rng.randf_range(6.0, 10.0)
		var top_r: float = _rng.randf_range(1.0, 1.7)
		var bot_r: float = top_r * 0.3
		var screw_root := Node3D.new()
		screw_root.position = pos
		add_child(screw_root)
		var taper := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = top_r
		cm.bottom_radius = bot_r
		cm.height = h
		taper.mesh = cm
		taper.material_override = _mat_brass
		taper.position = Vector3(0, h * 0.5, 0)
		screw_root.add_child(taper)
		# slotted head: a thin box across the top to suggest the slot
		var slot := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(top_r * 2.2, top_r * 0.18, top_r * 0.45)
		slot.mesh = bm
		slot.material_override = _mat_iron
		slot.position = Vector3(0, h + top_r * 0.12, 0)
		screw_root.add_child(slot)
		screw_root.rotation.y = _rng.randf() * TAU
		_add_static_collider_cylinder(screw_root, top_r, h)

# ── Pallets: stacked plank crates near the edges
func _build_pallets() -> void:
	for i in range(pallet_count):
		var pos: Vector3 = _random_pos()
		var stack: int = _rng.randi_range(1, 3)
		var pal_root := Node3D.new()
		pal_root.position = pos
		add_child(pal_root)
		for s in range(stack):
			var p := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(_rng.randf_range(2.5, 4.0),
							  _rng.randf_range(0.4, 0.8),
							  _rng.randf_range(2.5, 4.0))
			p.mesh = bm
			p.material_override = _mat_wood
			var lift: float = float(s) * (bm.size.y + 0.05)
			p.position = Vector3(0, bm.size.y * 0.5 + lift, 0)
			pal_root.add_child(p)
			if s == stack - 1:
				_add_static_collider_box(pal_root, bm.size,
					Vector3(0, bm.size.y * 0.5 + lift, 0))
		pal_root.rotation.y = _rng.randf() * TAU

# ── Steel beams: long horizontal I-beams, raised on small pylons
func _build_beams() -> void:
	for i in range(beam_count):
		var pos: Vector3 = _random_pos()
		var length: float = _rng.randf_range(18.0, 30.0)
		var beam_root := Node3D.new()
		beam_root.position = pos
		add_child(beam_root)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(length, 1.2, 1.2)
		beam.mesh = bm
		beam.material_override = _mat_steel
		beam.position = Vector3(0, 3.2, 0)
		beam_root.add_child(beam)
		# two pylons under it
		for sx in [-1, 1]:
			var py := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.55
			pm.bottom_radius = 0.55
			pm.height = 2.6
			py.mesh = pm
			py.material_override = _mat_iron
			py.position = Vector3(sx * (length * 0.4), 1.3, 0)
			beam_root.add_child(py)
		beam_root.rotation.y = _rng.randf() * TAU

# ── Crates: small wooden boxes piled
func _build_crates() -> void:
	for i in range(crate_count):
		var pos: Vector3 = _random_pos()
		var s: float = _rng.randf_range(1.1, 1.9)
		var c := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, s, s)
		c.mesh = bm
		c.material_override = _mat_wood
		c.position = pos + Vector3(0, s * 0.5, 0)
		c.rotation.y = _rng.randf() * TAU
		add_child(c)
		_add_static_collider_box(self, bm.size,
			c.position, c.rotation.y)

# ── Hazard lanes: yellow stripes radiating from center
func _build_hazard_lanes() -> void:
	for i in range(8):
		var angle: float = float(i) * (TAU / 8.0)
		var dx: float = cos(angle)
		var dz: float = sin(angle)
		# stripe from r=12 to r=90 in this direction
		var inner: float = 13.0
		var outer: float = 90.0
		var mid: float = (inner + outer) * 0.5
		var len: float = outer - inner
		var stripe := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.02, len)
		stripe.mesh = bm
		stripe.material_override = _mat_hazard
		stripe.position = Vector3(dx * mid, -0.49, dz * mid)
		stripe.rotation.y = -angle
		add_child(stripe)

# ── Workbench perimeter: huge table legs at the very edges, suggesting
# we're inside something built for a human
func _build_workbench_perimeter() -> void:
	var R: float = 130.0
	for i in range(8):
		var a: float = float(i) * (TAU / 8.0)
		var pos := Vector3(cos(a) * R, 0, sin(a) * R)
		var leg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 3.4
		cm.bottom_radius = 3.0
		cm.height = 50.0
		leg.mesh = cm
		leg.material_override = _mat_wood
		leg.position = pos + Vector3(0, 25.0, 0)
		add_child(leg)
		_add_static_collider_cylinder_at(leg.position, 3.4, 50.0)

# ── Utility: random point inside spawn ring
func _random_pos() -> Vector3:
	for _i in range(8):
		var a: float = _rng.randf() * TAU
		var r: float = sqrt(_rng.randf()) * (spawn_max_r - spawn_min_r) \
			+ spawn_min_r
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		return p
	return Vector3.ZERO

# ── Static colliders so Reaper doesn't walk through props
func _add_static_collider_cylinder(parent: Node, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	cs.shape = cap
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)

func _add_static_collider_cylinder_at(pos: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	body.global_position = pos
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h
	cs.shape = cap
	body.add_child(cs)

func _add_static_collider_box(parent: Node, size: Vector3,
		offset: Vector3, rot_y: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	body.position = offset
	body.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
