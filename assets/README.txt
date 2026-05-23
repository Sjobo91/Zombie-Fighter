MORTIMER'S HORDE — assets folder
================================

Drop .glb (or .gltf) 3D models into ./models/ to upgrade the procedural
primitive characters to real imported geometry.

Recognised file names (case-sensitive, on Windows it doesn't matter):

  models/knight.glb       — replaces the Knight player model
  models/wizard.glb       — replaces the Wizard player model
  models/gunslinger.glb   — replaces the Gunslinger player model
  models/hunter.glb       — replaces the Hunter player model
  models/rogue.glb        — replaces the Rogue player model

The game checks for these on launch via fetch(); if the file isn't there
(404) the primitive fallback stays. If the file IS there, the primitives
hide and the imported scene takes their place.

Recommended sources for free .glb models:

  - https://sketchfab.com  (filter "Downloadable" + license)
  - https://www.cgtrader.com (free section)
  - https://kenney.nl/assets (CC0)
  - https://quaternius.com (CC0)

Notes:
  - Models should face +Z (forward) and have their feet roughly on the
    XZ-plane (y = 0). The game positions the imported scene at the
    primitive's origin (waist height).
  - Default scale is 1. If your model is tiny or huge you'll need to
    edit the call to tryImport(g, "...", scale) in index.html.
  - Animations are NOT yet wired up — the game still drives a static
    pose by rotating the .userData.arm/.legs anchor groups, which only
    exists on the primitive. An imported .glb will look stiff for now;
    animation support is a follow-up task.
