# Beam

A 2D side-scrolling beat-em-up built with **Godot 4.7**. Play as a martial artist who runs, jumps, wall-jumps, slides, and chains melee attacks against enemies.

## Features

- Title screen with persistent background music
- Fluid movement: run, jump, wall-jump, crouch, and slide
- Melee combat: punch, standing kick, crouch-kick, flying kick — all with hitboxes
- Enemies with health, knockback, and death animations
- Pause menu (Escape key) with resume and quit-to-title
- Health HUD with auto-level-reset on death
- Collectable scoring
- Pen trail drawing (Q key — debug/dev feature)

## Controls

| Action | Keys |
| --- | --- |
| Move left / right | `A` / `D` or Left / Right arrows |
| Jump | `W`, `Space`, or Up arrow |
| Crouch | `S` or Down arrow |
| Punch | `J`, `Z`, or left mouse button |
| Kick | `K`, `X`, or right mouse button |
| Crouch-kick | Crouch + Punch (or Z) |
| Flying kick | Kick while airborne |
| Slide | Crouch while running (auto-kicks after 0.55s) |
| Wall jump | Jump while sliding down a wall |
| Pause | `Escape` |
| Start game | Any key / mouse click on the title screen |

## Running the project

1. Install [Godot 4.7](https://godotengine.org/).
2. Open `project.godot` in the Godot editor.
3. Press **F5** (Play) — the game boots into the title screen.

## Project structure

```
scenes/
  title_screen.tscn      # Entry scene
  Main.tscn              # Gameplay root with HUD and pause overlay
  player.tscn            # Player with animations, sounds, attack hitbox
  levels/level_root.tscn # Level tilemap, background, collectables, enemies
  collectable.tscn       # Rotating collectable with collection animation
  snail.tscn             # Enemy with patrol and hit detection
scripts/
  player.gd             # Movement, combat, wall-jump, hitbox logic
  main.gd               # Level setup, HUD, pause, death handling
  title_screen.gd       # Title screen input / scene transition
  music.gd              # Autoloaded persistent background music
  snail.gd              # Enemy patrol, health, knockback, death
  collectable.gd        # Collection logic
  pen_trail.gd          # Debug pen trail rendering
assets/
  images/               # Sprites and environment art
  sounds/               # BGM, jump, kick, punch, pistol
```

## Known limitations

- Crouch does not shrink the player's collision shape.
- The pen trail (Q key) is a debug feature and may be removed in release builds.
- Attack hitboxes are simple rectangular areas — no per-frame hurtbox tuning.
- Only one level and one enemy type currently.
- BGM loops via manual restart (minor gap between loops with MP3).

## License

Source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE). Free to use, modify, and share for **noncommercial** purposes. **Commercial use** and **use as AI/ML training data** require prior written permission — contact Ahmed Hussain (ahmedyhussain07@gmail.com).
