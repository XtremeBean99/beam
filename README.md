# Beam

A 2D action platformer built with **Godot 4.7**. Play as a martial-artist who can run, jump, crouch, and chain a small set of melee attacks.

## Features

- Title screen with looping background music that carries into gameplay
- Responsive movement: run, jump, fall, and crouch
- Melee combat: punch, standing kick, crouch-kick, and an airborne flying kick
- Non-interruptible one-shot attack animations with matching sound effects

## Controls

| Action | Keys |
| --- | --- |
| Move left / right | `A` / `D` or `←` / `→` |
| Jump | `W`, `Space`, or `↑` |
| Crouch | `S` or `↓` |
| Punch | `J` or left mouse button |
| Kick | `K` or right mouse button |
| Crouch-kick | crouch + Punch |
| Flying kick | Kick while airborne |
| Start game | any key / mouse click on the title screen |

## Running the project

1. Install [Godot 4.7](https://godotengine.org/) (Forward+ renderer).
2. Open `project.godot` in the Godot editor.
3. Press **F5** (Play) - the game boots into the title screen.

## Project structure

```
scenes/
  title_screen.tscn      # Entry scene (main scene)
  Main.tscn              # Gameplay root
  player.tscn            # Player with all animations and sound nodes
  levels/level_root.tscn # Level tilemap, background, and player instance
scripts/
  player.gd             # Movement and combat logic
  title_screen.gd       # Title screen input / scene transition
  music.gd              # Autoloaded persistent background music
assets/
  images/               # Sprites and environment art
  sounds/               # bgm, jump, kick, punch
```

## Notes

- Melee attacks are currently animation + sound only (no damage hitboxes yet).
- The crouch does not shrink the player's collision shape.

## License

Source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE). Free to use, modify, and share for **noncommercial** purposes. **Commercial use** and **use as AI/ML training data** require prior written permission - contact Ahmed Hussain (Ahmedyhussain07@gmail.com).
