# INSIDE/LIMBO-Style Ladders in Godot 4 (2.5D, Node-Based State Machine)

This tutorial implements a cinematic ladder system using a dedicated ladder rail actor and a dedicated ladder state.

It is intentionally built for this architecture:

- `Player` + node-based `PlayerStateMachine`
- `PlayerGroundState`, `PlayerAirState`, `PlayerClimbUpState`, `PlayerLadderState`
- Godot 4.6 + Jolt Physics

The result is deterministic and stable (no ladder jitter from physics), with clean transitions and re-grab protection.

## How to read code examples

All snippets below are a **reference implementation** for the target ladder architecture in this tutorial.

- They are designed to be copied into files under `/Users/akodkod/Developer/GameDev/crimes/`.
- If your current project code differs, adapt names/signatures but keep the same data flow.

---

## Why this architecture

### Rail-state approach (recommended)

A ladder is represented as a rail segment (`Bottom` to `Top`) and a state (`PlayerLadderState`) that owns movement while climbing.

Benefits:

- Deterministic alignment to the ladder line
- No `move_and_slide()` fighting climb motion
- Explicit enter/exit rules
- Easy cinematic tuning

### Raycast-only approach (not used here)

Raycast-only ladders can work but often require ad-hoc correction every frame. For INSIDE/LIMBO-style feel, explicit rail + explicit state is more predictable.

---

## Step 1: Create the reusable Ladder actor

### Files

- `/Users/akodkod/Developer/GameDev/crimes/features/ladder/ladder.gd`
- `/Users/akodkod/Developer/GameDev/crimes/features/ladder/ladder.tscn`

### Scene tree

```text
Ladder (Node3D, script: ladder.gd)
├── RailArea (Area3D)
│   └── Collision (CollisionShape3D, BoxShape3D)
├── Bottom (Marker3D)
└── Top (Marker3D)
```

### GDScript: Ladder class skeleton + rail API

```gdscript
class_name Ladder
extends Node3D

@export var trigger_area: Area3D
@export var bottom_marker: Marker3D
@export var top_marker: Marker3D
@export var default_mount_distance := 0.8

func get_bottom_point() -> Vector3:
	return bottom_marker.global_position if bottom_marker else global_position


func get_top_point() -> Vector3:
	return top_marker.global_position if top_marker else global_position + Vector3.UP


func get_axis() -> Vector3:
	var delta: Vector3 = get_top_point() - get_bottom_point()
	if delta == Vector3.ZERO:
		return Vector3.UP
	return delta.normalized()


func point_at_t(t: float) -> Vector3:
	var clamped_t := clampf(t, 0.0, 1.0)
	return get_bottom_point().lerp(get_top_point(), clamped_t)


func closest_t(world_pos: Vector3) -> float:
	var bottom: Vector3 = get_bottom_point()
	var axis: Vector3 = get_axis()
	var length := bottom.distance_to(get_top_point())
	if length <= 0.001:
		return 0.0
	var projection := (world_pos - bottom).dot(axis)
	return clampf(projection / length, 0.0, 1.0)
```

### GDScript: Trigger wiring (ladder informs player candidate system)

```gdscript
func _ready() -> void:
	if not trigger_area:
		trigger_area = get_node_or_null(^"RailArea")
	if not bottom_marker:
		bottom_marker = get_node_or_null(^"Bottom")
	if not top_marker:
		top_marker = get_node_or_null(^"Top")

	if not trigger_area:
		push_error("Ladder is missing RailArea")
		return

	if not trigger_area.body_entered.is_connected(_on_trigger_body_entered):
		trigger_area.body_entered.connect(_on_trigger_body_entered)
	if not trigger_area.body_exited.is_connected(_on_trigger_body_exited):
		trigger_area.body_exited.connect(_on_trigger_body_exited)


func _on_trigger_body_entered(body: Node3D) -> void:
	if body is not Player:
		return
	(body as Player).on_ladder_trigger_entered(self)


func _on_trigger_body_exited(body: Node3D) -> void:
	if body is not Player:
		return
	(body as Player).on_ladder_trigger_exited(self)
```

---

## Step 2: Input setup

### File

- `/Users/akodkod/Developer/GameDev/crimes/scripts/data.gd`

### GDScript: ladder input aliases

