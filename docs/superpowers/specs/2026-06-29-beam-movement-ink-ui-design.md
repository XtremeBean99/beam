# Beam — Fluid Movement & "Ink & Circuit" UI Design

**Date:** 2026-06-29
**Status:** Approved design (pre-plan)
**Engine:** Godot 4.7

---

## 1. Overview

Beam is pivoting from a tile-based beat-'em-up prototype into a **fluid-movement
platformer** with a **monochrome, hand-drawn "futuristic tech monk"** identity.
Level 1's tileset and the player-drawn-platform mechanic were test scaffolding and
are being retired. The player ("the monk") expresses combat *through movement* —
stomping, slide-killing, and a charge-gated fireball — rather than through attack
buttons.

This document is the single source of truth for the work. It will be implemented
in phases (see §11) but specified as one whole.

### Goals
- A fluid, expressive movement set: run, variable jump, double jump, wall slide +
  wall jump, momentum slide — with coyote time and jump buffering.
- Combat emerges from movement (stomp, slide-kill, charged fireball). No attack buttons.
- A reusable **InkStroke** primitive that renders hand-drawn glowing terrain with
  matching collision, used to build **Level 2** traced from `assets/images/map2.png`.
- A cohesive **Ink & Circuit** UI: one shared Theme, monochrome void-and-glow,
  with title, HUD, pause, settings, and level-complete screens.
- A luminous **afterglow trail** on the player during fast movement.

### Non-goals (this iteration)
- New enemy types beyond the existing snail.
- Networked/online features, controller remapping UI beyond keyboard rebinding.
- A full multi-level campaign (only Level 2 is authored; flow is built to extend).

### Settled assumptions
- **A1** — Level 1 (`scenes/levels/level_root.tscn` + the tileset) is **retired**:
  kept in the repo for reference but removed from the play path. The boot flow
  becomes Title → Level 2.
- **A2** — The fireball stays **ground-only** for now, behind a single tunable
  constant so it can be opened up to air use later.
- **A3** — The per-enemy floating health bars are **removed**, replaced by a brief
  monochrome **hit-flash** + knockback. No persistent enemy health UI.

---

## 2. Design language — "Ink & Circuit"

A deliberate tension between an organic **monk** half and a precise **tech** half.

- **World = organic:** wobbly hand-drawn ink strokes, uneven weight, generous
  negative space, slow breathing motion.
- **UI = tech:** thin straight geometric framing, corner brackets/reticles,
  monospace readouts, crisp snappy feedback.
- **Shared emblem:** the **ensō** (single-stroke incomplete circle) recurs as the
  logo, the charge meter, the level-complete motif, and selection accents.

**Palette — monochrome "void-and-glow":** luminous bone-white / pale-grey linework
on a deep near-black void (`#0E0F12`). **Brightness, not hue, signals importance** —
a brighter white glow marks active/selected/ready states.

**Typography:** a calligraphic/condensed **display** face for titles and the ensō
wordmark; a clean **monospace** for HUD numerals (HP / SCORE / charge). Generous
letter-spacing. All monochrome.

**Motion:** ambient elements *breathe* (slow sine ease in/out); interactive
elements *snap* with a brief glow pulse on focus/confirm.

**UI design discipline:** a single shared `Theme`; consistent spacing scale;
clear visual hierarchy (one primary action per screen); strong contrast within the
monochrome range; always-visible focus and pressed/disabled states; readouts
anchored to corners so the play space stays clear.

---

## 3. Core primitive — `InkStroke`

The technical heart of the hand-drawn world.

- **Files:** `scripts/ink_stroke.gd`, `scenes/ink_stroke.tscn`.
- **Inputs (exported):** `points: PackedVector2Array`, `thickness: float`
  (default ~16), optional `closed: bool`, optional glow/width styling.
- **Behavior at `_ready()`:**
  1. Render a `Line2D` along `points` — monochrome with a soft glow (bright core,
     faint outer), uneven cap for an inked feel.
  2. Build a **thickened collision polygon** from the polyline (offset each point
     by its averaged perpendicular ± `thickness/2`) into a `StaticBody2D` +
     `CollisionPolygon2D` on the world collision layer.
- **Source of the math:** the polyline-thickening logic currently living in
  `main.gd` (`_build_thick_platform`, `_get_perpendicular`) migrates here and the
  originals are deleted.
