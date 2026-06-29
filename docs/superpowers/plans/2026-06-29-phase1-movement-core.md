# Phase 1 — Movement Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite Beam's player into a fluid movement core (accel/friction run, variable-height jump, coyote time, jump buffer, double jump, wall-jump that refunds the air jump, momentum slide with a speed-scrubbed animation) and remove the test-only draw mechanic and the old combat.

**Architecture:** Strip the player-drawn-platform mechanic and the beat-'em-up combat first to reach a clean movement-only baseline, then layer the fluidity features onto `player.gd` in small, independently playtestable increments. No new scenes; existing nodes that combat used are left in place (untouched) for Phase 2 to repurpose.

**Tech Stack:** Godot 4.7, GDScript, `CharacterBody2D`.

## Global Constraints

- Engine: **Godot 4.7** (`config/features=PackedStringArray("4.7", "Forward Plus")`).
- `godot` is **not on PATH**; verification is done by running the project from the Godot editor (**F5**) and watching the **Output/Debugger** panels for errors. Each task's "verify" step is a manual playtest checklist.
- The boot scene is still `res://scenes/title_screen.tscn` → `Main.tscn` → `LevelRoot` (Level 1) for this phase. Level retirement happens in Phase 3.
- Keep existing public interfaces other scripts depend on: the player's `hurt()` method, `alive` property, `health` property, `apply_knockback(from_direction)`, and the `player_died` signal (used by `main.gd`).
- Do **not** edit `player.tscn` node structure in this phase. Unused `KickSound` / `PunchSound` / `AttackHitbox` nodes are harmless and are reworked in Phase 2.
- Commit after every task with a `feat:`/`refactor:`/`chore:` message ending with the project's `Co-Authored-By` trailer.

---

### Task 1: Remove the player-drawn platform (draw) mechanic

This was test-only scaffolding. Removing it also clears the polyline-thickening code, which migrates to the `InkStroke` primitive in Phase 3.

**Files:**
- Modify: `scripts/main.gd` (remove all draw logic)
- Modify: `scenes/Main.tscn` (remove the `DrawTrail` node + its reference)
- Modify: `project.godot` (remove the `draw` input action)
- Delete: `scripts/pen_trail.gd`, `scripts/pen_trail.gd.uid`

**Interfaces:**
- Consumes: nothing.
- Produces: a `main.gd` that only does level setup, scoring, health display, and pause (`_setup_level`, `_on_player_hit`, `_on_player_died`, `_update_health_display`, `increase_score`, `_toggle_pause`, `_on_resume_pressed`, `_on_quit_pressed`).

- [ ] **Step 1: Replace `scripts/main.gd` with the draw-free version**

```gdscript
extends Node2D
@onready var score_label = $HUD/ScorePanel/ScoreLabel
@onready var health_label = $HUD/HealthPanel/HealthLabel
@onready var player = $LevelRoot/Player
@onready var pause_overlay = $HUD/PauseOverlay

var score = 0
var is_paused = false


func _ready():
	_setup_level()
	_update_health_display()
	pause_overlay.hide()


func _process(_delta):
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()


func _setup_level():
	for collectable in get_tree().get_nodes_in_group("collectables"):
		if collectable.has_signal("collected") and not collectable.collected.is_connected(increase_score):
			collectable.collected.connect(increase_score)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_signal("player_hit") and not enemy.player_hit.is_connected(_on_player_hit):
			enemy.player_hit.connect(_on_player_hit)

	if player and player.has_signal("player_died"):
		if not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died)


func _on_player_hit(body):
	if body.has_method("hurt") and body.alive:
		body.hurt()
		_update_health_display()


func _on_player_died():
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()


func _update_health_display():
	if player and player.has_method("hurt"):
		health_label.text = "HP: %d" % player.health


func increase_score():
	score += 1
	score_label.text = "SCORE: %s" % score


func _toggle_pause():
	is_paused = not is_paused
	get_tree().paused = is_paused
	pause_overlay.visible = is_paused


func _on_resume_pressed():
	_toggle_pause()


func _on_quit_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
```

