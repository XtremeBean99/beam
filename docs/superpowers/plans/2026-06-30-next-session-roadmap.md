# Beam — Next-Session Roadmap

> Forward plan for expanding the game per the design spec
> (`docs/superpowers/specs/2026-06-29-beam-movement-ink-ui-design.md`). Pick up
> from the top of "Priorities" below.

## Update — 2026-06-30 (input-corruption + float fixes)

- **Dead controls after a rebind (critical)** — `settings.gd` saved/loaded key
  bindings by `keycode`, but the project's default bindings use `physical_keycode`
  (keycode 0). One rebind wrote zeros for every action; on launch `load_keybindings`
  erased the real bindings and bound them to nothing. Fixed to use `physical_keycode`
  and skip invalid (0) codes (self-heals old saves); cleared the corrupt
  `user://settings.cfg [keys]` section. If controls ever die again, suspect that file.
- **Player floated above ground** — terrain collision `thickness` 40 seats the player
  ~20px above the drawn line (symmetric band). Level 1/3 set to 16 to match Level 2.

## Update — 2026-06-30 (tutorial + boss/feedback pass)

- **Tutorial (new Level 1, "FIRST BREATH")** — `scenes/levels/level1.tscn` +
  `assets/levels/level1_strokes.json`, reusing `level2.gd`. Teaches move → jump →
  double-jump → slide → stomp → collect-all via floating ink hint-text Labels.
  Platform heights tuned to the real jump arc. Campaign is now level1 → level2 →
  level3 (`Main.tscn` boots level1; `main.gd` LEVELS has all three).
- **Flyer now chases** the player within `CHASE_RANGE` (exported `chases`).
- **Wizard boss** (uses the unused wizard sprites) — `scripts/boss.gd` +
  `scenes/boss.tscn`: hovers, tracks the player at range, casts `enemy_fireball`
  projectiles, has a depleting health bar, dies with a grow-and-fade. Replaces the
  tanky-snail placeholder in level3. Killable by stomp/slide/player-fireball.
- **Player hit-feedback** — `player.gd` `hurt()` now white-flashes the sprite,
  shakes the camera, plays a hit sound (`PistolSound`), and emits `health_changed`
  (main wires it to the HUD so projectile damage updates the pips). Collectable
  pickup plays a pitched `punch.mp3` blip.
- **Slides faster/snappier** + **auto-slide on landing while holding crouch**.
- **Still TODO (Pass 2):** real ink-wipe transition, display font (no font asset in
  repo yet), broad placement/difficulty balance. Hint-text size/placement and boss
  feel need an F5 look.

## Update — 2026-06-30 (freeze fix + HUD pass)

- **Level-complete freeze fixed** — `_on_beam_done`/`_on_level_continue` awaited
  `transition.faded_out`, which never fired (the Transition CanvasLayer was
  force-hidden in `_ready`), so the beam sequence hung and Continue never advanced.
  Now timer-driven (`await get_tree().create_timer().timeout`) and the layer is no
  longer hidden, so fades actually render.
- **Beam "frozen camera" fixed** — the dissolve tween scaled the whole player to
  0.01, shrinking its child `Camera2D` and zooming into the void. Now only the
  sprite scales/fades (`level2.gd`).
- **HUD cleanup** — removed the redundant `CHARGE` text row (the ensō is the charge
  display); moved the **charge ensō to the top-right** with a `FIRE` label (was
  overlapping the stats panel); moved the test button to bottom-right; put the
  level-complete screen on its own `OverlayLayer` (CanvasLayer 50) so the beam
  (world z-index 100) no longer draws over it. Fireball damage = 3 (one-shots),
  stomp plays `KickSound`, END LEVEL test button, score/kills reset on death.

## Update — 2026-06-30 (expansion pass)

**Bug fixes (startup/play-path errors):**
- `collectable.gd` — `call_deferred("_disable_collision()")` had literal parens
  (runtime error on every pickup); also now ignores non-player bodies so terrain
  on the shared collision layer 1 can't auto-trigger collection on level load.
- `fireball.tscn` — `collision_mask` was `1` (terrain/player) so fireballs never
  hit enemies (layer 2). Now `2`; fireballs damage snails/flyers/boss.
- `settings_menu.gd` — key-rebind buttons looked up the wrong node path
  (`<action>Button` vs `<action>Row/<action>Button`); rebinding was silently dead.
