# REAPER: Rogue Protocol — Godot 4 port

> A rogue workshop robot and his siblings fight back against the zombie
> horde overrunning their workshop.

## The premise

A brilliant inventor built an army of mechanical helpers. One night the
dead rose, the lights went out, and the zombies poured in.

The robots have a directive: **defend the workshop. End the horde.**

You play **REAPER**, the lead unit. More robots will become playable as
the roster grows (Ringworker, X-10, the Lugnuts, eventually the
salvaged Prototype-01). Twenty waves of zombies between you and the
necromancer at their source.

## The acts

| Act | Waves | Location |
|---|---|---|
| I   | 1–7   | **THE ASSEMBLY FLOOR** — conveyor belts, half-built shells |
| II  | 8–13  | **THE LOGISTICS BAY** — pallets, shelving, fallen tools |
| III | 14–19 | **THE ENGINEERING LAB** — blueprints, prototypes, sparks |
| —   | 20    | **THE ENGINE CORE** — the source of the protocol |

| Wave | Boss |
|---|---|
| 10  | **THE IRON COLOSSUS** — bronze-and-coal industrial juggernaut |
| 20  | **PROTOTYPE-01 · THE EXILE** — the inventor called it faulty; it called itself awake |

## Combat (REAPER)

| Key | Action |
|-----|--------|
| W A S D | Move |
| Shift   | Sprint |
| Space   | Jump (+ 2 air-jumps for verticality) |
| Mouse   | Aim camera |
| **LMB** | Alternating single-hand punch (rapid, ~0.22s) |
| **RMB** | Double-fisted SMASH (360° AoE + shockwave ring, ~0.9s) |
| **R**   | Summon Ringworker ally (~15s lifetime) |
| **Q**   | **MELTDOWN** ult — 5s of 3× swing rate + 1.6× damage |
| Esc     | Pause menu (Resume / Quit to Title) |

Plays like the Hulk: fast, jumpy, brutal.

## Currency: Mechparts

Every fallen zombie drops **Mechparts** (⚙). Bank balance survives
death (50% banked) or victory (100% banked). Spend at the **Mech Repair
Shop** between runs on permanent upgrades:

| Upgrade            | Effect                         | Max levels |
|--------------------|--------------------------------|------------|
| Reinforced Chassis | +20 max HP per level           | 8 |
| Hotter Rounds      | +3 damage per level            | 8 |
| Overclocked Trigger| 10% faster swing rate per level| 5 |
| Ringworker Uplink  | -5s summon cooldown per level  | 4 |

## How to open in Godot

1. Open **`Godot_v4.6.3-stable_win64.exe`**
2. Project Manager → **Import** → browse to
   `Zombie-Fighter-Godot/project.godot` → **Import & Edit**
3. Hit **F5**. The title screen appears first.

## File layout

```
Zombie-Fighter-Godot/
├── project.godot
├── README.md
├── scenes/
│   ├── title.tscn          # entry point
│   ├── hub.tscn            # Mech Repair Shop
│   ├── main.tscn           # the workshop battleground
│   ├── player.tscn         # REAPER
│   ├── ally.tscn           # Ringworker summon
│   ├── zombie*.tscn        # enemy variants (basic / warrior / runner / x10 / lugnut)
│   ├── wave_manager.tscn   # 20-wave driver
│   └── hud.tscn
├── scripts/
│   ├── mechbank.gd         # autoload — persistent Mechparts
│   ├── title.gd / hub.gd
│   ├── player.gd / ally.gd / zombie.gd / wave_manager.gd
│   ├── workshop_dressing.gd / lava_ball.gd / procedural_anim.gd
│   └── hud.gd
└── assets/models/
    ├── reap_the_whirlwind.glb  # REAPER's body (rigged + animated)
    ├── zombie.glb              # zombie enemy
    ├── zombie_walk_test.glb    # zombie variant
    ├── enemy*.glb              # legacy robot variants (being phased out as enemies)
    ├── x10.glb / lugnut.glb    # heavy + small variants
    ├── ringworker.glb          # the summonable ally
    └── dread.glb               # legacy — kept for reference
```

## Branches

- **`main`**       — original Three.js single-file ARPG.
- **`godot-port`** — *this* — the Godot 4 reimagining. Active branch.