- [ ] **Step 2: Remove the `DrawTrail` node from `scenes/Main.tscn`**

Delete this line from `scenes/Main.tscn`:

```
[node name="DrawTrail" type="Line2D" parent="."]
```

(The node has no children and nothing references it after Step 1.)

- [ ] **Step 3: Remove the `draw` input action from `project.godot`**

In `project.godot`, under `[input]`, delete the entire `draw={ ... }` block (the action mapped to the `Q` key). Leave `left`, `right`, `jump`, `crouch`, `punch`, `kick`, `shoot`, and `pause` intact.

- [ ] **Step 4: Delete the pen-trail script**

```bash
git rm scripts/pen_trail.gd scripts/pen_trail.gd.uid
```

- [ ] **Step 5: Verify in the editor**

Open the project in Godot and press **F5**. Expected:
- No parse/script errors in the Output/Debugger.
- Game boots to the title, starts a level, and plays normally.
- Pressing **Q** does nothing (no trail, no platform).
- SCORE and HP HUD still update (collect an item / take a hit).

- [ ] **Step 6: Commit**

```bash
git add scripts/main.gd scenes/Main.tscn project.godot
git commit -m "$(printf 'refactor: remove test-only player-drawn platform mechanic\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 2: Movement-only `player.gd` baseline (remove combat)

Port `player.gd` to a clean movement-only script: keep run / jump / wall slide / wall jump / slide / hurt / animations; remove all attacks (kick, flying-kick, crouch-kick, falling-attack, fireball, attack hitbox). The combat-blocking flag `is_attacking` is renamed `is_busy` to reflect its sole remaining purpose: freezing input during the hurt animation.

**Files:**
- Modify: `scripts/player.gd` (full replacement)

**Interfaces:**
- Consumes: scene nodes `$AnimatedSprite2D`, `$JumpSound`.
- Produces (relied on by `main.gd` and Phase 2): `hurt()`, `apply_knockback(from_direction: float)`, properties `alive: bool`, `health: int`, `invincible: bool`, signal `player_died`. New movement state used by later tasks: `is_sliding: bool`, `slide_dir: float`, `facing_right: bool`.

- [ ] **Step 1: Replace `scripts/player.gd` with the movement-only version**

```gdscript
extends CharacterBody2D

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var jump_sound = $JumpSound

const SPEED = 300.0
const JUMP_VELOCITY = -700.0
const WALL_JUMP_HORIZONTAL = 400.0
const WALL_JUMP_VERTICAL = -550.0
const WALL_SLIDE_GRAVITY = 300.0
const GRAVITY = 980.0

const SLIDE_ACCEL = 850.0
const SLIDE_FRICTION = 0.98
const SLIDE_FLAT_FRICTION = 0.995
const SLIDE_MIN_SPEED = 30.0
const SLIDE_STOP_SPEED = 20.0

const HURT_ANIMS = ["hurt"]
const KNOCKBACK_FORCE = 400.0
const INVINCIBLE_MS = 1000.0
const MAX_WALL_JUMPS = 1

var alive = true
var health = 3
var invincible = false
var is_busy = false        # blocks movement input during the hurt animation
var is_sliding = false
var slide_dir = 1.0
var slide_timer = 0.0
var facing_right = true
var floor_angle = 0.0
var wall_jumps_used = 0
var air_time = 0.0

signal player_died


func _ready():
	add_to_group("player")
	var frames = animated_sprite_2d.sprite_frames
	for anim in HURT_ANIMS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	floor_max_angle = deg_to_rad(60)
	floor_snap_length = 6.0


func _on_animation_finished():
	if animated_sprite_2d.animation in HURT_ANIMS:
		invincible = false
		is_busy = false


func hurt():
	if not alive or invincible:
		return
	health -= 1
	if health <= 0:
		alive = false
		is_busy = true
		player_died.emit()
		animated_sprite_2d.play("hurt")
		set_physics_process(false)
		await animated_sprite_2d.animation_finished
		queue_free()
	else:
		invincible = true
		is_busy = true
		animated_sprite_2d.play("hurt")
		await get_tree().create_timer(INVINCIBLE_MS / 1000.0).timeout
		invincible = false
		is_busy = false