```gdscript
class_name Data

const INPUT_MOVE_LEFT := "move_left"
const INPUT_MOVE_RIGHT := "move_right"
const INPUT_MOVE_FORWARD := "move_forward"
const INPUT_MOVE_BACKWARD := "move_backward"

const INPUT_CLIMB_UP := INPUT_MOVE_FORWARD
const INPUT_CLIMB_DOWN := INPUT_MOVE_BACKWARD
const INPUT_JUMP := "jump"
```

### project.godot excerpt (text)

```text
[input]
move_forward = W + Up Arrow
move_backward = S + Down Arrow
```

### 2.5D locomotion guard example

Keep horizontal locomotion independent from climb input:

```gdscript
func get_input_direction() -> Vector3:
	var horizontal_input := Input.get_axis(Data.INPUT_MOVE_LEFT, Data.INPUT_MOVE_RIGHT)
	if is_zero_approx(horizontal_input):
		return Vector3.ZERO

	var camera_right := player.camera.transform.basis.x
	return (camera_right * horizontal_input).normalized()
```

---

## Step 3: Player candidate tracking

### File

- `/Users/akodkod/Developer/GameDev/crimes/features/player/player.gd`

### GDScript: candidate state + enter/exit handlers + nearest selection

```gdscript
class_name Player
extends Character

var _ladder_candidates: Array[Ladder] = []
var _active_ladder_candidate: Ladder
var _ladder_regrab_blocked_until_msec := 0


func on_ladder_trigger_entered(ladder: Ladder) -> void:
	if not ladder:
		return
	if _ladder_candidates.has(ladder):
		return

	_ladder_candidates.append(ladder)
	_refresh_active_ladder_candidate()


func on_ladder_trigger_exited(ladder: Ladder) -> void:
	if not ladder:
		return

	_ladder_candidates.erase(ladder)
	if _active_ladder_candidate == ladder:
		_active_ladder_candidate = null

	_refresh_active_ladder_candidate()


func get_active_ladder_candidate() -> Ladder:
	_refresh_active_ladder_candidate()
	return _active_ladder_candidate


func _refresh_active_ladder_candidate() -> void:
	var best_ladder: Ladder
	var best_distance: float = INF

	for ladder in _ladder_candidates:
		if not is_instance_valid(ladder) or not ladder.is_inside_tree():
			continue

		var t := ladder.closest_t(global_position)
		var distance_to_rail := global_position.distance_to(ladder.point_at_t(t))
		if distance_to_rail < best_distance:
			best_distance = distance_to_rail
			best_ladder = ladder

	_active_ladder_candidate = best_ladder
```

### GDScript: cooldown helpers

```gdscript
func can_grab_ladder() -> bool:
	return Time.get_ticks_msec() >= _ladder_regrab_blocked_until_msec


func block_ladder_regrab(duration_seconds: float) -> void:
	var duration_msec := int(maxf(duration_seconds, 0.0) * 1000.0)
	_ladder_regrab_blocked_until_msec = Time.get_ticks_msec() + duration_msec


func wants_to_climb_up() -> bool:
	return Input.is_action_pressed(Data.INPUT_CLIMB_UP)


func wants_to_climb_down() -> bool:
	return Input.is_action_pressed(Data.INPUT_CLIMB_DOWN)
```

---

## Step 4: Add the ladder state

### Files

- `/Users/akodkod/Developer/GameDev/crimes/features/player/player_ladder_state.gd`
- `/Users/akodkod/Developer/GameDev/crimes/features/player/player_state_machine.gd`
- `/Users/akodkod/Developer/GameDev/crimes/features/player/player.tscn`

### GDScript: state machine registration + APIs

```gdscript
class_name PlayerStateMachine
extends Node

var ground: PlayerGroundState
var air: PlayerAirState
var climb_up: PlayerClimbUpState
var ladder: PlayerLadderState

func _ready() -> void:
	for child in get_children():
		if child is PlayerGroundState:
			ground = child
		elif child is PlayerAirState:
			air = child
		elif child is PlayerClimbUpState:
			climb_up = child
		elif child is PlayerLadderState:
			ladder = child


func try_enter_ladder() -> bool:
	return _try_enter(ladder)


func is_ladder() -> bool:
	return current_state == ladder
```

### Scene tree addition

```text
PlayerStateMachine
├── PlayerGroundState
├── PlayerAirState
├── PlayerClimbUpState
└── PlayerLadderState
```

---

## Step 5: Enter rules and transition priorities

