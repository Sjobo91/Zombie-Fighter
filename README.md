# Mortimer's Horde — Godot 4 port

## The story

The brilliant inventor **Mortimer** built constructs to bring his dead
queen back. The machines turned on him, and now his gothic kingdom is
swarmed by his rogue creations.

**You** are an autonomous Mech-Police unit dispatched when the city
fell silent. **Twenty waves** between you and the source.

- **Act I (waves 1–7) — The Graveyard**
- **Act II (waves 8–13) — The City**
- **Act III (waves 14–19) — The Cathedral**
- **Wave 10 — The Iron Colossus** (mini-boss)
- **Wave 20 — Mortimer, The Forsaken Engineer** (final boss)

Die and you start over. **Soulshards** the wreckage drops follow you
home — spend them at the **Fallen Hero's Camp** (next build) on
permanent upgrades.

## What's here so far

- **Player** — Mech Robotic Police unit (third-person, WASD + mouse
  look + sprint + sword-swing-on-LMB while the visual gets polished).
- **Enemies** — steampunk gevechtsrobots that march toward you and
  strike on contact. 38 HP each.
- **Bosses** — wave 10 / 20 special spawns with tinted materials and
  dedicated HP bars.
- **Wave system** — 20 waves across 3 acts.
- **HUD** — HP, wave counter, act name, Soulshards counter, boss bar,
  banners.

## How to open in Godot

1. Open **`Godot_v4.6.3-stable_win64.exe`**
2. Project Manager → **Import** → browse to
   `Zombie-Fighter-Godot/project.godot` → **Import & Edit**
3. Hit **F5** to run.

## Controls

| Key | Action |
|---|---|
| W A S D | Move |
| Shift | Sprint |
| Space | Jump |
| Mouse | Aim camera |
| LMB | Attack |
| Esc | Free / capture cursor |

## File layout

```
Zombie-Fighter-Godot/
├── project.godot
├── README.md
├── scenes/
│   ├── main.tscn               # the world
│   ├── player.tscn             # the Mech-Police player
│   ├── zombie.tscn             # the basic robot enemy
│   ├── wave_manager.tscn       # 20-wave driver
│   └── hud.tscn
├── scripts/
│   ├── player.gd
│   ├── zombie.gd               # enemy AI
│   ├── wave_manager.gd
│   └── hud.gd
└── assets/
    ├── models/
    │   ├── player.glb          # Mech-Police w/ scifi gun (the hero)
    │   ├── enemy.glb           # steampunk combat robot (default enemy)
    │   ├── enemy_runner.glb    # combat robot (variant — not wired yet)
    │   ├── enemy_warrior.glb   # robot warrior (variant — not wired yet)
    │   └── ringworker.glb      # bad-ass elite — usage TBD
    └── audio/
```

## The Ringworker — what is it?

`ringworker.glb` is parked. It's a "bad-ass" model the developer liked
but hasn't decided what to do with. Three good options:

1. **Summon-ally** — once per run, press R to call in a Ringworker that
   fights alongside you for ~15 seconds.
2. **Elite enemy** — appears rarely (5% per spawn) as a tougher variant.
3. **Wave-15+ enemy** — Act III gets these as the elite force right
   before Mortimer.

Decide before the Hub build is done.
