## Why

The current `TankPractice` configuration is a 1v1 ZoneMod derivative rather than a standalone Tank training mode. Its map data and plugin list inherit 1v1 behavior, while the referenced GitHub plugin provides useful hittable-reset utilities but does not manage the full training lifecycle. A clean replacement is needed so Tank practice is predictable, repeatable, and isolated from the other match modes.

## What Changes

- **BREAKING** Remove the existing 1v1-derived `TankPractice` configuration and replace it with a standalone training configuration.
- **BREAKING** Remove the old `l4d2_tank_reset_iron` and upstream `tank_training` runtime plugins from the TankPractice installation after creating a recoverable backup.
- Add a dedicated TankPractice controller plugin based on the GitHub project's hittable/forklift reset logic.
- Support up to four survivors, one manually controlled Tank, no random boss spawning, and no unrelated special-infected or horde pressure.
- Add a namespaced training menu and commands for Tank spawn/control, hittable reset, map restart, noclip, control locking, and status/help.
- Remove the copied 1v1 `mapinfo.txt` and `mapcvars.txt` behavior; use the normal shared map metadata unless TankPractice explicitly adds a future override.
- Keep `server.cfg`, `hextags.cfg`, ZoneMod configuration, shared plugin configuration, and all other match modes unchanged.

## Capabilities

### New Capabilities

- `standalone-tank-practice`: Defines the isolated Tank training mode, its lifecycle, controls, reset behavior, and command surface.

### Modified Capabilities

None.

## Impact

- Affected local and remote files under `cfg/cfgogl/TankPractice/`.
- A new mode-owned SourceMod plugin, translation file, and generated cvar config in the standard SourceMod locations; these are loaded only by TankPractice.
- Existing TankPractice files will be backed up before replacement so the change can be reverted without touching unrelated files.
- The remote server will require a mode reload or map restart before the replacement plugin becomes active.
