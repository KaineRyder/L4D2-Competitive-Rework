## 1. Build the dedicated plugin

- [x] 1.1 Create `tank_practice.sp` as the mode-owned controller, with namespaced commands and explicit map/session state.
- [x] 1.2 Port the GitHub project's hittable and forklift snapshot/reset behavior into the dedicated plugin without retaining the old public command/cvar names.
- [x] 1.3 Implement deterministic Tank spawn/ownership, single-Tank enforcement, configured health, control locking, and failure cleanup.
- [x] 1.4 Implement `!tp` menu, reset, restart, noclip, status, help, and clear success/error feedback.
- [x] 1.5 Add standard SourceMod translations and `tank_practice.cfg` for the new plugin's configurable behavior.

## 2. Replace the match-mode configuration

- [x] 2.1 Rewrite `TankPractice/confogl.cfg` as a standalone versus training configuration for up to four survivors and one manual Tank.
- [x] 2.2 Rewrite `TankPractice/confogl_plugins.cfg` to load only required training dependencies and the dedicated plugin; remove the ZoneMod shared/1v1 chain.
- [x] 2.3 Rewrite `TankPractice/TankPractice.cfg` with training-specific plugin and hittable-control cvars.
- [x] 2.4 Remove the copied 1v1 `mapinfo.txt` and `mapcvars.txt`, and retain only the mode files needed by Confogl.
- [x] 2.5 Keep the existing `TankPractice` entry in `matchmodes.txt` and make no changes to other modes or global configs.

## 3. Validate locally

- [x] 3.1 Compile the dedicated plugin with the repository's SourceMod, Left4DHooks, SDKHooks, BuiltinVotes, and MultiColors includes.
- [x] 3.2 Run static checks for legacy 1v1 references, duplicate command/cvar names, missing paths, and unintended changes outside the TankPractice change surface.
- [x] 3.3 Verify the replacement files and rollback instructions are complete before remote deployment.

## 4. Deploy and verify remotely

- [x] 4.1 Confirm the remote game root and inspect only TankPractice-related target files.
- [x] 4.2 Create a timestamped mode-local backup of the complete old TankPractice directory and legacy TankPractice runtime artifacts.
- [x] 4.3 Remove the old TankPractice contents and legacy runtime plugins, then install the replacement files with the existing ownership and permissions.
- [x] 4.4 Verify remote hashes, plugin load lines, required dependencies, backup contents, and SourceMod error logs.
- [x] 4.5 Leave the live server mode unchanged unless it is safe to reload; document the exact activation and rollback commands.
