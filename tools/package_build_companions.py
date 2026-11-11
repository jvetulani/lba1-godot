#!/usr/bin/env python3
"""Copy LBA1 import tools and GeneralUser SoundFont beside an exported executable.

Used for headless/CI exports (the Godot editor plugin handles GUI exports).
Usage: python3 tools/package_build_companions.py /path/to/exported/game.x86_64
"""
from pathlib import Path
import argparse, shutil, sys


def package(project: Path, executable: Path) -> Path:
    if not executable.is_file():
        raise FileNotFoundError(f"Exported executable not found: {executable}")
    tools = project / 'native/lba1-native/tools'
    sf = project / 'native/lba1-native/soundfonts/GeneralUser-GS.sf2'
    if not sf.is_file():
        raise FileNotFoundError(f"Required SoundFont missing: {sf}")
    launch = tools / 'run_first_time.py'
    stage = tools / 'stage_native_assets.py'
    if not launch.is_file() or not stage.is_file():
        raise FileNotFoundError(f"Required importer scripts missing from: {tools}")
    target = executable.resolve().parent / 'lba1-native'
    (target / 'soundfonts').mkdir(parents=True, exist_ok=True)
    (target / 'tools').mkdir(parents=True, exist_ok=True)
    shutil.copy2(sf, target / 'soundfonts' / sf.name)
    for script in tools.glob('*.py'):
        shutil.copy2(script, target / 'tools' / script.name)
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    args = parser.parse_args()
    try:
        target = package(Path(__file__).resolve().parent.parent, args.executable)
    except (OSError, FileNotFoundError) as exc:
        print(f'Build companion copy failed: {exc}', file=sys.stderr)
        return 1
    print(f'LBA build companion assets ready at {target}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
