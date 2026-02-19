# Player State Machine Tutorial

A step-by-step guide to implementing a **node-based state machine** for the Player in Godot 4.6 with typed GDScript. No animations — prototype only.

---

## Overview

Games like LIMBO and INSIDE have discrete player modes: on the ground, in the air, climbing a ledge. A state machine formalises this — instead of growing `if`/`else` chains in `_physics_process`, each mode becomes its own class with explicit `enter()`, `exit()`, and `process()` methods.

### Why Only Three States?

It's tempting to make separate states for Idle, Walk, Jump, and Fall. But for a LIMBO/INSIDE prototype, that creates unnecessary noise:

- **Idle vs Walk** — the only difference is "is there input?". That's a simple `if` inside one state, not a meaningful mode change. Splitting them creates transitions every time the player taps or releases a key, with no payoff.
- **Jump vs Fall** — once airborne, the physics are identical: gravity applies, optional air control, land when `is_on_floor()`. A jump just means `enter()` applies an upward impulse. That's an entry condition, not a distinct behavioural mode.

Three states is the right granularity:

| State        | When                                       |
|--------------|--------------------------------------------|
| **Ground**   | On the floor — idle or walking              |
| **Air**      | Airborne — jumped or walked off a ledge     |
| **ClimbUp** | Mantling a ledge — tween controls position  |

You can always split states later if gameplay demands it (e.g. a dedicated Crouch state). Start simple.

### Why Node-Based?

Godot offers several state machine patterns. Here's why we use **one Node per state**:

| Approach       | Pros                                  | Cons                                        |
|----------------|---------------------------------------|---------------------------------------------|
| Enum + match   | Simple, single file                   | Grows unwieldy; no per-state `enter`/`exit` |
| Resource-based | Lightweight, no scene tree overhead   | Harder to wire in editor, no node signals   |
| **Node-based** | Editor-visible, animation-ready, typed transitions, per-state `enter`/`exit`, guards | Slightly more files |

Node-based states are visible in the scene tree, can reference sibling nodes (like AnimationPlayer), emit typed signals, and support `can_enter()` guards — exactly what a LIMBO/INSIDE-style player needs.

### Architecture

Three building blocks:

1. **`PlayerState`** — abstract base `Node`. Defines the virtual interface every state implements.
2. **`PlayerStateMachine`** — manager `Node`. Owns all states as children, delegates engine callbacks, handles transitions.
3. **Concrete states** — `PlayerGroundState`, `PlayerAirState`, `PlayerClimbUpState`.

### Final Player Scene Tree

```
Player (CharacterBody3D)
├── Body (MeshInstance3D)
│   └── Eyes (MeshInstance3D)
├── Collision (CollisionShape3D)
└── StateMachine (PlayerStateMachine)
    ├── Ground (PlayerGroundState)      ← initial_state
    ├── Air (PlayerAirState)
    └── ClimbUp (PlayerClimbUpState)
```

### File Layout

All state scripts live under `features/player/states/`:

| File                        | Class                  |
|-----------------------------|------------------------|
| `player_state.gd`          | `PlayerState`          |
| `player_state_machine.gd`  | `PlayerStateMachine`   |
| `player_ground_state.gd`   | `PlayerGroundState`    |
| `player_air_state.gd`      | `PlayerAirState`       |
| `player_climb_up_state.gd` | `PlayerClimbUpState`   |

---

## Step 1 — Create the Base `PlayerState` Class

Create `features/player/states/player_state.gd`.

This is the abstract base class. Every concrete state extends it and overrides the methods it needs. The state machine will call these methods — states never call `_process` or `_physics_process` themselves.

### Class Definition

