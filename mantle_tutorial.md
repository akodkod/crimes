# Mantle System Tutorial

A step-by-step guide to implementing a mantle (climb-up / vault) mechanic for your Player in Godot 4.6 with Jolt Physics. No animations — prototype only.

---

## Overview

The mantle allows the Player (150 cm tall, capsule radius 0.32) to climb on top of objects whose height is between **20 cm and 200 cm**. It triggers when the player presses **Jump** while standing on the floor and facing a valid surface on physics **layer 2 ("Mantleable")**.

Detection uses two `RayCast3D` nodes attached to the Player:

| Ray            | Purpose                               | Origin                         | Direction          |
|----------------|---------------------------------------|--------------------------------|--------------------|
| **ForwardRay** | Detects a wall in front of the player | Chest height (~0.75 m)         | Forward (local −Z) |
| **HeightRay**  | Measures the top of that wall         | Above + in front of the player | Straight down (−Y) |

If ForwardRay hits a Mantleable surface **and** HeightRay finds a ledge within the valid height range, the player mantles instead of jumping.

---

## Step 1 — Assign the Mantleable Layer to Objects

The project already defines physics layer 2 as **"Mantleable"** (`project.godot → 3D Physics → Layer Names`).

For every object the player should be able to mantle onto:

1. Select the `CollisionObject3D` (e.g. a `StaticBody3D` or `CSGBox3D`).
2. In the Inspector, open **Collision → Layer**.
3. Enable bit **2** ("Mantleable"). You can keep bit 1 ("Default") enabled as well so the player still collides with it normally.

> The small `CSGBox3D3` in `levels/intro_blockout.tscn` (2 × 2 × 4 at position (1, 1, 0)) is a good first test object. Its top surface sits at Y = 2.0, which is within the mantleable range relative to a player standing at Y = 0.

---

## Step 2 — Add Detection Rays to the Player Scene

Open `features/player/player.tscn` and add two `RayCast3D` children **directly under the root Player node** (siblings of Body and Collision).

### 2a — ForwardRay

This ray checks whether there is a Mantleable wall directly in front of the player.

| Property            | Value          | Why                                                                                                   |
|---------------------|----------------|-------------------------------------------------------------------------------------------------------|
| **Name**            | `ForwardRay`   |                                                                                                       |
| **Position**        | `(0, 0.75, 0)` | Chest height — midpoint of the 1.5 m capsule                                                          |
| **Target Position** | `(0, 0, -0.7)` | Forward in local space (−Z). Length ≈ capsule radius (0.32) + a small reach (~0.38). Adjust to taste. |
| **Enabled**         | `true`         |                                                                                                       |
| **Collision Mask**  | Only bit **2** | So it only detects Mantleable objects                                                                 |

### 2b — HeightRay

This ray casts **downward** from a point above and in front of the player to find the top surface of the object.

| Property            | Value            | Why                                                                                     |
|---------------------|------------------|-----------------------------------------------------------------------------------------|
| **Name**            | `HeightRay`      |                                                                                         |
| **Position**        | `(0, 2.2, -0.7)` | Above max mantle height (2.0 m) and at the same forward offset as ForwardRay's tip      |
| **Target Position** | `(0, -2.5, 0)`   | Straight down, long enough to reach the floor                                           |
| **Enabled**         | `false`          | Only enable it on-demand inside `_should_mantle()` to avoid unnecessary per-frame casts |
| **Collision Mask**  | Only bit **2**   | Same Mantleable filter                                                                  |

> Both rays inherit the Player's rotation, so "forward" always matches the direction the player is facing.

### 2c — Wire Up Script References

Add two `@onready` variables in `player.gd`:

- `forward_ray` → `$ForwardRay`
- `height_ray` → `$HeightRay`

Also add an `@export` or constant for the mantle height range:

- `min_mantle_height: float = 0.2`
- `max_mantle_height: float = 2.0`

---

## Step 3 — Implement `_should_mantle()`

The method already exists as a stub returning `false`. Replace it with the following logic:

1. **Guard**: If `forward_ray` is not colliding, return `false` — there is nothing in front of us.
2. **Force HeightRay update**: Enable `height_ray`, call `force_raycast_update()`, then read its result.
3. **Read collision point**: Get `height_ray.get_collision_point()`. The **Y component** of this point is the top-surface world height.
4. **Calculate relative height**: `ledge_height = collision_point.y - global_position.y`. This is how tall the obstacle is relative to the player's feet.
5. **Range check**: Return `true` only if `ledge_height >= min_mantle_height` **and** `ledge_height <= max_mantle_height`.
6. **Store target**: If valid, save the target position (collision point + a small Y offset so the player lands on top, not inside the geometry) in a class variable like `_mantle_target: Vector3` for use in `_mantle()`.
7. **Cleanup**: Disable `height_ray` after reading, regardless of result.

### Edge-case notes

- If `height_ray` does **not** collide (the ray misses the top), treat it as non-mantleable.
- The forward offset of `HeightRay` (`-0.7` on Z) must be enough to clear the wall's edge. If you find the ray landing behind the wall, increase the offset slightly.
- You may want to add a **floor check above the ledge** (a third short ray or `ShapeCast3D` pointing upward from the ledge point) to reject mantles where there isn't enough headroom. Skip this for the prototype.

---

## Step 4 — Implement `_mantle()`

The simplest prototype approach: **tween the player's position** to the top of the ledge.

1. Read `_mantle_target` (set during `_should_mantle()`).
2. Temporarily disable gravity / physics processing so `move_and_slide()` doesn't fight the tween. The easiest way: set a flag like `_is_mantling: bool = true` and skip the physics block in `_physics_process` while it's active.
3. Create a `Tween` via `create_tween()`.
4. Tween in **two phases** for a natural-feeling arc:
   - **Phase A — Rise**: Tween `global_position:y` to `_mantle_target.y + 0.05` over ~0.2 s (ease out).
   - **Phase B — Forward**: Tween `global_position` to `_mantle_target` (full XYZ) over ~0.15 s (ease in-out). Chain this with `.set_trans(Tween.TRANS_QUAD)`.
5. After the tween finishes (connect to `finished` signal or `await tween.finished`):
   - Reset `velocity` to `Vector3.ZERO` so the player doesn't slide.
   - Set `_is_mantling = false` to re-enable normal physics.

### Why a tween and not velocity?

Velocity-based mantling (`velocity.y = some_value`) interacts unpredictably with `move_and_slide()` when pushing the player into a ledge. A tween gives you precise positional control and is simpler to debug for a prototype.

---

## Step 5 — Guard `_physics_process` During Mantle

Wrap the existing `_physics_process` body in a guard:

```
if _is_mantling:
    return
```

Place this at the very top of `_physics_process`, before gravity, input, or `move_and_slide()`. This prevents the physics loop from overwriting the tween's position changes.

---

## Step 6 — Debug Visualisation

You already use `DebugDraw3D`. Add visual helpers for tuning:

- **ForwardRay hit**: Draw a small sphere at `forward_ray.get_collision_point()` when colliding (e.g. red).
- **HeightRay hit**: Draw a sphere at the ledge point (e.g. green) so you can see exactly where the game thinks the top is.
- **Mantle target**: Draw an arrow from the player to `_mantle_target` when a valid mantle is detected (e.g. yellow).

This makes it trivial to see why a mantle succeeds or fails.

---

## Step 7 — Test It

1. Open `levels/intro_blockout.tscn`.
2. Make sure `CSGBox3D3` (or any test box) has collision layer **2** enabled.
3. Add a few boxes at different heights to test the range boundaries:
   - A **0.15 m** tall box → should **not** mantle (below minimum).
   - A **0.5 m** tall box → should mantle.
   - A **1.5 m** tall box → should mantle.
   - A **2.0 m** tall box → should mantle (upper boundary).
   - A **2.2 m** tall box → should **not** mantle (above maximum).
4. Run the scene and walk toward each box, then press **Space**.
5. Tweak ray lengths, tween durations, and height thresholds until it feels right.

---

## Summary of Changes

| File / Asset                                 | What to do                                                                                                    |
|----------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| `features/player/player.tscn`                | Add `ForwardRay` and `HeightRay` RayCast3D nodes                                                              |
| `features/player/player.gd`                  | Implement `_should_mantle()`, `_mantle()`, add `@onready` refs, mantle height constants, `_is_mantling` guard |
| Any Mantleable `StaticBody3D` / `CSGShape3D` | Enable collision layer 2                                                                                      |
| `levels/intro_blockout.tscn`                 | Add test boxes at various heights with layer 2                                                                |

No new scenes, no new classes, no animations. Just two raycasts, a height check, and a tween.