### Ground -> Ladder example

```gdscript
# PlayerGroundState.gd
func process_physics(delta: float) -> void:
	if not player.is_on_floor():
		state.try_enter_air()
		return

	# Ladder entry has priority when climb input is active.
	if _try_enter_ladder():
		return

	if player.wants_to_jump():
		if state.try_enter_climb_up():
			return
		player.velocity.y = jump_velocity
		state.try_enter_air()
		return

	var input_direction := get_input_direction()
	_apply_velocity(input_direction, delta)


func _try_enter_ladder() -> bool:
	if not player.can_grab_ladder():
		return false
	if not (player.wants_to_climb_up() or player.wants_to_climb_down()):
		return false
	return state.try_enter_ladder()
```

### Air -> Ladder before climb-up example

```gdscript
# PlayerAirState.gd
func process_physics(delta: float) -> void:
	if player.is_on_floor():
		state.try_enter_ground()
		return

	player.velocity += player.get_gravity() * delta
	_apply_air_control(get_input_direction(), delta)
	player.move_and_slide()

	# Air ladder catch first.
	if state.try_enter_ladder():
		return

	# Then ledge climb fallback.
	state.try_enter_climb_up()
```

### PlayerLadderState.can_enter() gating example

```gdscript
func can_enter() -> bool:
	if not player.can_grab_ladder():
		return false

	var candidate := player.get_active_ladder_candidate()
	if not candidate:
		return false
	if not candidate.is_body_inside(player):
		return false

	var vertical_input := _get_vertical_input()

	if state.is_ground():
		if vertical_input > 0.0 and candidate.can_mount_from_bottom(global_position, bottom_entry_max_distance):
			_prepare_entry(candidate, 0.0)
			return true
		if vertical_input < 0.0 and candidate.can_mount_from_top(global_position, top_entry_max_distance):
			_prepare_entry(candidate, 1.0)
			return true
		return false

	if state.is_air():
		if absf(vertical_input) < 0.01:
			return false
		if player.velocity.y < -air_catch_max_fall_speed:
			return false
		_prepare_entry(candidate, candidate.closest_t(global_position))
		return true

	return false
```

---

## Step 6: `PlayerLadderState` behavior

### File

- `/Users/akodkod/Developer/GameDev/crimes/features/player/player_ladder_state.gd`

### GDScript: enter + tick + exits + detach

```gdscript
class_name PlayerLadderState
extends PlayerState

@export var climb_speed := 2.0
@export var snap_speed := 18.0
@export var endpoint_deadzone := 0.04
@export var top_exit_forward_offset := 0.35
@export var bottom_exit_backward_offset := 0.15
@export var detach_push_horizontal_speed := 2.0
@export var detach_push_vertical_speed := 2.5
@export var regrab_cooldown_seconds := 0.2

var _ladder: Ladder
var _rail_t := 0.0

func on_enter(_previous_state: PlayerState) -> void:
	if not _ladder:
		_exit_to_fallback_state()
		return

	player.velocity = Vector3.ZERO
	_snap_player_to_rail(1.0)


func process_physics(delta: float) -> void:
	if not _ladder or not is_instance_valid(_ladder) or not _ladder.is_inside_tree():
		_exit_to_fallback_state()
		return

	if player.wants_to_jump():
		_detach_to_air()
		return

	var vertical_input := _get_vertical_input()
	var length := maxf(_ladder.get_bottom_point().distance_to(_ladder.get_top_point()), 0.001)

	if absf(vertical_input) >= 0.01:
		_rail_t += (vertical_input * climb_speed * delta) / length

	_rail_t = clampf(_rail_t, 0.0, 1.0)

	if _rail_t >= 1.0 - endpoint_deadzone and vertical_input > 0.0:
		_exit_top_to_ground()
		return

	if _rail_t <= endpoint_deadzone and vertical_input < 0.0:
		_exit_bottom_to_ground()
		return

	_snap_player_to_rail(delta)


func on_exit(_next_state: PlayerState) -> void:
	_ladder = null
	_rail_t = 0.0


func _exit_top_to_ground() -> void:
	var n := _ladder.get_axis().cross(Vector3.UP).cross(_ladder.get_axis()).normalized()
	if n == Vector3.ZERO:
		n = -_ladder.global_transform.basis.z.normalized()

	player.global_position = _ladder.get_top_point() + n * top_exit_forward_offset
	player.velocity = Vector3.ZERO
	state.try_enter_ground()


func _exit_bottom_to_ground() -> void:
	var n := -_ladder.global_transform.basis.z.normalized()
	player.global_position = _ladder.get_bottom_point() - n * bottom_exit_backward_offset
	player.velocity = Vector3.ZERO
	state.try_enter_ground()


func _detach_to_air() -> void:
	var away := _get_detach_direction()
	player.velocity = away * detach_push_horizontal_speed
	player.velocity.y = detach_push_vertical_speed
	player.block_ladder_regrab(regrab_cooldown_seconds)
	state.try_enter_air()
```

