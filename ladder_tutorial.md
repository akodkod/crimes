# INSIDE/LIMBO-Style Ladders in Godot 4 (2.5D, Node-Based State Machine)

This tutorial implements a cinematic ladder system for this project using a dedicated ladder rail actor and a dedicated ladder state.

It is intentionally built for the existing architecture:

- `Player` + node-based `PlayerStateMachine`
- `PlayerGroundState`, `PlayerAirState`, `PlayerClimbUpState`
- Godot 4.6 + Jolt Physics

The result is deterministic and stable (no ladder jitter from physics), with clean transitions and re-grab protection.

---

## Why this architecture

### Rail-state approach (recommended)

A ladder is represented as a rail segment (`Bottom` to `Top`) and a state (`PlayerLadderState`) that owns movement while climbing.

Benefits:

- Deterministic alignment to the ladder line
- No `move_and_slide()` fighting your climb motion
- Explicit enter/exit rules
- Easy to tune cinematic feel

### Raycast-only approach (not used here)

Raycast-only ladders can work, but usually need constant checks and ad-hoc correction each frame. In a cinematic 2.5D game, this often produces jitter and ambiguous transitions.

For INSIDE/LIMBO-style behavior, explicit rail + state is cleaner.

---

## Step 1: Create the reusable Ladder actor

### Files added

- `features/ladder/ladder.gd`
- `features/ladder/ladder.tscn`

### Ladder scene tree

Use this exact structure:

```text
Ladder (Node3D, script: ladder.gd)
├── RailArea (Area3D)
│   └── Collision (CollisionShape3D, BoxShape3D)
├── Bottom (Marker3D)
└── Top (Marker3D)
```

### What each node does

- `RailArea`: trigger volume for candidate detection
- `Bottom`: world anchor for ladder start
- `Top`: world anchor for ladder end

`ladder.gd` provides the rail API:

- `get_bottom_point()`
- `get_top_point()`
- `get_axis()`
- `point_at_t(t: float)`
- `closest_t(world_pos: Vector3)`

And mount helpers:

- `can_mount_from_bottom(world_pos, max_distance)`
- `can_mount_from_top(world_pos, max_distance)`

### Trigger wiring

`Ladder` connects `RailArea.body_entered/body_exited` and calls into `Player`:

- `player.on_ladder_trigger_entered(self)`
- `player.on_ladder_trigger_exited(self)`

So ladders push candidate changes to the player; the player does not poll the world.

---

## Step 2: Input setup

This implementation reuses existing actions:

- `move_forward` = climb up
- `move_backward` = climb down
- `jump` = detach from ladder

### Project input map changes

In `project.godot`, bind:

- `move_forward`: `W` and `Up Arrow`
- `move_backward`: `S` and `Down Arrow`

### Data aliases

In `scripts/data.gd`:

```gdscript
const INPUT_CLIMB_UP := INPUT_MOVE_FORWARD
const INPUT_CLIMB_DOWN := INPUT_MOVE_BACKWARD
```

### Important 2.5D note

To avoid W/S changing normal locomotion, `PlayerState.get_input_direction()` now uses only left/right axis for movement, reserving forward/backward actions for ladder intent.

---

## Step 3: Player candidate tracking

### File changed

- `features/player/player.gd`

### Added responsibilities

`Player` now tracks ladder candidates and cooldown state:

- `_ladder_candidates: Array[Ladder]`
- `_active_ladder_candidate: Ladder`
- `_ladder_regrab_blocked_until_msec`

Public helpers used by states:

- `on_ladder_trigger_entered(ladder: Ladder)`
- `on_ladder_trigger_exited(ladder: Ladder)`
- `get_active_ladder_candidate() -> Ladder`
- `can_grab_ladder() -> bool`
- `block_ladder_regrab(duration_seconds: float)`
- `wants_to_climb_up() -> bool`
- `wants_to_climb_down() -> bool`

Candidate selection rule is nearest ladder rail by distance to `point_at_t(closest_t(player_pos))`.

---

## Step 4: Add the ladder state

### File added

- `features/player/player_ladder_state.gd`

### Scene integration

