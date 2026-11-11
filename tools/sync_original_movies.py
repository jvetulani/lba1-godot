#!/usr/bin/env python3
"""Reconcile original LBA1 FLA movies against the converted media manifest.

Converts only missing/stale FLA entries with the project's original converter;
does not re-import music, voices, samples, tiles, or models.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
from datetime import datetime


def choose_root(project: Path, manifest: dict, override: Path | None) -> Path | None:
    candidates = [override, Path(manifest['source_directory']) if manifest.get('source_directory') else None]
    candidates += [project.parent / 'releases/lba1-linux-x86_64/data',
                   project / 'releases/lba1-linux-x86_64/data']
    for candidate in candidates:
        if candidate is None:
            continue
        candidate = candidate.expanduser().resolve()
        for root in [candidate, candidate / 'Speedrun/Windows']:
            if root.is_dir() and any(p.is_dir() and p.name.casefold() == 'fla' for p in root.iterdir()):
                return root
    return None


def fla_files(root: Path) -> list[Path]:
    folder = next((p for p in root.iterdir() if p.is_dir() and p.name.casefold() == 'fla'), None)
    return sorted((p for p in folder.iterdir() if p.is_file() and p.suffix.casefold() == '.fla'),
                  key=lambda p: p.name.casefold()) if folder else []


def reconcile(project: Path, cache: Path, assets_root: Path | None = None,
              do_convert: bool = False) -> tuple[list[str], list[str]]:
    manifest_path = cache / 'manifest.json'
    if not manifest_path.is_file():
        raise FileNotFoundError(f'Media manifest not found: {manifest_path}')
    manifest = json.loads(manifest_path.read_text())
    if not isinstance(manifest, dict) or not isinstance(manifest.get('assets'), dict):
        raise ValueError('Invalid media-cache manifest')
    entries = manifest['assets']
    originals = choose_root(project, manifest, assets_root)
    cached = {name.removeprefix('movie:') for name, entry in entries.items()
              if name.startswith('movie:') and isinstance(entry, dict)
              and (cache / str(entry.get('path', ''))).is_file()}
    actual_ogv = {p.stem.lower() for p in (cache / 'movies').glob('*.ogv') if p.stat().st_size > 32}
    if originals is None:
        print('Original FLA directory unavailable; checking existing media cache only.')
        return sorted(cached | actual_ogv), []
    originals_list = fla_files(originals)
    source_names = {p.stem.lower() for p in originals_list}
    missing = sorted(source_names - (cached | actual_ogv))
    print(f'Original source: {originals}')
    print(f'Found {len(originals_list)} original FLA movies, {len(cached | actual_ogv)} converted OGV movies.')
    if missing:
        print('Not converted:', ', '.join(missing))
    if do_convert and missing:
        converter = project / 'native/lba1-native/tools/import_modern_media.py'
        if not converter.is_file():
            raise FileNotFoundError(f'Original game converter unavailable: {converter}')
        if not shutil.which('ffmpeg'):
            raise RuntimeError('ffmpeg is required to convert FLA movies')
        sys.path.insert(0, str(converter.parent))
        spec = importlib.util.spec_from_file_location('lba_import_modern_media_for_movies', converter)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        issues: list[str] = []
        # convert_movies validates the original FLA files, uses SHA256 caching,
        # and writes additional movie entries only. Other media stays untouched.
        module.convert_movies(originals, cache, entries, issues, force=False)
        if issues:
            print('Movie conversion warnings:', file=sys.stderr)
            for issue in issues:
                print('  ' + issue, file=sys.stderr)
        # Use an atomic write, retain the original manifest and all unrelated keys.
        backup = manifest_path.with_name('manifest.json.before-movies-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
        shutil.copy2(manifest_path, backup)
        temp = manifest_path.with_name('manifest.json.movies-tmp')
        temp.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        os.replace(temp, manifest_path)
        print('Manifest backup:', backup)
        cached = {name.removeprefix('movie:') for name, entry in entries.items()
                  if name.startswith('movie:') and isinstance(entry, dict)
                  and (cache / str(entry.get('path', ''))).is_file()}
        actual_ogv = {p.stem.lower() for p in (cache / 'movies').glob('*.ogv') if p.stat().st_size > 32}
        missing = sorted(source_names - (cached | actual_ogv))
    if missing:
        print(f'WARNING: {len(missing)} original movies are still missing from converted cache: {", ".join(missing)}', file=sys.stderr)
    return sorted(cached | actual_ogv), missing


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project', type=Path, default=Path.cwd())
    ap.add_argument('--media-cache', type=Path, required=True)
    ap.add_argument('--assets', type=Path, help='Original LBA1 data directory containing FLA/')
    ap.add_argument('--convert', action='store_true', help='Convert missing original movies and update the manifest')
    args = ap.parse_args()
    names, missing = reconcile(args.project.resolve(), args.media_cache.resolve(), args.assets, args.convert)
    print(f'Available movies ({len(names)}):', ', '.join(names))
    if missing: sys.exit(2)


if __name__ == '__main__':
    main()
