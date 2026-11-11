#!/usr/bin/env python3
"""Extract evenly spaced editor frames for EVERY converted movie:* entry."""
import argparse, json, shutil, subprocess, sys, re
from pathlib import Path
from generate_movie_scenes import generate
from sync_original_movies import reconcile


def probe(path: Path):
    out = subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0',
        '-show_entries','stream=width,height:format=duration','-of','json',str(path)],text=True)
    meta=json.loads(out); stream=meta['streams'][0]
    return float(meta.get('format',{}).get('duration') or 0), int(stream['width']), int(stream['height'])


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project', type=Path, default=Path.cwd())
    ap.add_argument('--media-cache', type=Path, required=True)
    ap.add_argument('--frames', type=int, default=32)
    ap.add_argument('--assets', type=Path, help='Original LBA1 data directory containing FLA/')
    ap.add_argument('--sync-originals', action='store_true', help='Convert missing original FLA movies before making previews')
    args=ap.parse_args()
    project=args.project.resolve(); cache=args.media_cache.resolve()
    if not (project/'project.godot').is_file() or not (cache/'manifest.json').is_file():
        ap.error('project.godot or converted media-cache/manifest.json is missing')
    if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
        ap.error('ffmpeg and ffprobe are required')
    available, missing = reconcile(project, cache, args.assets, args.sync_originals)
    stems=generate(project,cache)
    assets=json.loads((cache/'manifest.json').read_text())['assets']
    if missing:
        print('NOTICE: Some original movies are missing. Run with --sync-originals to convert them.', file=sys.stderr)
    for stem in stems:
        if not re.fullmatch('[A-Za-z0-9_-]{1,80}',stem):
            continue
        item = assets.get('movie:' + stem, {})
        src = cache / str(item.get('path', 'movies/' + stem + '.ogv'))
        if not src.is_file():
            print('Skipping missing video', src);continue
        try:
            duration,width,height=probe(src)
            if duration<=0: raise ValueError('no duration')
            dest=project/'assets/editor_previews'/stem
            dest.mkdir(parents=True,exist_ok=True)
            count=max(2,min(120,args.frames))
            for frame in dest.glob('frame_*.jpg'):frame.unlink()
            fps=count/duration
            subprocess.run(['ffmpeg','-hide_banner','-nostdin','-loglevel','error','-y',
                '-i',str(src),'-vf',f'fps={fps:.9f}', '-frames:v',str(count),'-q:v','3',
                str(dest/'temp_%03d.jpg')],check=True)
            frames=sorted(dest.glob('temp_*.jpg'))
            for i,path in enumerate(frames):path.rename(dest/f'frame_{i:03d}.jpg')
            (dest/'preview.json').write_text(json.dumps({'frame_count':len(frames),
                'duration_seconds':duration,'width':width,'height':height,
                'source_aspect':width/height},indent=2)+'\n')
            print(f'{stem}: {len(frames)} frames, {width}x{height}, {duration:.1f}s')
        except (ValueError,subprocess.CalledProcessError,IndexError,KeyError) as exc:
            print('Could not extract',stem,exc,file=sys.stderr)
    print(f'Extracted previews for {len(stems)} converted movie entries.')
    print('Reopen Godot; generated scenes are in scenes/ui/previews/')

if __name__=='__main__':main()
