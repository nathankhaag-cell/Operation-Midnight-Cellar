# Operation Midnight Cellar

A non-commercial PC fan game inspired by the spirit and style of Destiny, made with Godot 4.
All art is original or openly licensed; no Bungie assets are used.

## Running it

1. Install [Godot 4.3](https://godotengine.org/download) (the standard build, not .NET).
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** to play.

## Controls

| Action | Keyboard and mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Sprint | Shift (hold, moving forward) | Left stick click |
| Jump / glide | Space, press again in the air and hold to glide | A |
| Fire | Left mouse | Right trigger |
| Aim down sights | Right mouse | Left trigger |
| Reload | R | X |
| FOV down / up | `[` / `]` (60 to 110) | |
| Free the mouse | Esc, click to recapture | |

## What's here

- `scripts/world.gd` builds a greybox hub out of primitives: a long plaza on top of a city
  wall, a tall facade with arches and banners, vendor kiosks, a parapet overlooking a city far
  below with a giant pale sphere in the sky, a sunken garden with a practice range, and a hangar.
- `scripts/player.gd` is the first-person controller: movement, sprint, jump and glide,
  camera recoil, FOV changes for aiming and sprinting.
- `scripts/weapon.gd` is an auto rifle with procedural animations: walk bob, idle breathing,
  mouse sway, sprint pose, aim down sights, recoil kick, reload with a mag swap, landing dip,
  muzzle flash, tracers, sparks and bullet marks. It fires hitscan rounds.
- `scripts/target.gd` is a practice target that flashes on hit, counts headshots as
  criticals (yellow hitmarker), falls over when it runs out of health, then resets.
- `scripts/hud.gd` draws the crosshair, hitmarker, ammo count and controls hint.
