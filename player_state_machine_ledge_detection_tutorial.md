# Godot 4: Robust Ledge Detection in a Node-Based `PlayerStateMachine` (Ground/Air/ClimbUp)

This tutorial adapts ledge detection to your current architecture in:

- `res://features/player/player_state_machine.gd`
- `res://features/player/player_ground_state.gd`
- `res://features/player/player_air_state.gd`
- `res://features/player/player_climb_up_state.gd`

It does **not** introduce a `Hang` state. It keeps your existing 3-state flow and tween-based climb.

---

## 1) Current Architecture Mapping

Your concrete classes map to the tutorial like this:

| Role | Your Class | Responsibility |
|---|---|---|
| State machine owner | `PlayerStateMachine` | Holds current state, delegates frame/physics, routes `to_ground/to_air/to_climb_up` |
| Base state API | `PlayerState` | Shared accessors (`player`, `state`, `transform`) and virtual hooks |
| Ground locomotion | `PlayerGroundState` | Walk/idle/jump decision point |
| Air locomotion | `PlayerAirState` | Gravity + air control + landing |
| Climb execution | `PlayerClimbUpState` | Ledge validation (`can_enter`) + climb tween |

Important existing entrypoint (keep this): jump in `PlayerGroundState.process_physics()` tries climb first:

```gdscript
if player.wants_to_jump():
	if state.to_climb_up():
		return

	player.velocity.y = jump_velocity
	state.to_air()
	return
```

So the climb gate remains `PlayerClimbUpState.can_enter()`.

---

## 2) Where Detection Lives

Put all ledge detection logic in `PlayerClimbUpState`.

- `can_enter()` performs detection.
- If detection succeeds, cache `_climb_up_target_point`.
- `on_enter()` uses the cached point for the existing two-phase tween.

This keeps `PlayerGroundState` and `PlayerAirState` simple and unchanged.

---

## 3) Detection Design (Two Rays + Clearance)

A ledge is valid only if all checks pass:

1. Forward wall hit exists.
2. A walkable top surface exists above that wall (top-down ray).
3. Height is inside your climb window (`climb_up_min_height..climb_up_max_height`).
4. Capsule fits at destination (clearance query).

All casts use `Data.CLIMBABLE_MASK` and `direct_space_state`.

---

## 4) `PlayerClimbUpState` Tutorial Version

Use this as the adapted tutorial script blueprint (documentation snippet, not applied automatically):

```gdscript
class_name PlayerClimbUpState
extends PlayerState

@export var climb_up_min_height := 0.3
@export var climb_up_max_height := 2.0
@export var climb_up_step_forward_length := 0.25

# Ledge detection tuning
@export var wall_check_distance := 0.7
@export var wall_check_height := 1.0
@export var top_check_up := 1.2
@export var top_check_inset := 0.25
@export var top_check_down := 2.2
@export var min_floor_dot := 0.7
@export var max_wall_up_dot := 0.2
@export var skin := 0.02
@export var debug_seconds := 3.0

var _climb_up_target_point := Vector3.ZERO


func can_enter() -> bool:
	var ledge := _find_ledge()
	if ledge.is_empty():
		_climb_up_target_point = Vector3.ZERO
		return false

	_climb_up_target_point = ledge["target_point"]
	return true


func on_enter(_previous_state: PlayerState) -> void:
	var rise_tween := create_tween()
	rise_tween.tween_property(player, "transform:origin:y", _climb_up_target_point.y + 0.05, 0.3)
	rise_tween.set_ease(Tween.EASE_OUT)
	await rise_tween.finished

	# Keep your existing forward step behavior.
	var forward_offset := transform.basis.x * climb_up_step_forward_length
	var target_with_offset := _climb_up_target_point + forward_offset

	var forward_tween := create_tween()
	forward_tween.tween_property(player, "transform:origin", target_with_offset, 0.2)
	forward_tween.set_ease(Tween.EASE_IN)
	forward_tween.set_trans(Tween.TRANS_QUAD)
	await forward_tween.finished

	_exit_climb_up_state()


func process_frame(_delta: float) -> void:
	if not has_climbing_target():
		_exit_climb_up_state()


func has_climbing_target() -> bool:
	return _climb_up_target_point != Vector3.ZERO


func _exit_climb_up_state() -> void:
	_climb_up_target_point = Vector3.ZERO

	if player.is_on_floor():
		state.to_ground()
	else:
		state.to_air()


func _find_ledge() -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var up := Vector3.UP

	# Your project's forward convention for player motion/facing.
	var forward := transform.basis.x
	forward.y = 0.0
	forward = forward.normalized()
	if forward == Vector3.ZERO:
		return {}

	# 1) Wall ray
	var wall_from := transform.origin + up * wall_check_height
	var wall_to := wall_from + forward * wall_check_distance
	var wall_hit := _ray(space, wall_from, wall_to)
	if wall_hit.is_empty():
		return {}

	var wall_normal: Vector3 = wall_hit["normal"]
	if abs(wall_normal.dot(up)) > max_wall_up_dot:
		return {}

	# 2) Top-down ray
	var top_from := wall_hit["position"] + up * top_check_up - wall_normal * top_check_inset
	var top_to := top_from - up * top_check_down
	var top_hit := _ray(space, top_from, top_to)
	if top_hit.is_empty():
		return {}

	var top_normal: Vector3 = top_hit["normal"]
	if top_normal.dot(up) < min_floor_dot:
		return {}

	# 3) Height window
	var ledge_height := top_hit["position"].y - transform.origin.y
	if ledge_height < climb_up_min_height or ledge_height > climb_up_max_height:
		return {}

	# 4) Capsule clearance at stand center
	var capsule := (player.get_node(^"Collision") as CollisionShape3D).shape as CapsuleShape3D
	var stand_center := top_hit["position"] + up * (capsule.height * 0.5 + skin)
	stand_center += wall_normal * (capsule.radius + skin)
	if not _capsule_fits_at(space, capsule, stand_center):
		return {}

	return {
		"target_point": top_hit["position"],
		"top_point": top_hit["position"],
		"wall_normal": wall_normal,
		"stand_center": stand_center,
	}


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Data.CLIMBABLE_MASK, [player.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false

	var hit := space.intersect_ray(query)
	Debugger.draw_ray_and_collision(query, hit, debug_seconds)
	return hit


func _capsule_fits_at(
	space: PhysicsDirectSpaceState3D,
	capsule: CapsuleShape3D,
	center: Vector3,
) -> bool:
	var p := PhysicsShapeQueryParameters3D.new()
	p.shape = capsule
	p.transform = Transform3D(Basis.IDENTITY, center)
	p.collision_mask = Data.CLIMBABLE_MASK
	p.exclude = [player.get_rid()]
	p.collide_with_areas = false
	p.collide_with_bodies = true
	p.margin = skin

	var hits := space.intersect_shape(p, 1)
	return hits.is_empty()
```

