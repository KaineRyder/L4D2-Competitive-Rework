## Context

The server uses the Confogl match loader. On the first match load it unloads the current plugin set, executes the configured general fixes, executes the selected mode's `confogl_plugins.cfg`, and then executes the server's shared plugin list. The selected mode's `confogl.cfg` is executed on the match load and on subsequent maps.

The existing `TankPractice` mode is not isolated: its configuration is copied from 1v1 ZoneMod, its `mapinfo.txt` and `mapcvars.txt` are 1v1 data, and its plugin list executes `zonemod/shared_plugins.cfg`. The GitHub `tank_training` plugin has a useful hittable/forklift snapshot-and-restore implementation, but its commands and state handling are a utility layer rather than a complete mode controller.

The replacement must preserve the existing match-mode name and leave all files outside the TankPractice-owned surface unchanged. The remote installation is root-owned, so deployment will use a timestamped backup and privileged file installation. The server must not be forced to change modes while players are using it.

## Goals / Non-Goals

**Goals:**

- Make TankPractice a standalone versus-based training mode for up to four survivors and one human-controlled Tank.
- Remove the 1v1 rules, 1v1 map overrides, ZoneMod shared plugin chain, and legacy TankPractice plugins from this mode.
- Reuse and improve the GitHub project's hittable/forklift state tracking and reset behavior.
- Provide a namespaced, repeatable training control surface with explicit spawn, reset, restart, noclip, lock, status, and help operations.
- Keep the replacement reversible through a mode-local backup and verify the deployed plugin/configuration before activation.

**Non-Goals:**

- Changing `server.cfg`, `generalfixes.cfg`, `sharedplugins.cfg`, `zonemod`, `hextags.cfg`, or any other match mode.
- Adding new maps, Stripper files, custom models, ranking, persistence, or a competitive score system.
- Automatically switching the live server or interrupting a currently active match.
- Supporting arbitrary special-infected training in the first replacement; the mode is Tank-focused.

## Decisions

### 1. Keep the `TankPractice` match-mode name, replace its contents

The existing `matchmodes.txt` entry remains the public entry point. The files in `cfg/cfgogl/TankPractice/` are replaced with a small, standalone set. The old `mapinfo.txt` and `mapcvars.txt` are removed so the mode cannot silently inherit 1v1 map behavior. The normal shared map metadata remains the fallback for plugins that use it.

Alternative considered: create a second match-mode name. Rejected because it would leave the broken mode registered and require changing the mode selector; preserving the name makes the replacement transparent.

### 2. Use a dedicated plugin built from the GitHub reset logic

The new runtime artifact is `tank_practice.smx`, compiled from `tank_practice.sp`. The source will retain the GitHub project's robust hittable/forklift snapshot and recreation concepts, but the public commands and lifecycle state belong to the new plugin. All public commands use a `tp` namespace so they do not collide with legacy commands.

The plugin will expose configuration through `tp_*` cvars and a standard `cfg/sourcemod/tank_practice.cfg`. The old `sm_tankreset_*` cvars and `tank_training.smx` are not part of the new interface.

Alternative considered: load the GitHub plugin beside a new controller plugin. Rejected because both plugins would hook the same Tank/hittable events and would create duplicate state, command collisions, and ambiguous reset ownership.

### 3. Use a small mode-specific plugin set

`TankPractice/confogl_plugins.cfg` will load only the mode's required pieces: ReadyUp, boss-percent support for flow-based spawning, hittable control, and `tank_practice.smx`. It will not execute `cfgogl/zonemod/shared_plugins.cfg` and will not load 1v1 plugins or `l4d_tank_control_eq`.

The server's existing general-fix and shared-plugin execution remains untouched because it is global infrastructure. The mode will only avoid adding the competitive ZoneMod chain and will unload a legacy TankPractice plugin if one is still present during migration.

### 4. Separate mode state from reset state

The controller uses a small state machine:

```text
MapStart -> Preparing -> Ready
Ready -> TankActive
TankActive -> Resetting -> Ready
Ready/TankActive -> MapRestarting -> MapStart
```

On map start it waits until map entities and the Tank-glow pass are available, records eligible hittables, and clears stale references. A reset kills/removes the active Tank, restores or recreates tracked hittables, restores configured survivor state, and clears pending spawn/control timers before returning to `Ready`.

### 5. Make Tank spawning explicit and deterministic

Random Tank and Witch spawning are disabled by the mode. `!tp_tank [soul|flow]` targets the issuing alive player, while the menu exposes the normal and stored-flow spawn paths. If flow spawning is unavailable, the plugin reports the condition and does not silently fall back. The plugin permits only one active Tank and applies the configured health and control-lock behavior after ownership changes.

### 6. Prefer safe repeatability over automatic round transitions

The mode allows four survivors, disables other special infected and common pressure, prevents director death checks from ending a practice session, and leaves map progression under explicit player/admin control. `!tp reset` is the normal loop operation; `!tp restart` is the fallback when a map script or entity cannot be safely recreated.

### 7. Treat deletion as a reversible migration

Before deployment, the complete existing TankPractice directory and every legacy TankPractice runtime file are copied to a timestamped backup under the TankPractice directory. Only after checksum/target checks pass are old files removed and new files installed. The remote server is verified through file hashes, plugin list/info, and SourceMod error logs after the next mode load.

## Risks / Trade-offs

- [The global match loader still executes general and user shared plugins] → Do not modify global files; omit the ZoneMod shared chain from TankPractice and add mode-local unloads only for known legacy conflicts.
- [Tank flow spawning depends on Left4DHooks/boss-percent natives and map nav data] → Check feature status, expose normal spawn as a fallback, and report failures instead of leaving a half-created Tank.
- [Some scripted forklifts cannot be fully recreated at runtime] → Capture all available physics/render/collision state, log failed recreations, and provide `!tp restart` as a deterministic fallback.
- [Legacy plugins may remain loaded until the next match load] → Keep old files out of the new mode load list, remove them during migration, and require a mode reload/map restart before testing.
- [State-changing training commands can disrupt a public server] → Scope them to the TankPractice plugin and expose an access cvar; do not install or enable them in other modes.

## Migration Plan

1. Build the dedicated plugin against the repository's local SourceMod/Left4DHooks includes.
2. Replace the local TankPractice mode files and add the new plugin source/config/translation artifacts.
3. Run compile and static/config checks without modifying unrelated files.
4. On the remote host, create a mode-local backup of the old configuration, old plugin, and previously deployed GitHub plugin files.
5. Remove the old TankPractice directory contents and legacy runtime artifacts, then install the replacement files with the existing root ownership.
6. Verify hashes, required paths, mode load lines, and backup contents.
7. Reload the mode only when the server is safe to restart; otherwise leave the new files staged for the next map/mode change.
8. Roll back by restoring the backup directory and the previous mode load line, then reloading the match mode.

## Open Questions

None for the first replacement. The default profile is one Tank, up to four survivors, manual Tank spawning, no random director pressure, and manual reset.
