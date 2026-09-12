## ADDED Requirements

### Requirement: Standalone TankPractice configuration

The TankPractice match mode SHALL use its own versus configuration and SHALL NOT execute the ZoneMod 1v1 configuration or `zonemod/shared_plugins.cfg`. The mode SHALL retain the existing `TankPractice` match-mode name so existing mode selection continues to work.

#### Scenario: Mode loads without 1v1 rules

- **WHEN** the server loads the `TankPractice` match mode
- **THEN** the mode config sets a four-survivor-capable versus session and does not load 1v1 plugins or 1v1-specific map overrides

#### Scenario: Other modes remain unchanged

- **WHEN** the server loads `zonemod` or another registered mode
- **THEN** that mode continues to use its existing configuration and plugin list

### Requirement: Controlled training population

TankPractice SHALL allow up to four survivors and exactly one active Tank practice slot. The mode SHALL disable random Tank/Witch spawning, all non-Tank special-infected slots, and common-infected pressure by default. The mode SHALL prevent automatic survivor-death checks from ending the practice session.

#### Scenario: Clean practice map

- **WHEN** a TankPractice map starts
- **THEN** survivors can remain in the map while no random Tank, Witch, non-Tank special infected, or common horde is introduced

#### Scenario: Survivor count

- **WHEN** one to four human or bot survivors are present
- **THEN** the mode keeps the configured survivor cap at four and does not apply the old 1v1 survivor limit

### Requirement: Explicit Tank lifecycle

The dedicated plugin SHALL provide namespaced controls to spawn a Tank for the issuing eligible player, apply configured Tank health, prevent more than one active practice Tank, and optionally lock Tank frustration/control. Random director Tank creation SHALL NOT be required for a training session.

#### Scenario: Spawn a practice Tank

- **WHEN** an eligible player invokes the Tank spawn action
- **THEN** the plugin creates or assigns one Tank to that player, applies the configured health, and reports the resulting owner/state

#### Scenario: Duplicate Tank request

- **WHEN** a practice Tank already exists and another Tank spawn action is requested
- **THEN** the plugin removes or replaces the existing practice Tank before creating the new one, leaving at most one active Tank

#### Scenario: Unsupported flow spawn

- **WHEN** a flow-based spawn is requested but the required native or nav data is unavailable
- **THEN** the plugin reports the failure and does not leave a dangling Tank or pending ownership timer

### Requirement: Repeatable hittable reset

The plugin SHALL record eligible Tank-hittable physics entities after map entities are ready, including forklifts when present. A reset SHALL restore tracked entities to their captured transform and physics state, recreate entities that were destroyed when safe, and clear stale entity references.

#### Scenario: Reset an intact hittable

- **WHEN** a Tank moves or rotates a tracked hittable and the player invokes reset
- **THEN** the entity returns to its captured position, angles, velocity, collision, and relevant render state

#### Scenario: Reset a destroyed hittable

- **WHEN** a tracked hittable is destroyed and its model/class can be recreated safely
- **THEN** the plugin recreates it from the captured state and includes it in the next reset cycle

#### Scenario: Forklift behavior

- **WHEN** a map contains a tracked forklift
- **THEN** the plugin records it independently and applies the configured forklift-break/reset policy without corrupting other tracked entities

### Requirement: Training controls and feedback

The plugin SHALL provide a `!tp` menu and namespaced commands for menu access, Tank spawn, full reset, map restart, noclip, Tank-control lock, status, and help. The plugin SHALL provide a clear chat or console result for successful and rejected actions.

#### Scenario: Open the training menu

- **WHEN** a player invokes `!tp`
- **THEN** the plugin displays the current training state and the available actions

#### Scenario: Full reset

- **WHEN** a player invokes the reset action
- **THEN** the plugin ends the active Tank practice, restores configured survivor state, resets tracked hittables, cancels pending timers, and reports the reset count/state

#### Scenario: Map restart fallback

- **WHEN** a player invokes the restart action
- **THEN** the plugin restarts the current map through the server's normal map command and does not alter any other match mode configuration

### Requirement: Safe mode migration and isolation

Deployment SHALL back up the complete old TankPractice surface before removing it. The replacement SHALL install its plugin, source, translation, and cvar config only as TankPractice-owned assets, and SHALL leave `server.cfg`, `hextags.cfg`, ZoneMod files, shared plugin files, and other match modes unchanged.

#### Scenario: Recoverable replacement

- **WHEN** the new mode is deployed
- **THEN** the old TankPractice files and legacy runtime artifacts are present in a timestamped mode-local backup before deletion

#### Scenario: Replacement verification

- **WHEN** deployment verification runs
- **THEN** the new plugin/configuration paths exist, their checksums match the built package, and the old TankPractice load line is absent
