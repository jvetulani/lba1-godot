#!/usr/bin/env python3
"""Generate one editable Godot scene per movie:* asset in a converted LBA1 manifest.
Does not overwrite DreamSequence/DragonBoot or custom edits.
"""
import argparse, json, re
from pathlib import Path

TEMPLATE = '''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/lba_movie_preview.gd" id="1_preview"]

[node name="{name}" type="Control"]
offset_right = 640.0
offset_bottom = 480.0
mouse_filter = 2
script = ExtResource("1_preview")
movie_name = "{stem}"

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 1)

[node name="Picture" type="Control" parent="."]
layout_mode = 1
offset_right = 640.0
offset_bottom = 480.0
mouse_filter = 2

[node name="EditorPoster" type="TextureRect" parent="Picture"]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
expand_mode = 1
stretch_mode = 5
mouse_filter = 2

[node name="PreviewHint" type="Label" parent="Picture"]
visible = false
layout_mode = 1
anchor_left = 0.1
anchor_top = 0.4
anchor_right = 0.9
anchor_bottom = 0.6
horizontal_alignment = 1
vertical_alignment = 1
autowrap_mode = 3
text = "Generate video previews using tools/make_video_posters.py"

[node name="Movie" type="VideoStreamPlayer" parent="."]
layout_mode = 1
offset_right = 640.0
offset_bottom = 480.0
expand = true
bus = &"LBA Cinematics"
'''

def generate(project: Path, cache: Path) -> list[str]:
    manifest = json.loads((cache / 'manifest.json').read_text())
    assets = manifest.get('assets', {})
    stems = sorted(
        {key[6:] for key in assets if key.startswith('movie:') and isinstance(assets[key], dict)
         and (cache / str(assets[key].get('path', ''))).is_file()}
        | {p.stem.lower() for p in (cache / 'movies').glob('*.ogv') if p.stat().st_size > 32}
    )
    target = project / 'scenes/ui/previews'
    target.mkdir(parents=True, exist_ok=True)
    for stem in stems:
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', stem):
            print('Skipping unsupported movie stem:', stem)
            continue
        if stem in ('introd', 'dragon3'):
            continue
        name = 'Movie_' + stem
        scene = target / (name + '.tscn')
        if not scene.exists():
            scene.write_text(TEMPLATE.format(name=name, stem=stem))
        else:
            print('Existing scene kept:', scene.name)
    return stems

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=Path.cwd())
    parser.add_argument('--media-cache', type=Path, required=True)
    args = parser.parse_args()
    if not (args.project / 'project.godot').exists() or not (args.media_cache / 'manifest.json').exists():
        parser.error('Provide a valid Godot project and converted media-cache containing manifest.json')
    stems = generate(args.project, args.media_cache)
    print(f'Discovered {len(stems)} movie assets:', ', '.join(stems))