func apply_knockback(from_direction):
	velocity.x = from_direction * KNOCKBACK_FORCE
	velocity.y = -200.0


func _physics_process(delta):
	if not alive:
		return

	if not is_on_floor():
		air_time += delta
	elif air_time >= 0.1:
		air_time = 0.0
		wall_jumps_used = 0
	elif air_time > 0:
		air_time = 0.0

	if not is_finite(velocity.x):
		velocity.x = 0.0
	if not is_finite(velocity.y):
		velocity.y = 0.0

	var direction = Input.get_axis("left", "right")
	var crouching = Input.is_action_pressed("crouch") and is_on_floor()

	# Gravity / wall slide
	if not is_on_floor():
		if is_on_wall() and velocity.y > 0:
			var wall_normal = get_wall_normal()
			var pushing = direction != 0 and sign(direction) == -sign(wall_normal.x)
			if pushing:
				velocity.y += (WALL_SLIDE_GRAVITY / GRAVITY) * delta
			else:
				velocity.y += GRAVITY * delta
		else:
			velocity.y += GRAVITY * delta

	# Wall jump
	if Input.is_action_just_pressed("jump") and is_on_wall() and not is_on_floor() and not is_busy and wall_jumps_used < MAX_WALL_JUMPS:
		wall_jumps_used += 1
		var wall_normal = get_wall_normal()
		velocity.x = wall_normal.x * WALL_JUMP_HORIZONTAL
		velocity.y = WALL_JUMP_VERTICAL
		jump_sound.play()

	# Ground jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_busy:
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	# Start slide
	if Input.is_action_just_pressed("crouch") and is_on_floor() and not is_busy and not is_sliding and abs(velocity.x) >= SLIDE_MIN_SPEED:
		is_sliding = true
		slide_dir = sign(velocity.x)
		slide_timer = 0.0

	if is_sliding:
		if Input.is_action_just_pressed("jump"):
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			velocity.y = JUMP_VELOCITY
			jump_sound.play()
		elif not is_on_floor() or not Input.is_action_pressed("crouch"):
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
		elif direction == 0:
			is_sliding = false
			slide_timer = 0.0
			floor_angle = 0.0
			velocity.x = 0
		else:
			slide_timer += delta
			slide_dir = sign(direction)
			var normal = get_floor_normal()
			var slope = abs(normal.x)
			var surface_right = Vector2(-normal.y, normal.x)
			floor_angle = surface_right.angle()
			var current_speed = velocity.x * surface_right.x + velocity.y * surface_right.y
			if slope > 0.01:
				current_speed += SLIDE_ACCEL * slope * delta * slide_dir
				current_speed *= SLIDE_FRICTION
			else:
				current_speed *= SLIDE_FLAT_FRICTION
			if abs(current_speed) < SLIDE_STOP_SPEED:
				current_speed = SLIDE_STOP_SPEED * slide_dir
			velocity = surface_right * current_speed

	# Horizontal movement (when not sliding)
	if not is_sliding:
		if crouching or is_busy:
			velocity.x = move_toward(velocity.x, 0, SPEED)
		elif direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Animation
	if not is_busy:
		if not is_on_floor():
			if is_on_wall() and velocity.y > 0:
				animated_sprite_2d.play("fall")
			elif velocity.y < 0:
				animated_sprite_2d.play("jump")
			else:
				animated_sprite_2d.play("fall")
		elif is_sliding:
			animated_sprite_2d.play("crouch")
		elif crouching:
			animated_sprite_2d.play("crouch")
		elif abs(velocity.x) > 1:
			animated_sprite_2d.play("walk")
		else:
			animated_sprite_2d.play("idle")

	move_and_slide()

	if not is_sliding and floor_angle != 0:
		floor_angle = 0.0
	animated_sprite_2d.rotation = floor_angle

	if direction == 1.0:
		animated_sprite_2d.flip_h = false
		facing_right = true
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true
		facing_right = false
	if is_sliding:
		animated_sprite_2d.flip_h = (slide_dir < 0)