| Property / Method                    | Type / Signature                          | Purpose                                                       |
|--------------------------------------|-------------------------------------------|---------------------------------------------------------------|
| `class_name`                         | `PlayerState`                             | Typed reference everywhere                                    |
| `extends`                            | `Node`                                    | Lives in the scene tree as a child of StateMachine             |
| `player`                             | `var player: Player`                      | Set by StateMachine in `_ready()`. All states access the Player through this. |
| `state_machine`                      | `var state_machine: PlayerStateMachine`   | Set by StateMachine in `_ready()`. Used to request transitions. |
| `enter(previous_state: PlayerState)` | `-> void` (virtual)                       | Called when this state becomes active. `previous_state` is `null` on first entry. Use for one-time setup (set velocity, start tween, etc.). |
| `exit(next_state: PlayerState)`      | `-> void` (virtual)                       | Called just before leaving this state. Use for cleanup.        |
| `can_enter()`                        | `-> bool` (virtual, default `true`)       | **Guard**. StateMachine checks this before transitioning. Return `false` to block the transition. |
| `process_frame(delta: float)`        | `-> void` (virtual)                       | Delegated from `_process`. Use for visual updates.             |
| `process_physics(delta: float)`      | `-> void` (virtual)                       | Delegated from `_physics_process`. Use for movement and physics. |
| `process_input(event: InputEvent)`   | `-> void` (virtual)                       | Delegated from `_unhandled_input`. Use for action detection.   |
| `transition_to(target: StringName)`  | `-> void`                                 | Convenience wrapper: calls `state_machine.transition_to(target)`. |

### Key Points

- Mark `_process`, `_physics_process`, and `_unhandled_input` as **disabled** by calling `set_process(false)`, `set_physics_process(false)`, and `set_process_unhandled_input(false)` in `_ready()`. The state machine calls the virtual methods directly — we don't want Godot also calling the engine callbacks on every state node every frame.
- `transition_to()` is a one-liner helper so states can write `transition_to(&"Walk")` instead of `state_machine.transition_to(&"Walk")`.
- Use `&"StateName"` (StringName literals) for transition targets. They match the **node names** in the scene tree.

---

## Step 2 — Create the `PlayerStateMachine`

Create `features/player/states/player_state_machine.gd`.

This node manages the lifecycle. It sits as a direct child of the Player and owns all state nodes as its children.

### Class Definition

| Property / Method                          | Type / Signature                                    | Purpose                                                              |
|--------------------------------------------|-----------------------------------------------------|----------------------------------------------------------------------|
| `class_name`                               | `PlayerStateMachine`                                |                                                                      |
| `extends`                                  | `Node`                                              |                                                                      |
| `@export var initial_state: PlayerState`   | `PlayerState`                                       | Drag the Idle node here in the inspector                              |
| `current_state`                            | `var current_state: PlayerState`                    | The active state. Read-only from outside.                             |
| `_states`                                  | `var _states: Dictionary[StringName, PlayerState]`  | Maps node name → state. Built from children at `_ready()`.           |

### `_ready()` Logic

1. Iterate over all children. For each child that `is PlayerState`:
   - Set `child.player` to `owner` (which is the Player root node, since the StateMachine is saved inside `player.tscn`).
   - Set `child.state_machine` to `self`.
   - Add to `_states` with `child.name` as key.
2. Assert that `initial_state` is not `null`.
3. Set `current_state = initial_state`.
4. Call `current_state.enter(null)` to kick things off.

### Delegation

The state machine overrides the three engine callbacks and forwards them:

| Engine Callback          | Delegates To                               |
|--------------------------|--------------------------------------------|
| `_process(delta)`        | `current_state.process_frame(delta)`       |
| `_physics_process(delta)`| `current_state.process_physics(delta)`     |
| `_unhandled_input(event)`| `current_state.process_input(event)`       |

### `transition_to(target_name: StringName) -> void`

1. **Lookup**: Get `target_state` from `_states[target_name]`. If not found, push a warning and return.
2. **Same-state guard**: If `target_state == current_state`, return silently.
3. **Entry guard**: If `target_state.can_enter()` returns `false`, return silently.
4. **Exit**: Call `current_state.exit(target_state)`.
5. **Swap**: Set `current_state = target_state`.
6. **Enter**: Call `current_state.enter(previous_state)` (keep a local ref to the old state before swapping).

> The state machine should also expose the current state name for debugging: a simple `get_current_state_name() -> StringName` returning `current_state.name`.

---

## Step 3 — Implement `PlayerGroundState`

Create `features/player/states/player_ground_state.gd`.

The player is on the floor — whether standing still or walking. This is the default state.

### Transitions Out