---

## Step 7: Robustness guards

### GDScript: cooldown, invalid ladder fallback, input deadzone

```gdscript
func _get_vertical_input() -> float:
	# Small input noise is ignored by caller threshold.
	return Input.get_action_strength(Data.INPUT_CLIMB_UP) - Input.get_action_strength(Data.INPUT_CLIMB_DOWN)


func _snap_player_to_rail(delta: float) -> void:
	var target := _ladder.point_at_t(_rail_t)
	var blend := clampf(snap_speed * delta, 0.0, 1.0)
	player.global_position = player.global_position.lerp(target, blend)
	player.velocity = Vector3.ZERO


func _exit_to_fallback_state() -> void:
	# If ladder disappears mid-climb, fail safely.
	if player.is_on_floor():
		state.try_enter_ground()
	else:
		state.try_enter_air()


func can_enter() -> bool:
	if not player.can_grab_ladder():
		return false
	# ...rest of ladder-enter checks...
	return true
```

---

## Step 8: Debug and tuning

### GDScript: rail debug draw

```gdscript
@export var debug_duration := 0.05

func _draw_debug() -> void:
	if not _ladder:
		return

	var bottom := _ladder.get_bottom_point()
	var top := _ladder.get_top_point()
	var current := _ladder.point_at_t(_rail_t)

	DebugDraw3D.draw_arrow(bottom, top, Color.YELLOW, 0.03, true, debug_duration)
	Debugger.draw_sphere(current, 0.08, Color.CYAN, debug_duration)
```

Useful tunables:

- `climb_speed`
- `snap_speed`
- `bottom_entry_max_distance`
- `top_entry_max_distance`
- `endpoint_deadzone`
- `air_catch_max_fall_speed`
- `detach_push_horizontal_speed`
- `detach_push_vertical_speed`
- `regrab_cooldown_seconds`

---

## Step 9: Verification checklist

Use these exact pass/fail scenarios:

1. Enter from bottom while grounded and pressing climb-up.
2. Enter from top while grounded and pressing climb-down.
3. Climb full length up and down without jitter or drift.
4. Jump detach mid-ladder transitions to `Air` and does not immediately reattach.
5. Reaching top exits cleanly to `Ground` with correct placement.
6. Reaching bottom exits cleanly to `Ground`.
7. Ladder removed/disabled while climbing triggers safe fallback exit.
8. Ledge-climb and ladder entry do not fight when both are nearby.
9. No input on ladder keeps player stable on rail (no gravity slide).
10. Input spam near endpoints does not cause state flicker.

---

## Quick setup in a level

1. Instance `/Users/akodkod/Developer/GameDev/crimes/features/ladder/ladder.tscn` into your test scene.
2. Move `Bottom` to the foot of the ladder and `Top` to the top exit height.
3. Resize `RailArea/Collision` to cover the full climb path.
4. Run and test with `W/S` (or `Up/Down`) and `Jump` detach.

---

## Complete reference snippet map

- **Ladder actor + rail math**: Step 1 (`Ladder` class skeleton and rail API)
- **Trigger communication**: Step 1 (`_on_trigger_body_entered/exited`)
- **Input aliases**: Step 2 (`Data` constants)
- **Player candidate system**: Step 3 (`_ladder_candidates`, refresh + cooldown)
- **State machine ladder hooks**: Step 4 (`var ladder`, `try_enter_ladder`, `is_ladder`)
- **Entry priority logic**: Step 5 (ground/air transition snippets)
- **Ladder runtime flow**: Step 6 (`on_enter`, `process_physics`, exit/detach helpers)
- **Safety guards**: Step 7 (fallback, cooldown, deadzone)
- **Debug visualization**: Step 8 (`_draw_debug`)