- **Why option A (thickened polygon)** over segment chains or filled silhouettes:
  it handles slopes, curves, *and* detached floating platforms; it is robust
  against tunneling at a sane thickness; and it matches the visible line exactly.

This is now an **authoring** tool only — there is no runtime player drawing.

---

## 4. Movement core (`player.gd` rewrite)

CharacterBody2D. Existing constants kept where noted; new fluidity features added.

| Feature | Spec |
| --- | --- |
| Run | Momentum-based: accelerate toward max (~`SPEED 300`) with ground accel; friction decel on release. Reduced air control. |
| Jump | `JUMP_VELOCITY -700`, `GRAVITY 980`. **Variable height** (release early cuts upward velocity). |
| Coyote time | ~`0.1s` grace to still jump shortly after leaving ground. |
| Jump buffer | ~`0.1s` — a jump pressed just before landing fires on land. |
| Double jump | **One** air jump (`MAX_AIR_JUMPS 1`). Resets on floor. |
| Wall slide | Keep: only when pushing into wall and falling; reduced slide gravity. |
| Wall jump | Keep refined `WALL_JUMP_HORIZONTAL/VERTICAL`. **Wall contact / wall-jump refunds the air jump** → fluid wall-to-wall chains. |
| Slide | Hold crouch while moving on ground; keep slope-acceleration (`SLIDE_*`). Jump cancels. **No auto-kick.** |

### 4.1 Speed-driven slide animation
While sliding, the **crouch-kick animation is scrubbed by speed** instead of
auto-playing:
- Compute `t = clamp((slide_speed - SLIDE_ANIM_MIN) / (SLIDE_ANIM_MAX - SLIDE_ANIM_MIN), 0, 1)`.
- Hold the crouch-kick animation (no autoplay) and set
  `frame = round(t * (frame_count - 1))`.
- At low speed it reads as a crouch; as the slide accelerates it advances through
  the kick frames so the kick visually "extends" with speed.
- Above `SLIDE_ARMED_SPEED` the slide is **armed** (deals contact damage — see §5).

### 4.2 Removed combat
Standing kick, flying-kick, the falling-attack auto-fireball, and the
auto-kick-on-slide-release are all deleted from `player.gd`.

---

## 5. Combat through movement

No attack buttons. Health stays at `3` with i-frames on hurt (kept).

- **Stomp** — airborne and falling (`velocity.y > 0`) with the enemy below the
  player → `enemy.take_damage(...)`, player **bounces** (~`-450`) and **refunds the
  air jump**.
- **Slide-kill** — armed high-speed slide (`slide_speed >= SLIDE_ARMED_SPEED`) into
  an enemy → `enemy.take_damage(...)` with knockback in the slide direction; the
  player keeps sliding.
- **Fireball (charged special)** — thrown with the **punch animation** (kept).
  Spends one charge; **ground-only** for now (`FIREBALL_GROUND_ONLY = true`, A2).
- **Contact priority:** stomp / slide-kill are checked first; any other
  player–enemy contact calls `player.hurt()`.

### 5.1 Charge meter
- `kills` accrue when a player-caused hit kills an enemy. **Every 3 kills grants 1
  fireball charge**, capped at `MAX_CHARGES` (~3).
- **Kill crediting:** the enemy emits a `died` signal; `main.gd` (the level
  coordinator) counts kills, grants charge on each 3rd, and updates the HUD charge
  ensō.

---

## 6. Enemies

- The **snail** remains the single hazard type: dispatch by stomp, slide-kill, or
  fireball.
- `take_damage(amount, knockback_dir)` kept; on death the enemy emits `died`
  (new) so charge can be credited.
- **Floating health bars removed (A3):** replaced by a brief monochrome hit-flash
  (bright flash) + the existing knockback. Fits the palette and reduces clutter.

---

## 7. Level 2 — the InkStroke world

- **File:** `scenes/levels/level2.tscn` (+ a small `scripts/level2.gd` if needed
  for goal wiring).
- **Terrain:** several `InkStroke` instances traced over `map2` — the two long
  ground curves, the ramp/slope, the small platform, and minor accents. `map2` is
  shown as a faint authoring guide (a low-opacity `TextureRect`) and hidden at
  runtime.
- **Contents:** player spawn, snail enemies, collectables, and an **ensō goal
  gate** (Area2D) that fires level-complete.
