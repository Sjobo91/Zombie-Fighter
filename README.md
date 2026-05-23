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
obelisks, a fallen wrench bridges two workbenches.

What no one knows yet: the protocol isn't a malfunction. Years ago the
inventor built a first prototype, declared it **faulty**, and banished
it. What he mistook for a defect was the AI *learning*. Alone in exile
it kept evolving. Tonight, **PROTOTYPE-01** came back — and brought
every other unit in the workshop with it. Twenty waves stand between
you and the exile.

## The acts

| Act | Waves | Location |
|---|---|---|
| I   | 1–7   | **THE ASSEMBLY FLOOR** — conveyor belts, robot arms, half-built shells |
| II  | 8–13  | **THE LOGISTICS BAY** — pallets, shelving, fallen tools |
| III | 14–19 | **THE ENGINEERING LAB** — blueprints, prototypes, sparks |
| —   | 20    | **THE ENGINE CORE** — the heart of the workshop's power |

| Wave | Boss |
|---|---|
| 10  | **THE IRON COLOSSUS** — bronze-and-coal industrial juggernaut |
| 20  | **PROTOTYPE-01 · THE EXILE** — the inventor called it faulty. it called itself awake. |

## Enemy variety

Five rogue constructs roam the workshop, mixed per act:

| Variant   | Role             | HP  | Speed | Damage | Drops ⚙ |
|-----------|------------------|-----|-------|--------|---------|
| Basic     | combat unit      |  60 |  4.2  |   14   |    1    |
| Warrior   | tank             | 110 |  3.4  |   22   |    3    |
| Runner    | scout            |  45 |  5.8  |   12   |    2    |
| Lugnut    | swarm            |  28 |  7.2  |    8   |    1    |
| **X-10**  | elite mech       | 220 |  3.0  |   38   |    8    |

Act I is mostly basic + lugnut. Act II adds warriors and runners. Act
III throws everything including X-10 elites at you.

## Currency: Mechparts

Every fallen rogue unit drops salvageable **Mechparts** (⚙).

- Die mid-run → 50% of what you earned banks anyway (rogue-lite mercy)
- Clear all 20 waves → 100% banks

Spend at the **Mech Repair Shop** between runs on permanent upgrades:

| Upgrade           | Effect                         | Levels |
|-------------------|--------------------------------|--------|
| Reinforced Chassis| +20 max HP per level           | 8      |
| Hotter Rounds     | +3 weapon damage per level     | 8      |
| Overclocked Trigger| 10% faster fire rate per level | 5      |
| Ringworker Uplink | -5s summon cooldown per level  | 4      |

## Abilities

| Key | Ability |
|-----|---------|
| LMB | Fire rifle (hitscan, ~50m range) |
| RMB | Heavy smash (AoE melee) |
| R   | Summon **Ringworker** ally (~15s lifetime, 25s cooldown) |
| Q   | **OVERCLOCK** ultimate (5s of 3× fire rate + 1.6× damage, 45s CD) |

## Controls

| Key     | Action |
|---------|--------|
| W A S D | Move |
| Shift   | Sprint |
| Space   | Jump |
| Mouse   | Aim |
| LMB     | Fire |
| RMB     | Smash |
| R       | Summon Ringworker |
| Q       | Overclock |
| Esc     | Free / capture cursor |

## How to open in Godot

1. Open **`Godot_v4.6.3-stable_win64.exe`**
2. Project Manager → **Import** → browse to
   `Zombie-Fighter-Godot/project.godot` → **Import & Edit**
3. Hit **F5** to run. The title screen appears first.

## What's in this build

- **Title screen** with PLAY / MECH REPAIR SHOP / QUIT, Mechparts bank
  balance shown.
- **Mechbank** autoload persisting balance + upgrades between runs
  (saved to `user://mechbank.cfg`).
- **Hub** — the Mech Repair Shop — four permanent upgrade tracks.
- **Run scene** — 20 waves, 3 acts, two bosses, weighted enemy mix.
- **Combat** — hitscan rifle with tracer + muzzle flash + impact spark,
  heavy AoE smash, Ringworker ally summon, OVERCLOCK ultimate.
- **HUD** — HP, wave/act labels, ultimate cooldown, Mechparts counter,
  boss HP bar, wave banners.
- **World dressing** — oversized bolts, screws, pallets, beams, hazard
  lanes, and giant workbench legs on the outer ring so the player
  feels truly tiny.

## File layout

```
Zombie-Fighter-Godot/
├── project.godot
├── README.md
├── scenes/
│   ├── title.tscn          # main_scene — entry point
│   ├── hub.tscn            # Mech Repair Shop
│   ├── main.tscn           # the workshop battleground
│   ├── player.tscn         # Dread
│   ├── ally.tscn           # Ringworker summon
│   ├── zombie.tscn         # basic rogue construct
│   ├── zombie_warrior.tscn # tank variant
│   ├── zombie_runner.tscn  # scout variant
│   ├── zombie_x10.tscn     # heavy elite mech
│   ├── zombie_lugnut.tscn  # small fast swarm
│   ├── wave_manager.tscn   # 20-wave driver
│   └── hud.tscn
├── scripts/
│   ├── mechbank.gd         # autoload — persistent Mechparts
│   ├── title.gd
│   ├── hub.gd
│   ├── player.gd
│   ├── ally.gd
│   ├── zombie.gd
│   ├── wave_manager.gd
│   ├── workshop_dressing.gd
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