- `main.gd` `_update_charge` — dereferenced `player.KILLS_PER_CHARGE` outside the
  `is_instance_valid(player)` guard (null-crash risk).

**Expansion beyond spec:**
- **Multi-level campaign flow** — `main.gd` now has a `LEVELS` list + `_level_index`;
  clearing a level advances via `load_level()` (Continue), death respawns the
  *current* level, final clear returns to title. Fixed a latent double-show of the
  level-complete screen (the persistent `faded_out` handler became explicit `await`s).
- **Air-fireball** — `player.gd` `FIREBALL_GROUND_ONLY = false`.
- **New enemy: Flyer** (`scripts/flyer.gd`, `scenes/flyer.tscn`) — hovering/bobbing
  patroller using the **angel** sprites; stomp/slide/fireball kill it, contact hurts.
- **Boss** — `snail.gd` `max_health` is now `@export` (and `_foot` scales with node
  scale); Level 3 uses a big high-HP snail as a boss. Reuses all snail combat.
- **Level 3** (`scenes/levels/level3.tscn` + `assets/levels/level3_strokes.json`) —
  hand-authored InkStroke terrain (ramp, plateau, slide slope, boss arena, two float
  platforms), reuses the generic `level2.gd`. 3 snails + 2 flyers + boss + 5 collectables.

**Not yet done / next:** real multi-phase boss (current boss is a tanky snail),
checkpoints, more levels, and a verified F5 playtest (no Godot in the agent env).

## Where we are (shipped earlier)

- **Movement core** (spec §4) — accel/friction run, variable-height jump, coyote
  time, jump buffer, double jump with wall-refund, momentum slide. Slide tuned to
  a **slope-target** model: flat = walk speed, any incline faster
  (`target = SPEED·(SLIDE_BASE + slope·SLIDE_GAIN)`, capped). `floor_max_angle = 72°`
  so steep lines are slideable.
- **InkStroke world** (spec §3, §7) — `InkStroke` (glowing Line2D + thickened
  collision) and `InkTerrain` (builds a level from a strokes JSON). **Level 2**
  (`level2.tscn`) is the boot level, traced from `map2.png` (19 stitched strokes),
  with fall-respawn. Level 1 retired in-repo.
- **Enemies** (spec §6) — snail reworked to a `CharacterBody2D`: gravity, surface
  patrol that turns at line ends/sharp bends, monochrome hit-flash, emits `died`.
- **Combat (partial)** (spec §5) — **stomp** done (land on head → damage + bounce
  + air-jump refund). Player passes through enemies (collision exception).
- **UI** (spec §8) — shared **Ink & Circuit** theme; start menu (Play/Settings/Quit);
  **settings/volume** (Master/Music/SFX buses + `Settings` autoload persisting to
  `user://settings.cfg`); themed pause; HUD with **3 health pips + KILLS + SCORE**.
- **Tooling** — `tools/image_to_strokes.py` (image → strokes JSON pipeline) with
  endpoint stitching. `bgm.mp3` gitignored.

The user has placed 6 snails + 6 collectables in `level2.tscn` and confirmed
movement/slide feel is good.

## Open items vs. the spec

| Spec area | Status |
| --- | --- |
| §4 Movement | ✅ done (tuned) |
| §5 Stomp | ✅ done |
| §5 Slide-kill | ✅ done |
| §5 Charge meter + fireball | ✅ done |
| §7 Collect-all → beam exit / level flow | ✅ done |
| §8 HUD charge ensō | ✅ done |
| §8 Level-complete screen | ✅ done |
| §8 Ink-wipe transitions | ✅ done |
| §5 Settings — key rebinding | ✅ done |
| §9 Afterglow trail | ✅ done |
| Pen-draw editor / SVG import (user request) | ❌ future |

---

## Priorities for next session (in order)

### P1 — Collect-all → beam-of-light exit + level-complete (spec §7, §8)
The headline missing feature; makes the level a complete loop.

- **Win condition:** track collectables collected vs. total in `main.gd`
  (`get_tree().get_nodes_in_group("collectables").size()` at `_ready`; decrement /
  count on each `collected`). When the last is taken, fire level-complete.
- **Beam transport:** a vertical light beam descends onto the player; the player
  rises/dissolves into it (tween scale/alpha + a glowing `Line2D`/gradient column).
  Lock player input during the sequence (set a flag the player reads, or
  `set_physics_process(false)`).
- **Level-complete screen:** new `scenes/ui/level_complete.tscn` using `ui_theme` —
  the incomplete ensō **closes** as the reward motif; show **time / score / kills**;
  Continue button → reload level (only one level exists) or next level when added.
