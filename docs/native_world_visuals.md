# LBA1 native world visuals: integration coverage

The native simulation is the source of truth for all gameplay objects. Godot
must never invent extra collision/pickup/movement behavior.

Implemented in this integration:
- BODY actors via stable BODY.HQR references (existing character renderer)
- Native scene-sprite actors, including moving platforms, from SPRITES.HQR
- Native `ListExtra` sprites including drops, money and collectibles
- Special extras 0/1: hit star and impact burst, positioned from native data
- Speech bubbles 90/91 over native speaker, visible during Godot dialogue
- Sprite bitmap decode cached by original SPRITES.HQR resource ID; no texture
  recreation per frame, including moving scene sprites

Coverage still requiring separate implementation/verification:
- Original shadows, character/brick occlusion and sprite clipping flags
- Damage indicators and other `ListIncrustDisp` screen overlays
- Native-triggered SFX/music/ambient/stop and fade events
- Special extra 2 (fountain) is a no-op even in original `AffSpecial`
- Scene camera framing and original 1994 lighting match
- Replace transitional file-based host with an in-process bridge

Do not mark overall visual/audio integration complete until all original
OBJECT.C, EXTRA.C, INCRUST.C, MESSAGE.C, and audio playback paths have
been audited and checked in playable scenes. Never touch the approved
native SDL audio mastering as a visual integration shortcut.
