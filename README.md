# Trailhead

A small RC car, loose in a big wild place. **Trailhead** is an exploration driving game built in **Godot 4.6**: you pilot a 1:10-scale radio-controlled vehicle across a faithfully reconstructed slice of Zion canyon, where the human-scale world towers around you. No timers, no enemies — just the car, the terrain, and the sense of scale.

> "Trailhead" is a working codename.

## Highlights

- **Real terrain.** The canyon is baked from public-domain USGS 1-meter LiDAR elevation and NAIP aerial imagery into a streamed, drivable heightfield with surface-classified ground.
- **Surface-dependent physics.** A raycast vehicle with honest per-wheel surface response (packed dirt, loose rock, gravel, grass, sand, water) — traction, slip, and recovery vary by what you're driving on.
- **Deterministic sim core / render host split.** The driving simulation runs headless — no window, renderer, or audio required — behind a thin interface; the renderer *hosts* the sim rather than the reverse. This is what makes the game **headlessly testable**.
- **Streamed open world.** Terrain, collision, and foliage stream in around the vehicle as you drive, with LOD and a budgeted per-frame realization pipeline.

## Requirements

- [Godot Engine 4.6](https://godotengine.org/) (Forward+ renderer)

## Run it

Open the project in Godot 4.6 (import the project at the repo root), then press **Play (F5)** — the main scene is `scenes/cedar_hollow_playable.tscn`. Drive with the arrow keys / WASD (or a connected gamepad).

From the command line:

```sh
godot --path .
```

### Headless simulation

The driving core runs without a renderer — useful for testing and automation:

```sh
godot --headless --path . res://scenes/sim_runner.tscn
```

## Project layout

| Path | What |
|---|---|
| `systems/sim/` | Deterministic simulation core (no rendering / input / wall-clock) |
| `systems/vehicle/` | Raycast vehicle controller + per-wheel surface response |
| `systems/world/` | Tile streaming, surface map, world authority |
| `systems/render/` | Render host; terrain / foliage / water visual streaming |
| `autoload/` | `GameConfig`, `EventBus`, `GameManager`, `TileStreamer` singletons |
| `scenes/` | Playable scene, headless sim runner, test scenes |
| `assets/` | Models + textures (CC0 — see [NOTICE](NOTICE)) |
| `data/` | Baked terrain (heightfield, surface IDs, region tiles) |
| `tools/` | Bake pipeline, asset / format checks, headless test fixtures |
| `tests/` | Headless test harness |

## Terrain data

The committed `data/` holds the **baked** terrain the game loads at runtime. The **raw** source rasters (USGS 1 m LiDAR DEM tiles and NAIP 2021 imagery — both U.S. public domain) are not committed here because of their size; they can be re-downloaded from [The National Map](https://apps.nationalmap.gov/downloader/) to re-run the bake pipeline under `tools/`.

## License

Source code is released under the [MIT License](LICENSE). Bundled assets and terrain source data are third-party works (all CC0 or U.S. public domain), credited in [NOTICE](NOTICE).