```

- [ ] **Step 2: Verify in the editor**

Press **F5**. Expected — no script errors, and:
- Move left/right (`A`/`D`), jump (`W`/`Space`), wall-slide against a wall while falling and holding into it, wall-jump off it (once per airborne stretch).
- Run and press `S` to slide; release `S` or direction to stop.
- Pressing `J`/`K`/`Z`/`X`/mouse does **nothing** (combat removed).
- Touch a snail → player still takes damage and HP drops (the `hurt()` path is intact).

- [ ] **Step 3: Commit**

```bash
git add scripts/player.gd
git commit -m "$(printf 'refactor: strip combat to a movement-only player baseline\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 3: Fluid run + jump (accel/friction, coyote time, jump buffer, variable height)

Replace instant horizontal velocity with acceleration/friction, and add the three game-feel staples to jumping.

**Files:**
- Modify: `scripts/player.gd`

**Interfaces:**
- Consumes: the Task 2 baseline.
- Produces: state vars `coyote_timer: float`, `jump_buffer_timer: float` used by Task 4.

- [ ] **Step 1: Add the new constants and state**

After the `const GRAVITY = 980.0` line, add:

```gdscript
const RUN_ACCEL = 2200.0
const RUN_FRICTION = 2600.0
const AIR_ACCEL = 1600.0
const AIR_FRICTION = 800.0
const FALL_GRAVITY_MULT = 1.25
const JUMP_CUT_MULT = 0.45
const COYOTE_TIME = 0.1
const JUMP_BUFFER_TIME = 0.1
```

After `var air_time = 0.0`, add:

```gdscript
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
```

- [ ] **Step 2: Track coyote + buffer timers and a stronger fall**

In `_physics_process`, replace the gravity `else` branches so falling is snappier. Change both `velocity.y += GRAVITY * delta` lines inside the gravity block to:

```gdscript
			velocity.y += GRAVITY * (FALL_GRAVITY_MULT if velocity.y > 0 else 1.0) * delta
```

Then, immediately **after** the gravity/wall-slide block and **before** the wall-jump block, add the timer bookkeeping:

```gdscript
	# Coyote + jump buffer timers
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = max(0.0, coyote_timer - delta)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer = max(0.0, jump_buffer_timer - delta)
```

- [ ] **Step 3: Convert ground jump to coyote+buffer and add variable height**

Replace the existing **Ground jump** block:

```gdscript
	# Ground jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_busy:
		velocity.y = JUMP_VELOCITY
		jump_sound.play()
```

with:

```gdscript
	# Ground jump (coyote + buffered) and variable height
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and not is_sliding and not is_busy:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		jump_sound.play()

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT_MULT
```

- [ ] **Step 4: Replace instant run with accel/friction**

Replace the **Horizontal movement (when not sliding)** block:

```gdscript
	# Horizontal movement (when not sliding)
	if not is_sliding:
		if crouching or is_busy:
			velocity.x = move_toward(velocity.x, 0, SPEED)
		elif direction:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
```

with:

```gdscript
	# Horizontal movement (when not sliding) — accel/friction for momentum
	if not is_sliding:
		var accel = RUN_ACCEL if is_on_floor() else AIR_ACCEL
		var friction = RUN_FRICTION if is_on_floor() else AIR_FRICTION
		if (crouching or is_busy) or direction == 0:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		else:
			velocity.x = move_toward(velocity.x, direction * SPEED, accel * delta)
```

- [ ] **Step 5: Verify in the editor**

Press **F5**. Expected:
- Run has a slight ramp-up/slow-down (momentum), not instant snap.
- Tapping jump = a short hop; holding = full height (variable height).
- Walking off a ledge and pressing jump within a hair still jumps (coyote).
- Pressing jump just before landing still jumps on touchdown (buffer).
- Falls feel a touch snappier than the rise.

- [ ] **Step 6: Commit**

