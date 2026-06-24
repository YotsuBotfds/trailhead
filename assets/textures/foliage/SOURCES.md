# Foliage Texture Sources

CC0 bark + leaf-atlas textures for the riparian foliage (willow / cottonwood / juniper / yucca).
Acquired for C1 of the 2026-06-24 external audit (untextured foliage). Mirrors the convention in
`assets/textures/surface_visuals/ambientcg/SOURCES.md`.

- Download date: 2026-06-24
- License: **CC0 1.0 Universal** (public domain). Poly Haven assets per https://polyhaven.com/license ;
  ambientCG assets per https://docs.ambientcg.com/license/ . No attribution required.
- Source archives are NOT retained in-repo (recorded by SHA-256 below); re-download from the URLs to reproduce.

## Bark PBR

| File(s) | Source asset | URL | Channel | SHA-256 (source file/archive) |
|---|---|---|---|---|
| `bark_willow_albedo.jpg` | Poly Haven `bark_willow` (diff 1k) | [asset](https://polyhaven.com/a/bark_willow) / [file](https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_willow/bark_willow_diff_1k.jpg) | albedo (sRGB) | `c7de3072c2320934a3d9f5bc6c9cb58819952c0b3bd04f4e71b24cf89dbb6ad6` |
| `bark_willow_normal.jpg` | Poly Haven `bark_willow` (nor_gl 1k) | [file](https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_willow/bark_willow_nor_gl_1k.jpg) | normal (GL/+Y, linear) | `9d5a771315a85c2d890526af9826843e7967ed3330da49bef7e86c3e5a6c0b6a` |
| `bark_willow_arm.jpg` | Poly Haven `bark_willow` (arm 1k) | [file](https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_willow/bark_willow_arm_1k.jpg) | packed ARM — AO=R, Roughness=G, Metallic=B (linear) | `e95d9655dbb91b9be744718bb79e3ff1ad5c00dd4eed8de69bd6c381e8d8b0e9` |

`bark_willow` is the **primary, wired** bark — generic furrowed riparian bark; per-species `albedo_color`
tints differentiate trunk hue (willow brown, cottonwood pale grey-tan, juniper shaggy, yucca stalk).

| File(s) | Source asset | URL | Channel | SHA-256 (source archive) |
|---|---|---|---|---|
| `bark006_albedo.jpg`, `bark006_normal.jpg`, `bark006_roughness.jpg`, `bark006_ao.jpg` | ambientCG `Bark006` (1K-JPG) — Color / NormalGL / Roughness / AmbientOcclusion | [asset](https://ambientcg.com/view?id=Bark006) / [zip](https://ambientcg.com/get?file=Bark006_1K-JPG.zip) | albedo (sRGB) / normal (GL, linear) / roughness (linear) / ao (linear) | archive `2eba78074c48f3c718d11b355e02b702ded71c2e2d191d34960f178ad917d3ab` |

`Bark006` is a **retained, NOT-wired** alternative — coarser furrows, cottonwood-leaning. Available if the
owner wants a distinct cottonwood bark vs the willow bark currently shared across species.

## Leaf atlas (alpha cutout) — RETAINED, NOT WIRED

These exist for the **future leaf-cluster geometry regen** (Approach B in
`planning/c1-foliage-texture-plan.md`). Current leaf surfaces are ico-sphere clusters with spherical
(per-vertex-unique) UVs; wiring this atlas onto them would smear. **Do NOT wire until `gen_foliage_glb.py`
emits crossed-quad leaf cards with planar 0..1 atlas UVs.**

| File(s) | Source asset | URL | Notes | SHA-256 (source archive) |
|---|---|---|---|---|
| `leafset004_atlas_rgba.png` | ambientCG `LeafSet004` (Color + Opacity composited) | [asset](https://ambientcg.com/view?id=LeafSet004) / [zip](https://ambientcg.com/get?file=LeafSet004_1K-PNG.zip) | RGBA — RGB=Color, A=Opacity. The cutout-ready sheet for `alphaMode=MASK` leaf cards. | archive `201a04544a9dbb1e0db31ba873bb38039f501cfaea82a95d0f594167210e2472` |
| `leafset004_color.png`, `leafset004_opacity.png`, `leafset004_normal.png`, `leafset004_roughness.png` | ambientCG `LeafSet004` source maps | (same zip) | Unmerged source maps retained for re-authoring the per-species atlas / leaf normals. | (same archive) |

`leafset004_atlas_rgba.png` was built locally: `RGBA = Color.rgb + Opacity.L` (Pillow). The `.import`
preserves alpha (`premult_alpha=false`, `fix_alpha_border=true`, mipmaps on).