Notes:

- `can_enter()` is now the authoritative climb gate.
- `on_enter()` keeps your existing rise-then-forward tween flow.
- `target_point` is still a world point on top of the ledge, matching your current tween approach.

---

## 5) State-Machine Integration (No Structural Changes)

### `PlayerGroundState`

No behavior change required. It already tries `state.to_climb_up()` before normal jump.

### `PlayerAirState`

No ledge-specific change required. Keep gravity/air-control/landing as-is.

### `PlayerStateMachine`

No API change required. It already uses `can_enter()` through `transition_to(...)`.

Public state APIs remain:

- `PlayerStateMachine.to_climb_up()`
- `PlayerStateMachine.to_air()`
- `PlayerStateMachine.to_ground()`

---

## 6) Tuning Defaults for Your Scene

Based on your current player capsule (`height=1.5`, `radius=0.32`) and existing climb range:

| Variable | Start Value | Why |
|---|---:|---|
| `climb_up_min_height` | `0.3` | Keeps tiny bumps from triggering climb |
| `climb_up_max_height` | `2.0` | Matches your existing upper bound |
| `wall_check_distance` | `0.7` | Similar reach to your current forward ray |
| `wall_check_height` | `1.0` | Rough chest-level check for 1.5m capsule |
| `top_check_up` | `1.2` | Starts down-ray above edge reliably |
| `top_check_inset` | `0.25` | Samples onto the top instead of wall lip |
| `top_check_down` | `2.2` | Enough depth to find top surface |
| `min_floor_dot` | `0.7` | Accepts up to ~45 degree slope |
| `max_wall_up_dot` | `0.2` | Rejects floor-like wall hits |
| `skin` | `0.02` | Prevents near-contact clipping |
| `climb_up_step_forward_length` | `0.25` | Keep your current end-of-climb forward push |

---

## 7) Debug + Validation

Keep ray visualization via:

```gdscript
Debugger.draw_ray_and_collision(query, hit, debug_seconds)
```

Add point markers for decision quality:

- Rejected top candidate: red point.
- Accepted top point: green point.
- Final `_climb_up_target_point`: yellow point.

If you use `debug_draw_3d`, draw these each frame for a short lifetime during testing.

Common failure signatures:

1. No wall hits at all:
- Usually wrong collision mask/layer setup (`Data.CLIMBABLE_MASK` vs object layer).

2. Wall hit exists but no top hit:
- `top_check_up` too low or `top_check_inset` too small.

3. Top hit exists but climb denied:
- Height outside `[climb_up_min_height, climb_up_max_height]`.

4. All rays pass but still denied:
- Clearance check failing (`_capsule_fits_at`) due low ceiling/overhang.

5. Intermittent misses while moving:
- Verify project forward axis assumption (`transform.basis.x`) matches your control orientation.

---

## 8) Test Matrix (Deterministic)

| Scenario | Setup | Expected States |
|---|---|---|
| Flat jump | No wall in front, press jump | `Ground -> Air -> Ground` |
| Valid ledge jump | Climbable wall with valid top and clearance | `Ground -> ClimbUp -> Ground` |
| Too-high obstacle | Top above `climb_up_max_height` | `Ground -> Air` |
| Missing top surface | Forward wall hit but no valid top-down hit | `Ground -> Air` |
| Blocked headroom | Valid ledge but ceiling blocks capsule fit | `Ground -> Air` |
| Walk-off edge | Leave platform without jump | `Ground -> Air -> Ground` |

---

## 9) Implementation Checklist

1. Move robust detection helpers into `PlayerClimbUpState`.
2. Keep climb gate in `can_enter()`.
3. Keep existing two-phase tween in `on_enter()`.
4. Keep `Ground/Air` flow unchanged.
5. Validate with the matrix above and tune exported values.

This gives you stronger ledge reliability without changing your state-machine shape.