| Condition                                     | Target State |
|-----------------------------------------------|--------------|
| Not on floor (`!player.is_on_floor()`)        | `Air`        |
| Jump pressed + `_should_climb_up()` is `true` | `ClimbUp`    |
| Jump pressed + on floor                       | `Air`        |

> Both "walked off a ledge" and "jumped" lead to `Air`. The difference is that jumping sets an upward velocity impulse before the transition — handled in `process_input`.

### `enter()` Behaviour

- Nothing special on most entries. Velocity carries over from the previous state (e.g. horizontal momentum after landing).

### `process_physics(delta)` Behaviour

1. Apply gravity if not on floor (safety net for edge cases like moving platforms pulling away).
2. Read the input vector (`Input.get_vector("move_left", "move_right", "move_forward", "move_backward")`).
3. **If input is non-zero** — accelerate toward target speed using camera-relative direction:
   - `camera_forward = player.camera.transform.basis.z`
   - `camera_right = player.camera.transform.basis.x`
   - `direction = (camera_forward * input_dir.y + camera_right * input_dir.x).normalized()`
   - `player.velocity.x = move_toward(player.velocity.x, direction.x * player.max_speed, player.acceleration * delta)`
   - Same for `.z`.
   - Rotate the player to face the movement direction (`atan2(direction.x, direction.z) - PI / 2`), applying instantly or with `lerp_angle` depending on `player.rotation_speed`.
4. **If input is zero** — decelerate toward zero:
   - `player.velocity.x = move_toward(player.velocity.x, 0, player.deceleration * delta)`
   - Same for `.z`.
5. Check if the player is still on the floor after `move_and_slide()`. If not → transition to `Air`.
6. Call `player.move_and_slide()`.

### `process_input(event)` Behaviour

1. If `event.is_action_pressed("jump")` and `player.is_on_floor()`:
   - If `player._should_climb_up()` → transition to `ClimbUp`.
   - Else → set `player.velocity.y = player.jump_velocity`, then transition to `Air`.

### Notes

- Movement and idle are handled by the same state — input magnitude decides whether the player moves or decelerates. No state transition noise.
- The jump impulse is applied **before** transitioning to Air, so `PlayerAirState.enter()` doesn't need to know whether we jumped or fell.

---

## Step 4 — Implement `PlayerAirState`

Create `features/player/states/player_air_state.gd`.

The player is airborne — either jumped or walked off a ledge. Gravity applies, optional air control, land when touching the floor.

### Transitions Out

| Condition                | Target State |
|--------------------------|--------------|
| `player.is_on_floor()`  | `Ground`     |

### `enter()` Behaviour

- Nothing special. The jump impulse (if any) was already applied by `PlayerGroundState.process_input()` before the transition. If the player walked off a ledge, `velocity.y` is already `0` or slightly negative — gravity takes over naturally.

### `process_physics(delta)` Behaviour

1. Apply gravity: `player.velocity += player.get_gravity() * delta`.
2. **Air control** (optional, for LIMBO/INSIDE feel):
   - Read the input vector.
   - If input is non-zero, apply camera-relative movement at **reduced** acceleration (e.g. `player.acceleration * 0.5 * delta`). This gives slight directional influence without full air authority.
   - If no input, do **not** decelerate horizontally — let momentum carry.
3. If `player.is_on_floor()` → transition to `Ground`.
4. Call `player.move_and_slide()`.

### Notes

