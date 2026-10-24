# Operation Midnight Cellar

A non-commercial PC fan game inspired by the spirit and style of Destiny, made with Godot 4.
All art is original or openly licensed; no Bungie assets are used.

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build, not .NET).
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
| Switch weapon | 1 / 2 / 3, mouse wheel | Y |
| FOV down / up | `[` / `]` (60 to 110) | |
| Free the mouse | Esc, click to recapture | |

## What's here

- `scripts/world.gd` builds a greybox hub out of primitives: a long plaza on top of a city
  wall, a tall facade with arches and banners, vendor kiosks, a parapet overlooking a city far
  below with a giant pale sphere in the sky, a sunken garden with a practice range, and a hangar.
- `scripts/player.gd` is the first-person controller: movement, sprint, jump and glide,
  camera recoil, FOV changes for aiming and sprinting.
- `scripts/weapon_data.gd` defines the weapon archetypes as data: fire mode, rate of fire,
  damage, precision multiplier, magazine, reload, zoom, spread and bloom, recoil (mostly
  vertical, mostly recovering) and damage falloff, plus the shape of each box viewmodel.
  It ships an auto rifle, a hand cannon (slow, heavy recoil, big precision bonus) and a
  scout rifle (semi-auto, long zoom, long range).
- `scripts/weapon.gd` carries one gun per slot and switches with a lower-and-raise of about
  0.35 s. Everything is procedural: walk bob, idle breathing, mouse sway, sprint pose, aim
  down sights, recoil kick, reload (mag swap, or a cylinder roll on the hand cannon),
  landing dip, muzzle flash, tracers, sparks and bullet marks. Rounds are hitscan with
  spread that blooms as you fire. On a controller it adds mild aim assist: shots just off a
  target bend toward it (heads first), and look speed slows near targets. Mouse play gets
  neither.
- `scripts/combat.gd` finds what a shot hit and shows the feedback: floating damage numbers
  (white for body hits, yellow for precision hits), the hitmarker and the target's health bar.
- `scripts/target.gd` is a practice target with health. The head is the precision spot. It
  flashes on hit, folds down when its health runs out, then resets. A tougher gold "major"
  target stands at the back of the range.
- `scripts/hud.gd` draws a reticle per weapon that opens with the current spread and turns
  red over a target in range, the hitmarker (bigger on kills), the weapon list with ammo,
  the target's name and health bar, a reload prompt and the controls hint.