`features/player/player.tscn` now includes:

```text
PlayerStateMachine
├── PlayerGroundState
├── PlayerAirState
├── PlayerClimbUpState
└── PlayerLadderState
```

### State machine integration

`features/player/player_state_machine.gd` adds:

- `var ladder: PlayerLadderState`
- registration in `_ready()`
- `try_enter_ladder()`
- `to_ladder()` alias
- `is_ladder()`

---

## Step 5: Enter rules and transition priorities

### Ground -> Ladder

Handled in `PlayerGroundState.process_physics()` before jump logic:

- Must be allowed by cooldown
- Must be pressing climb intent (`up` or `down`)
- `state.try_enter_ladder()` must pass `PlayerLadderState.can_enter()`

`PlayerLadderState.can_enter()` from ground:

- Up input + near ladder bottom => enter at `t = 0`
- Down input + near ladder top => enter at `t = 1`

### Air -> Ladder (optional catch)

`PlayerAirState` tries ladder before climb-up detection.

`PlayerLadderState.can_enter()` from air:

- Must have climb input (up/down)
- Must be inside ladder trigger
- Must have safe fall speed (`velocity.y >= -air_catch_max_fall_speed`)

Then entry `t` is projected from current world position (`closest_t`).

### Ladder vs ClimbUp conflict

Priority is explicit:

1. Try ladder first in air
2. Only then try `ClimbUp`

This avoids ledge and ladder systems fighting during overlap.

---

## Step 6: `PlayerLadderState` behavior

### Enter (`on_enter`)

- Zero velocity
- Snap toward ladder rail (`_snap_player_to_rail`)

### Tick (`process_physics`)

- If ladder becomes invalid, fail-safe to `Ground`/`Air`
- Jump => detach to `Air`
- Convert climb input into `t` movement along rail
- Clamp `t` to `[0, 1]`
- Snap player toward `point_at_t(t)`
- Keep velocity zero (no gravity slide)

### Exit top (`Ladder -> Ground`)

When near top (`t >= 1 - endpoint_deadzone`) and input is upward:

- Place player near top anchor with small forward offset
- Zero velocity
- transition to ground

### Exit bottom (`Ladder -> Ground`)

When near bottom (`t <= endpoint_deadzone`) and input is downward:

- Place player near bottom anchor with slight backward offset
- Zero velocity
- transition to ground

### Jump detach (`Ladder -> Air`)

On jump press:

- Apply small push-away horizontal impulse + upward impulse
- Block ladder re-grab for `regrab_cooldown_seconds`
- transition to air

---

## Step 7: Robustness guards

This implementation includes:

- Re-grab cooldown after jump detach
- Clamped rail parameter `t`
- Fail-safe fallback exit if ladder reference becomes invalid
- Tiny input deadzone (`abs(input) < 0.01`) to ignore accidental noise
- Endpoint deadzone to prevent flicker at top/bottom boundaries

---

## Step 8: Debug and tuning

### Debug visuals

`PlayerLadderState` draws:

- Yellow arrow from ladder bottom to top
- Cyan sphere at current rail point (`point_at_t(t)`)

### Primary tuning variables

In `PlayerLadderState`:

- `climb_speed`
- `snap_speed`
- `bottom_entry_max_distance`
- `top_entry_max_distance`
- `endpoint_deadzone`
- `air_catch_max_fall_speed`
- `detach_push_horizontal_speed`
- `detach_push_vertical_speed`
- `regrab_cooldown_seconds`

In ladder placement (`ladder.tscn` instances):

- `Bottom` and `Top` positions
- `RailArea` collision shape size

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

1. Instance `features/ladder/ladder.tscn` into your test scene.
2. Move `Bottom` to the foot of the ladder and `Top` to the top exit height.
3. Resize `RailArea/Collision` to cover full climb path with a little margin.
4. Run and test using W/S (or Up/Down) + Jump detach.

---

## Final notes

- Scope is prototype gameplay logic only (no ladder animation state graph yet).
- Ladder geometry is straight segment only (bottom-top line).
- Multiplayer/root-motion/network sync are intentionally out of scope.