- **Respawn:** fast respawn at the start (or a placed checkpoint) on death —
  movement-game pacing, replacing the current full `reload_current_scene()` delay.
- **Background:** monochrome void with subtle parallax ink/circuit motifs.
- **Level 1:** retired per A1 (kept in repo, off the play path).

---

## 8. UI — Ink & Circuit screens

All screens consume one shared **`theme.tres`** (display + mono fonts; thin
bright-outline Button/Panel/Label styles; glow on focus; pressed/disabled states).

- **Title** — void background (retire `aishot-1341.jpg`); **ensō + "BEAM"
  wordmark**; vertical menu **Play / Settings / Quit** with tech-bracket selection;
  breathing prompt.
- **HUD** — corner-anchored, thin-lined: **HP** as 3 segments/pips (top-left),
  **SCORE** in mono numerals, and a **charge ensō** that fills with kills and glows
  when a fireball is ready.
- **Pause** — dimmed void + ensō: **Resume / Settings / Quit**.
- **Settings** — **master / music / SFX** volume via audio buses + **keyboard
  rebinding**, persisted with `ConfigFile` (`scripts/settings.gd`). (Was deferred
  item 2.1.)
- **Level complete** — the incomplete ensō **closes** as the reward motif; shows
  **time / score / kills**; Continue.
- **Transitions** — a simple **ink-wipe** fade between scenes.

---

## 9. Player afterglow trail

- **Files:** `scripts/player_trail.gd` (+ node under the player).
- **Behavior:** during fast states (slide, wall-jump, double jump, or speed above a
  threshold) spawn a fading **afterimage** — a `Sprite2D` copy of the current sprite
  frame at the player's transform, pure white with **additive blend**, fading alpha
  to 0 over ~`0.25s`, then freed.
- **Cadence:** emit every ~`0.04s` while active. Tunable interval, lifetime, and
  speed threshold. Disabled while idle/slow to keep the look restrained.

---

## 10. Cleanup / removals

- **Draw mechanic:** delete `scripts/pen_trail.gd` (+ `.uid`), the `DrawTrail`
  node, the `draw` input action in `project.godot`, and all draw logic in
  `main.gd` (`_start/_continue/_finish_drawing`, `_build_thick_platform`,
  `_get_perpendicular`, `_fade_platform`, `_remove_platform*`). The thickening math
  moves to `InkStroke` (§3).
- **Combat:** strip removed attacks from `player.gd` (§4.2).
- **Assets:** remove genuinely unused assets (angel, wizard, `pistol.wav`). **Keep
  the fireball** — it is now used.

---

## 11. Implementation phasing

A suggested build order (each phase independently testable):

1. **Movement core** — `player.gd` rewrite: accel/friction, variable jump, coyote
   time, jump buffer, double jump, wall-jump refund, slide + speed-scrubbed
   animation. Remove combat + draw mechanic.
2. **Combat through movement** — stomp, slide-kill, charge meter, fireball gating;
   enemy `died` signal + hit-flash; kill crediting in `main.gd`.
3. **InkStroke + Level 2** — primitive, then author `level2.tscn` from `map2`,
   goal gate, respawn; retire Level 1.
4. **Theme + UI screens** — `theme.tres`, then title / HUD (with charge ensō) /
   pause / level-complete; ink-wipe transitions.
5. **Settings + flow** — volume buses, key rebinding, `ConfigFile` persistence.
6. **Afterglow trail** — `player_trail.gd` (can land alongside phase 1/2).

---

## 12. Testing

- **Movement:** manual playtest checklist — coyote/buffer windows feel right;
  double jump refunds on wall; wall-to-wall chaining works; slide arms at speed and
  the animation scrubs smoothly; variable jump height responds to release.
- **Combat:** stomp/slide-kill/fireball each kill a snail; non-special contact
  hurts the player; charge increments every 3 kills and the fireball spends one;
  ground-only gating holds.
- **InkStroke:** authored strokes produce collision matching the visible line on
  slopes and floating platforms; no tunneling at run speed.
- **UI:** every screen uses the shared theme; focus/hover/pressed/disabled states
  visible; settings persist across restarts; rebinding takes effect immediately.
- Where practical, add lightweight GdUnit4 tests for pure logic (charge math,
  coyote/buffer timers, InkStroke polygon generation).