- **Scene flow:** introduce a tiny level-loading helper so the "LevelRoot" slot in
  `Main.tscn` can swap level scenes (groundwork for level 3+). Keep each level its
  own `.tscn`.
- **Ink-wipe transition** under the beam (reusable `scenes/ui/transition.tscn` +
  a fade/​wipe shader or animated ColorRect).

### P2 — Finish combat-through-movement (spec §5)
- **Slide-kill:** in `snail.gd._on_contact`, treat a side hit from a fast slide as a
  kill instead of hurting the player. Detect via `body.is_sliding and
  absf(body.velocity.x) >= SLIDE_KILL_SPEED` (expose `is_sliding` — already a var).
  Otherwise hurt as now.
- **Charge meter:** `main.gd` counts kills (already does) and grants **1 fireball
  charge per 3 kills** (cap ~3). Store on the player or in `main.gd`; expose to HUD.
- **Fireball:** re-add the charged special to `player.gd` — `shoot` action, spends a
  charge, plays the **punch** animation, spawns `fireball.tscn` (still in repo).
  Ground-only initially (`FIREBALL_GROUND_ONLY`). Wire `punch` SFX to the SFX bus.

### P3 — HUD charge ensō + polish (spec §8)
- Add a **charge ensō** to the HUD that fills with kills and glows when a fireball is
  ready (ties to P2).
- Optional: an **ensō logo** on the title, slider grabber styling, a real display
  font for headings.

### P4 — Settings: key rebinding (spec §5)
- Extend the settings menu with a **rebinding** section (capture `InputEventKey`,
  update the `InputMap`, persist to `user://settings.cfg` alongside volumes).

### P5 — Player afterglow trail (spec §9)
- `scripts/player_trail.gd`: spawn fading white afterimages of the sprite during
  fast states (slide / wall-jump / double jump / high speed); additive blend, ~0.25s
  fade. Low-risk, high visual payoff.

### P6 — Level-authoring tooling (user request)
- **SVG import:** parse true vector `<path>` data directly into strokes (crisper than
  raster tracing) — extend `tools/image_to_strokes.py` or a sibling tool.
- **In-editor pen tool:** a `@tool` EditorPlugin / scene to draw InkStrokes with the
  mouse and bake them to a level strokes JSON (repurpose the old polyline-capture).

---

## Loose ends / known issues

- **Push is blocked:** `bgm.mp3` (220 MB) is in git history and exceeds GitHub's
  100 MB limit. User will **trim/compress** it; until the historical blob is removed
  (e.g., `git filter-repo`), no branch pushes. The file is gitignored and still on
  disk locally.
- **Branch naming:** all work sits on `phase1-movement-core` (it grew past Phase 1).
  Consider renaming to `main`-track work or merging once the repo can push.
- **Wall-jump vs. floor angle:** `floor_max_angle = 72°` made steep lines slideable
  but means wall-jump only triggers on >72° (near-vertical) surfaces. Revisit if
  wall-jump feels too rare (a middle value ~66°, or a dedicated "wall" tag).
- **Terrain smoothness:** strokes are angular (few points per curve). If sliding
  ever feels bumpy, re-extract with a lower RDP `--eps`, or thicken
  `InkTerrain.thickness`.
- **No automated tests / no Godot binary in the agent env:** all verification is the
  user's F5 playtest. The pure helpers (`slide_frame`, `image_to_strokes`) are
  isolated for a future headless harness.

## Tuning knobs (quick reference)

- **Slide:** `player.gd` — `SLIDE_BASE` (1.0, flat speed ×walk), `SLIDE_GAIN` (2.0,
  steepness bonus), `SLIDE_MAX_SPEED` (800), `SLIDE_ACCEL` (3500), `SLIDE_MIN/END_SPEED`.
- **Jump/air:** `JUMP_VELOCITY`, `COYOTE_TIME`, `JUMP_BUFFER_TIME`, `MAX_AIR_JUMPS`,
  `STOMP_BOUNCE`.
- **Map:** `level2.tscn` → `Terrain.world_scale` (5.0), `Player.position` (spawn),
  `LevelRoot.fall_limit` (7000).
- **Snail:** `snail.gd` — `SPEED`, `PROBE_AHEAD`, `STEP_TOLERANCE`.
- **Audio:** `Settings` autoload + `default_bus_layout.tres`.
