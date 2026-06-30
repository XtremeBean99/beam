# Beam — Next-Session Roadmap

> Forward plan for expanding the game per the design spec
> (`docs/superpowers/specs/2026-06-29-beam-movement-ink-ui-design.md`). Pick up
> from the top of "Priorities" below.

## Where we are (shipped this session)

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