```bash
git add scripts/player.gd
git commit -m "$(printf 'feat: fluid run+jump (accel/friction, coyote time, jump buffer, variable height)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 4: Double jump + wall-jump/​wall-contact air-jump refund

Add one mid-air jump, refundable by touching or jumping off a wall, for fluid wall-to-wall chains.

**Files:**
- Modify: `scripts/player.gd`

**Interfaces:**
- Consumes: `coyote_timer`, `jump_buffer_timer` from Task 3.
- Produces: state var `air_jumps_left: int` (Phase 2's stomp bounce will refund it).

- [ ] **Step 1: Add the constant and state**

After `const JUMP_BUFFER_TIME = 0.1`, add:

```gdscript
const MAX_AIR_JUMPS = 1
```

After `var jump_buffer_timer = 0.0`, add:

```gdscript
var air_jumps_left = MAX_AIR_JUMPS
```

- [ ] **Step 2: Refill air jumps on the ground**

In the coyote-timer block from Task 3, set the air-jump count when grounded:

```gdscript
	# Coyote + jump buffer timers
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		air_jumps_left = MAX_AIR_JUMPS
	else:
		coyote_timer = max(0.0, coyote_timer - delta)
```

- [ ] **Step 3: Refund the air jump on wall contact, and on wall jump**

Two surgical additions to the wall-jump area (which, from the Task 3 fix, already consumes `jump_buffer_timer` and `coyote_timer`).

**(a)** Immediately **before** the `# Wall jump` comment line, add a wall-contact refresh block:

```gdscript
	# Touching a wall (airborne) refreshes the air jump → fluid wall chains
	if is_on_wall() and not is_on_floor():
		air_jumps_left = MAX_AIR_JUMPS

```

**(b)** Inside the existing **Wall jump** `if` block, add one line — `air_jumps_left = MAX_AIR_JUMPS` — immediately **after** `velocity.y = WALL_JUMP_VERTICAL`. The resulting block must read exactly:

```gdscript
	# Wall jump
	if Input.is_action_just_pressed("jump") and is_on_wall() and not is_on_floor() and not is_busy and wall_jumps_used < MAX_WALL_JUMPS:
		wall_jumps_used += 1
		var wall_normal = get_wall_normal()
		velocity.x = wall_normal.x * WALL_JUMP_HORIZONTAL
		velocity.y = WALL_JUMP_VERTICAL
		air_jumps_left = MAX_AIR_JUMPS
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		jump_sound.play()
```

- [ ] **Step 4: Add the mid-air (double) jump**

Immediately **after** the ground-jump block from Task 3 (the `if jump_buffer_timer > 0.0 and coyote_timer > 0.0 ...` block), and **before** the `Input.is_action_just_released("jump")` variable-height line, add:

```gdscript
	# Double jump — used when no coyote/ground jump is available
	elif jump_buffer_timer > 0.0 and not is_on_floor() and not is_on_wall() and air_jumps_left > 0 and not is_busy:
		velocity.y = JUMP_VELOCITY
		air_jumps_left -= 1
		jump_buffer_timer = 0.0
		jump_sound.play()
```

Note: this `elif` chains onto the ground-jump `if` so a single buffered press can't trigger both.

- [ ] **Step 5: Verify in the editor**

Press **F5**. Expected:
- Jump, then jump again once in mid-air (double jump). A third press does nothing until you land or touch a wall.
- Jump into a wall, wall-jump off, and you again have a mid-air jump available — you can chain wall → wall-jump → air-jump.
- Landing refills everything.

- [ ] **Step 6: Commit**

