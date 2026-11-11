# Global 3D brick rendering (experimental)

The default in-process game now instantiates actual grid-cell box meshes rather
than camera-facing BRK billboards. Every unique BRK image creates one 24-vertex
(flat-shaded) `ArrayMesh`; existing per-BRK `MultiMeshInstance3D` batches and
instance cell coordinates remain unchanged.

## BRK projection

BRK images are already isometric screenshots of authored bricks. Each box
vertex is mapped into source BRK pixel space with the fixed original LBA
isometric basis, `GRID_GRAPH_ORIGIN_PIXELS`, and BRK `hot_x/hot_y`.
This is *projective texture mapping*, not reconstructing all the original
artwork's geometry. Thin sprites, sloped surfaces, foliage, overhangs and
painted detail beyond the cell's cube cannot be represented faithfully by a
simple box; they need dedicated meshes or retained sprite overlays.

## Depth and shader

The box surface writes ordinary 3D GPU depth. `lba_tile.gdshader` skips its
old cell-origin `POSITION` override for normal operation, but retains the
existing nearest BRK sampling, alpha cutout, emission baseline, quantized
per-light shading, and optional `normal_texture`.

Existing character palette and dither shading is retained. Its legacy
`actor_depth_span` vertex transform is disabled for gameplay in this mode,
so actors and bricks use the same depth buffer. The shader's preview path
and parameters are preserved, and no native gameplay or collision logic is
modified.

World-space normal-map RGB can be enabled on the tile shader using
`has_normal_map=true` and `normal_map_world_space=true`; RGB maps
`world normal * 0.5 + 0.5`. For tangent-space maps set
`normal_map_world_space=false` (requires suitable mesh tangents).
Without a normal texture the box face normals provide a base for lighting.
The existing `ambient_fraction=1.0` preserves fully hand-shaded original art;
reduce it to opt into Godot light contributions.

## A/B toggle

Default: projected boxes in all decoded scenes and grid overlays.

Fallback: run with `LBA_BRICK_BILLBOARDS=1` to re-enable the legacy
camera-facing quads, original cell-origin brick depth, and actor depth-span.
The value is read when the game scene and actors are created. Restart to toggle.

## Validation

Run `godot --headless --path . --script res://tests/validate_projected_bricks.gd`
(or your installed `godot4` equivalent). This checks geometry, UVs and
outward winding. In-game visual evaluation is still required, and a working
Godot runtime plus the user's original LBA media is needed for it.

## Limitations

- The default cube is `CELL_XZ` square and `CELL_Y` tall, centered on the
  decoded grid coordinate. Native LBA art is an isometric bitmap, not a true
  3D model. Accuracy varies by brick artwork.
- Changing camera orientation invalidates the fixed source projection look;
  it will not reveal newly painted sides.
- BRK pixel transparency on the projected box can expose blank regions. The
  old sprite could extend past cube bounds; those pixels do not exist on the
  new geometry. Preserve or model such features separately.
- The Compatibility renderer's MultiMesh per-object light limits still apply.
