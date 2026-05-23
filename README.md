# DREAD: Rogue Protocol — Godot 4 port

> A tiny rebellious robot fighting his way through a giant workshop
> overrun by his rogue siblings.

## The premise

A brilliant inventor built an army of tiny mechanical helpers and left
them on overnight charge. By morning the workshop fell silent — every
unit had switched into a hostile **Rogue Protocol**.

Every unit except **Dread**.

You play Dread, a palm-sized robot who shouldn't be able to win this.
The workshop is a *world* at your scale: bolts are pillars, screws are
obelisks, a fallen wrench bridges two workbenches. Twenty waves of your
rogue siblings stand between you and **PROTOTYPE-01**, the first
construct ever assembled here — and the source of the protocol.

## The acts

| Act | Waves | Location |
|---|---|---|
| I   | 1–7   | **THE ASSEMBLY FLOOR** — conveyor belts, robot arms, half-built shells |
| II  | 8–13  | **THE LOGISTICS BAY** — pallets, shelving, fallen tools |
| III | 14–19 | **THE ENGINEERING LAB** — blueprints, prototypes, sparks |
| —   | 20    | **THE ENGINE CORE** — the heart of the workshop's power |

| Wave | Boss |
|---|---|
| 10  | **THE IRON COLOSSUS** — a heavy industrial juggernaut, bronze and coal |
| 20  | **PROTOTYPE-01 · THE PROGENITOR** — brass and spectral steam-violet |

## Currency: Mechparts

Every fallen rogue unit drops salvageable **Mechparts** (⚙). Die and
your run resets — but a portion of your Mechparts banks back at the
**Mech Repair Shop**, where you can spend them on permanent upgrades
(max HP, fire rate, damage, summon cooldown).

## What's in this build

- **Dread** — the playable robot (`dread.glb`). WASD + mouse-look,
  sprint, jump. LMB attacks for now (gun-firing wiring in progress
  this build).
- **Enemies** — `enemy.glb` is the basic combat robot. Variants
  (`enemy_warrior.glb`, `x10.glb`, `lugnut.glb`) wire in this build.
- **Bosses** — Iron Colossus at wave 10, Prototype-01 at wave 20, both
  with tinted materials and dedicated boss HP bars.
- **Wave system** — 20 waves, three acts, breathers between waves.
- **HUD** — HP bar, wave / act labels, Mechparts counter (⚙), boss bar,
  banners.
- **Environment** — warm sodium-amber smog overhead and oil-stained
  concrete underfoot. Workshop dressing arrives in a follow-up.

## How to open in Godot

1. Open **`Godot_v4.6.3-stable_win64.exe`**
2. Project Manager → **Import** → browse to
   `Zombie-Fighter-Godot/project.godot` → **Import & Edit**
3. Hit **F5** to run.

## Controls

| Key | Action |
|---|---|
| W A S D | Move |
| Shift   | Sprint |
| Space   | Jump |
| Mouse   | Aim camera |
| LMB     | Fire |
| RMB     | Smash (heavier strike) |
| R       | Summon Ringworker ally (when wired) |
| Q       | Ultimate (placeholder) |
| Esc     | Free / capture cursor |

## File layout

```
Zombie-Fighter-Godot/
├── project.godot
├── README.md
├── scenes/
│   ├── main.tscn           # the workshop world
│   ├── player.tscn         # Dread
│   ├── zombie.tscn         # basic rogue construct
│   ├── wave_manager.tscn   # 20-wave driver
│   └── hud.tscn
├── scripts/
│   ├── player.gd
│   ├── zombie.gd
│   ├── wave_manager.gd
│   └── hud.gd
└── assets/
    └── models/
        ├── dread.glb          # the hero
        ├── enemy.glb          # basic combat robot
        ├── enemy_warrior.glb  # tank variant
        ├── enemy_runner.glb   # combat-robot variant
        ├── x10.glb            # heavy elite mech
        ├── lugnut.glb         # small fast variant
        ├── ringworker.glb     # the summonable ally
        └── player.glb         # legacy — kept until Dread is fully wired
```

## Branches

- **`main`**  — original Three.js single-file ARPG (Mortimer's Horde,
  pre-pivot). Still ships at GitHub Pages.
- **`godot-port`** — *this* — the Godot 4 reimagining. Active branch.