```bash
git add scripts/player.gd
git commit -m "$(printf 'feat: double jump with wall-contact/wall-jump air-jump refund\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 5: Speed-scrubbed slide animation

The slide no longer auto-kicks. Instead it drives the `crouch-kick` animation by slide speed: held at the crouched first frame when slow, advancing through the kick frames as it accelerates.

**Files:**
- Modify: `scripts/player.gd`

**Interfaces:**
- Consumes: `is_sliding`, `slide_dir`, the slide velocity computed in `_physics_process`.
- Produces: helper `slide_frame(speed: float, frame_count: int) -> int` (pure; reused/validated by later phases if a headless harness is added).

- [ ] **Step 1: Add the slide-animation constants**

After `const SLIDE_STOP_SPEED = 20.0`, add:

```gdscript
const SLIDE_ANIM_MIN = 200.0   # below this, hold the crouched first frame
const SLIDE_ANIM_MAX = 700.0   # at/above this, fully-extended kick frame
const SLIDE_ANIM = "crouch-kick"
```

- [ ] **Step 2: Add the pure mapping helper**

Add this function near the bottom of the script (e.g., after `apply_knockback`):

```gdscript
# Map a slide speed to a frame index of the crouch-kick animation.
# Slow slide → frame 0 (crouched); fast slide → last frame (extended kick).
func slide_frame(speed: float, frame_count: int) -> int:
	if frame_count <= 1:
		return 0
	var t = clampf((absf(speed) - SLIDE_ANIM_MIN) / (SLIDE_ANIM_MAX - SLIDE_ANIM_MIN), 0.0, 1.0)
	return int(round(t * (frame_count - 1)))
```

- [ ] **Step 3: Drive the crouch-kick frame while sliding (in the animation block)**

In the **Animation** block, replace this branch:

```gdscript
		elif is_sliding:
			animated_sprite_2d.play("crouch")
```

with:

```gdscript
		elif is_sliding:
			var frames = animated_sprite_2d.sprite_frames
			if frames.has_animation(SLIDE_ANIM):
				animated_sprite_2d.animation = SLIDE_ANIM
				animated_sprite_2d.pause()
				var fc = frames.get_frame_count(SLIDE_ANIM)
				animated_sprite_2d.frame = slide_frame(velocity.length(), fc)
			else:
				animated_sprite_2d.play("crouch")
```

- [ ] **Step 4: Verify in the editor**

Press **F5**. Expected:
- Start a slide on flat ground: the sprite holds the crouched (first) `crouch-kick` frame.
- Slide down a slope so it accelerates: the kick visibly **extends** through the animation frames as speed rises, and retracts as it slows.
- Jump still cancels the slide; releasing `S`/direction still stops it; no automatic kick fires.

- [ ] **Step 5: Commit**

```bash
git add scripts/player.gd
git commit -m "$(printf 'feat: speed-scrubbed crouch-kick slide animation\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Self-Review

**Spec coverage (Phase 1 scope of the design doc §4, §10):**
- Accel/friction run — Task 3 ✓
- Variable jump height — Task 3 ✓
- Coyote time + jump buffer — Task 3 ✓
- Double jump (one air jump) — Task 4 ✓
- Wall slide + wall jump refined; wall contact/jump refunds air jump — Tasks 2 & 4 ✓
- Slide kept with slope accel; speed-scrubbed crouch-kick animation; no auto-kick — Tasks 2 & 5 ✓
- Removed combat (kick/flying-kick/falling-attack/auto-kick/fireball) — Task 2 ✓
- Removed draw mechanic (pen_trail.gd, DrawTrail node, draw action, main.gd draw logic) — Task 1 ✓

**Deferred to later phases (intentionally not in this plan):** stomp / slide-kill / charge / fireball gating + enemy `died` signal (Phase 2); InkStroke + Level 2 + collect-all + beam transport (Phase 3); theme/UI/HUD charge ensō (Phase 4); settings (Phase 5); afterglow trail (Phase 6, may be pulled forward).

**Placeholder scan:** none — every code step contains complete GDScript.

**Type/name consistency:** `is_busy`, `coyote_timer`, `jump_buffer_timer`, `air_jumps_left`, `MAX_AIR_JUMPS`, `slide_frame()`, `SLIDE_ANIM*` are introduced once and used consistently across tasks. `hurt()`, `alive`, `health`, `apply_knockback()`, `player_died` are preserved for `main.gd`.

**Note on testing:** Phase 1 verification is manual (in-editor playtest) because `godot` is not on PATH and movement is a game-feel concern. The one pure function (`slide_frame`) is isolated so a headless GdUnit-style harness introduced in a later phase can unit-test it without touching physics.