- A single Air state handles both the rising and falling arcs. No need to detect the apex.
- For variable-height jumps (classic INSIDE feel): check `Input.is_action_just_released("jump")` and halve `velocity.y` when positive. This makes short taps = low jumps, long holds = full jumps. Save for polish.
- For coyote time: track how long the player has been airborne. If < ~0.1 s and the player came from Ground (fell, didn't jump), allow a late jump input. Polish feature — skip for prototype.

---

## Step 5 — Implement `PlayerClimbUpState`

Create `features/player/states/player_climb_up_state.gd`.

The player is mantling onto a ledge. This state takes over full control of positioning via a tween — physics is suspended.

### Transitions Out

| Condition            | Target State |
|----------------------|--------------|
| Tween finished       | `Ground`     |

### `can_enter()` Guard

Return `player._should_climb_up()`. This prevents the state machine from entering ClimbUp when there is no valid ledge.

### `enter()` Behaviour

1. Store the mantle target position. The climb detection logic (`_should_climb_up`, `_climb_up_cast_forward_ray`, `_climb_up_find_target_point`) already lives on Player and computes the target. The `_climb_up_target_point` variable on Player holds the ledge position when detection succeeds.
2. Zero out velocity: `player.velocity = Vector3.ZERO`.
3. Create a tween with `player.create_tween()`. Store it in a `_active_tween: Tween` variable.
4. **Phase A — Rise**: Tween `player.global_position:y` to `target.y + 0.05` over `0.2` seconds with `Tween.TRANS_QUAD` and `Tween.EASE_OUT`.
5. **Phase B — Forward**: Chain `.tween_property()` to tween `player.global_position` to the target (with a small forward offset via `player.transform.basis.x * player.climb_up_step_forward_length`) over `0.15` seconds with `Tween.TRANS_QUAD` and `Tween.EASE_IN_OUT`.
6. `await` the tween's `finished` signal.
7. Reset `player._climb_up_target_point = Vector3.ZERO`.
8. Transition to `Ground`.

### `process_physics(_delta)` Behaviour

- **Do nothing**. Do not apply gravity, do not read input, do not call `move_and_slide()`. The tween handles all positioning.

### `exit()` Behaviour

- If `_active_tween` is valid and running, kill it: `_active_tween.kill()`. This is a safety net for interruptions (e.g. a future damage system forcing a state change mid-climb).

### Notes

- The tween approach avoids fighting `move_and_slide()` during the climb.
- The two-phase tween (rise then forward) creates a natural arc that looks good even without animations.

---

## Step 6 — Refactor `player.gd`

The monolithic `_physics_process` body is removed. Movement logic now lives in the individual states. What remains on `player.gd`:

### Keep

| Member                             | Why                                                              |
|------------------------------------|------------------------------------------------------------------|
| `@export var camera: Camera3D`     | States read it via `player.camera`                               |
| `@export var max_speed`            | Movement parameters — single source of truth                     |
| `@export var acceleration`         | Same                                                             |
| `@export var deceleration`         | Same                                                             |
| `@export var jump_velocity`        | Same                                                             |
| `@export var rotation_speed`       | Same                                                             |
| `var climb_up_min_height`          | Used by `_should_climb_up()`                                     |
| `var climb_up_max_height`          | Same                                                             |
| `var climb_up_forward_ray_length`  | Same                                                             |
| `var climb_up_step_forward_length` | Same                                                             |
| `var _climb_up_target_point`       | Set by `_should_climb_up()`, read by `PlayerClimbUpState`        |
| `_should_climb_up()`               | Called by Ground and ClimbUp states                               |
| `_climb_up_cast_forward_ray()`     | Helper for climb detection                                       |
| `_climb_up_find_target_point()`    | Helper for climb detection                                       |
| `_get_validation_conditions()`     | Editor validation                                                |

### Remove

| Member                    | Reason                                                   |
|---------------------------|----------------------------------------------------------|
| `_process()`              | Empty — remove entirely                                  |
| `_physics_process()`      | Logic moved to states                                    |
| `_is_climbing()`          | Replaced by state machine — ClimbUp state handles this   |
| `_jump()`                 | Replaced by jump impulse in `PlayerGroundState`          |
| `_climb_up()`             | Replaced by `PlayerClimbUpState.enter()`                 |
| `_on_climb_up_finished()` | Replaced by ClimbUp → Ground transition                  |

---

## Step 7 — Wire Up the Player Scene

Open `features/player/player.tscn` and make the following changes:

### 7a — Add the StateMachine Node

1. Select the root `Player` node.
2. Add a child node of type `Node`.
3. Rename it to `StateMachine`.
4. Attach `features/player/states/player_state_machine.gd` as its script.

### 7b — Add State Nodes

Add three child nodes **under StateMachine**, all of type `Node`:

| Node Name  | Script                                                     |
|------------|------------------------------------------------------------|
| `Ground`   | `features/player/states/player_ground_state.gd`            |
| `Air`      | `features/player/states/player_air_state.gd`               |
| `ClimbUp`  | `features/player/states/player_climb_up_state.gd`          |

### 7c — Set the Initial State

1. Select the `StateMachine` node.
2. In the Inspector, find the **Initial State** export.
3. Drag the `Ground` node into the slot (or use the node picker).

### 7d — Verify

The scene tree should match the diagram from the Overview. Each state node should show its script icon and have no warnings.

---

## Step 8 — Debug Visualisation

### Current State Label

In `PlayerStateMachine`, add a debug draw call in `_process`:

- Use `DebugDraw3D.draw_text_3d()` to render the current state name above the player's head (e.g. at `player.global_position + Vector3(0, 2.0, 0)`).
- This gives instant visual feedback of which state is active during play.

### Per-State Hints

The climb-up detection rays already use `Debugger.draw_ray_and_collision()`. No changes needed there — they'll fire whenever `_should_climb_up()` is called, regardless of which state calls it.

Optionally, add a colour-coded velocity arrow in Ground and Air states using `DebugDraw3D.draw_arrow()` (same pattern as the commented-out arrow in current `player.gd`).

---

## Step 9 — Test It

### Test Matrix

| Action                           | Expected States                      |
|----------------------------------|--------------------------------------|
| Stand still                      | `Ground`                             |
| Press movement                   | `Ground` (moving)                    |
| Release movement                 | `Ground` (decelerating → idle)       |
| Walk off a ledge                 | `Ground → Air → Ground` (on landing) |
| Press Jump on flat ground        | `Ground → Air → Ground`              |
| Press Jump while walking         | `Ground → Air → Ground`              |
| Press Jump facing a climbable box| `Ground → ClimbUp → Ground`          |
| Walk into climbable box + Jump   | `Ground → ClimbUp → Ground`          |

### Procedure

1. Open `levels/intro_blockout.tscn` (or `dev/dev.tscn`).
2. Make sure at least one box has collision layer **2** enabled for climb testing.
3. Run the scene.
4. Watch the debug text above the player — it should change to match the expected states in the table above.
5. Test the climb height boundaries:
   - A box shorter than `climb_up_min_height` (0.3 m) → Jump (Air), not ClimbUp.
   - A box taller than `climb_up_max_height` (2.0 m) → Jump (Air), not ClimbUp.
   - A box at exactly 1.0 m → ClimbUp.

---

## Transition Diagram

```
        ┌──────────────────────────────────┐
        │                                  │
        │           Ground                 │
        │   (idle + walk, on floor)        │
        │                                  │
        └──┬────────────┬──────────────────┘
           │            │
   !on_floor│            │ jump pressed
   (fell)   │            │ (impulse applied)
           │            │
        ┌──▼────────────▼──────────────────┐
        │                                  │
        │            Air                   │
        │   (gravity, optional air ctrl)   │
        │                                  │
        └──────────────┬───────────────────┘
                       │
                       │ on_floor (landed)
                       │
        ┌──────────────▼───────────────────┐
        │           Ground                 │
        └──────────────────────────────────┘

        ┌──────────────────────────────────┐
        │  ClimbUp (from Ground)           │
        │  tween finished → Ground         │
        └──────────────────────────────────┘
```

---

## Summary of Changes

| File / Asset                                    | What to do                                                                                 |
|-------------------------------------------------|--------------------------------------------------------------------------------------------|
| `features/player/states/player_state.gd`        | **New**. Base `PlayerState` class with virtual interface.                                   |
| `features/player/states/player_state_machine.gd`| **New**. `PlayerStateMachine` manager — child lookup, delegation, `transition_to()`.        |
| `features/player/states/player_ground_state.gd` | **New**. Ground state — movement, deceleration, jump input, transition to Air/ClimbUp.       |
| `features/player/states/player_air_state.gd`    | **New**. Air state — gravity, air control, transition to Ground on landing.                  |
| `features/player/states/player_climb_up_state.gd`| **New**. ClimbUp state — tween to ledge, transition to Ground on completion.                |
| `features/player/player.gd`                     | **Modify**. Remove `_physics_process` body, `_jump()`, `_climb_up()`, `_is_climbing()`. Keep exports and climb detection helpers. |
| `features/player/player.tscn`                   | **Modify**. Add `StateMachine` node with three state children. Set initial state to Ground.  |

Five new scripts, two modified files. No new scenes, no animations, no autoloads.