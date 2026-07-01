# Beam

A fast, movement-focused 2D platformer built with **Godot 4.7**, with a hand-drawn
"ink & void" aesthetic. Levels are traced as ink strokes and built into terrain at
runtime; you clear each one by flowing through it — sliding, wall-jumping, and
turning your own momentum into your main weapon.

## Features

- **Ink terrain** — levels are authored as SVG strokes and built into glowing
  collision geometry at runtime (`svg_parser` → `ink_terrain` → `ink_stroke`).
- **Fluid movement** — run, jump, double-jump, wall-jump, and a momentum slide with
  slope-based, gravity-driven speed. Coyote time and jump buffering keep it forgiving.
- **Combat through movement** — slide into enemies to defeat them, stomp them from
  above, or spend a fireball charge (charges are earned per kills).
- **Enemies** — ground-patrolling snails, aerial flyers, and a tougher boss, all
  sharing one `enemy_base` (contact rules, hit flash, death animation).
- **Hazards** — spikes (instant death) and falling off the map both kill the player
  and restart the level from the current attempt.
- **Platforms** — horizontal moving platforms that carry the player between markers,
  and crumbling platforms that break away a few moments after you land on them.
- **Level flow** — a level is cleared by collecting every token **or** clearing the
  enemies inside its boss-room panel; an exit door then appears where the last token
  was grabbed / last boss-room enemy fell.
- **Three levels** plus a tutorial with in-world text signs.
- **HUD** — health pips, score, kills, a fireball-charge ensō, and a live speedrun clock.
- **End-of-run screen** — total time and tokens collected as a percentage.
- Title screen, pause menu, settings (volume), scene transitions, and persistent music.

## Controls

| Action | Keys |
| --- | --- |
| Move left / right | `A` / `D` or Left / Right arrows |
| Jump / double-jump | `W`, `Space`, or Up arrow (press again in the air) |
| Wall jump | Jump while against a wall |
| Crouch | `S` or Down arrow |
| Slide | Crouch while running (jump to launch or cancel; double-jump in a flying slide drops straight down) |
| Fireball | `L` (needs a charge) |
| Pause | `Escape` |
| Start game | Any key / mouse click on the title screen |

## Running the project

1. Install [Godot 4.7](https://godotengine.org/).
2. Open `project.godot` in the Godot editor (first open imports the art assets).
3. Press **F5** (Play) — the game boots into the title screen.

## Project structure

```
scenes/
  title_screen.tscn        # Entry scene
  Main.tscn                # Gameplay root: HUD, pause overlay, level slot
  player.tscn              # Player: animations, sounds, camera, trail
  levels/level1..3.tscn    # Campaign levels (level1 = tutorial)
  spike.tscn               # Instant-kill hazard
  platform.tscn            # Horizontal moving platform (marker endpoints)
  crumbling_platform.tscn  # Breaks away after the player lands
  snail/flyer/boss.tscn    # Enemies
  collectable.tscn         # Token with collection animation
  ui/text_sign.tscn        # In-world tutorial sign
scripts/
  player.gd                # Movement, slide physics, fireball, death
  main.gd                  # Campaign flow, HUD, timer, completion, end screen
  ink_level.gd             # Per-level controller: fall-death + exit door
  ink_terrain.gd/ink_stroke.gd/svg_parser.gd   # SVG → terrain pipeline
  enemy_base.gd (+ snail/flyer/boss)            # Enemy behaviour
  moving_platform.gd/crumbling_platform.gd/spike.gd/text_sign.gd
  level_complete.gd        # Level-complete + end-of-run screen
assets/
  images/                  # Sprites and environment art
  levels/                  # Level stroke sources (SVG / JSON)
  sounds/                  # BGM, jump, kick, punch, pistol
shaders/
  white_silhouette.gdshader # Flat-white silhouette (used by the exit door)
```

## Known limitations

- Enemy / collectable / hazard / platform placement in the levels is authored by
  hand and may need in-editor tuning.
- Crouch does not shrink the player's collision shape.
- Boss-room detection uses a hand-placed `Bossroom` panel per level.
- BGM loops via manual restart (minor gap between loops with MP3).

## License

Source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE). Free to use, modify, and share for **noncommercial** purposes. **Commercial use** and **use as AI/ML training data** require prior written permission — contact Ahmed Hussain (ahmedyhussain07@gmail.com).
