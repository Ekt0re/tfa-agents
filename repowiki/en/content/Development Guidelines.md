# Development Guidelines

<cite>
**Referenced Files in This Document**
- [project.godot](file://project.godot)
- [export_presets.cfg](file://export_presets.cfg)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [multiplayer_manager.gd](file://Scripts/multiplayer_manager.gd)
- [player_prototype.gd](file://Scripts/player_prototype.gd)
- [bot_prototype.gd](file://Scripts/bot_prototype.gd)
- [power_up.gd](file://Scripts/power_up.gd)
- [oggetto.gd](file://Scripts/oggetto.gd)
- [input_manager.gd](file://Game/input_manager.gd)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Asset Management Procedures](#asset-management-procedures)
9. [Testing Strategies](#testing-strategies)
10. [Debugging Techniques and Profiling Methods](#debugging-techniques-and-profiling-methods)
11. [Common Pitfalls and How to Avoid Them](#common-pitfalls-and-how-to-avoid-them)
12. [Contribution Workflows](#contribution-workflows)
13. [Documentation Requirements](#documentation-requirements)
14. [Conclusion](#conclusion)

## Introduction
This document provides comprehensive development guidelines for contributors working on TFA Agents. It consolidates code organization standards, naming conventions, file structure guidelines, and best practices for GDScript development within the project. It also covers asset management procedures, performance optimization guidelines, testing strategies, debugging techniques, profiling methods, and common pitfalls to avoid. The goal is to ensure consistent, maintainable, and efficient development across the codebase.

## Project Structure
The project follows a feature-based organization with clear separation of concerns:
- Core engine configuration and autoloads are centralized in the project configuration.
- Scripts are organized under a dedicated folder with clear functional grouping.
- Menus and gameplay scenes are separated into logical directories.
- Assets are categorized by type and purpose, with import metadata alongside assets.
- Addons provide reusable functionality such as mission editing, shader previewing, and virtual joysticks.

```mermaid
graph TB
Project["Project Root"]
Config["project.godot"]
Exports["export_presets.cfg"]
Scripts["Scripts/"]
Menu["Menu/"]
Game["Game/"]
Scenes["Scenes/"]
Assets["Assets/"]
Shaders["Shaders/"]
Addons["addons/"]
Project --> Config
Project --> Exports
Project --> Scripts
Project --> Menu
Project --> Game
Project --> Scenes
Project --> Assets
Project --> Shaders
Project --> Addons
Scripts --> GlobalSettings["global_settings.gd"]
Scripts --> Preloader["resource_preloader.gd"]
Scripts --> MultiplayerMgr["multiplayer_manager.gd"]
Scripts --> PlayerProto["player_prototype.gd"]
Scripts --> BotProto["bot_prototype.gd"]
Scripts --> PowerUp["power_up.gd"]
Scripts --> Obj["oggetto.gd"]
Menu --> MainMenu["main_menu.gd"]
Game --> InputMgr["input_manager.gd"]
```

**Diagram sources**
- [project.godot](file://project.godot)
- [export_presets.cfg](file://export_presets.cfg)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [multiplayer_manager.gd](file://Scripts/multiplayer_manager.gd)
- [player_prototype.gd](file://Scripts/player_prototype.gd)
- [bot_prototype.gd](file://Scripts/bot_prototype.gd)
- [power_up.gd](file://Scripts/power_up.gd)
- [oggetto.gd](file://Scripts/oggetto.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [input_manager.gd](file://Game/input_manager.gd)

**Section sources**
- [project.godot](file://project.godot)
- [export_presets.cfg](file://export_presets.cfg)

## Core Components
This section outlines the primary systems and their responsibilities:
- Global Settings: Centralized settings management, graphics presets, audio bus control, FPS overlay, and release checking.
- Resource Preloader: Background loading of scenes and shader warm-up to reduce initial load times.
- Main Menu: Scene transitions, integrated release checks, changelog display, and preloading orchestration.
- Multiplayer Manager: Host/client lifecycle, lobby management, team assignment, and synchronized game start.
- Player Prototype: Movement, shooting, height-level transitions, camera effects, and multiplayer synchronization.
- Bot Prototype: AI-driven navigation, pathfinding across height levels, ramp traversal, and targeting.
- Power Up: Collectible items with level-aware visibility and effects.
- Generic Object: Destructible crates/barrels with explosion mechanics and level-aware visibility.

**Section sources**
- [global_settings.gd](file://Scripts/global_settings.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [multiplayer_manager.gd](file://Scripts/multiplayer_manager.gd)
- [player_prototype.gd](file://Scripts/player_prototype.gd)
- [bot_prototype.gd](file://Scripts/bot_prototype.gd)
- [power_up.gd](file://Scripts/power_up.gd)
- [oggetto.gd](file://Scripts/oggetto.gd)

## Architecture Overview
The system relies on autoload singletons for cross-scene coordination and a modular script architecture:
- Autoloads manage global state and services (settings, events, resource preloading, multiplayer).
- Scenes communicate via signals and shared nodes to minimize tight coupling.
- Multiplayer logic is encapsulated in dedicated managers with RPC calls for authoritative actions.
- Level-aware systems use groups and shader materials to enforce visibility and effects.

```mermaid
graph TB
subgraph "Autoloads"
GS["GlobalSettings"]
RE["ResourcePreloader"]
ME["MultiplayerManager"]
GE["GameEvents"]
end
subgraph "UI"
MM["MainMenu"]
end
subgraph "Gameplay"
PP["PlayerPrototype"]
BP["BotPrototype"]
PU["PowerUp"]
OBJ["Oggetto"]
end
MM --> RE
MM --> GS
MM --> ME
PP --> GS
PP --> ME
BP --> GS
PU --> GS
OBJ --> GS
GE --> PP
```

**Diagram sources**
- [project.godot](file://project.godot)
- [main_menu.gd](file://Menu/main_menu.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [multiplayer_manager.gd](file://Scripts/multiplayer_manager.gd)
- [player_prototype.gd](file://Scripts/player_prototype.gd)
- [bot_prototype.gd](file://Scripts/bot_prototype.gd)
- [power_up.gd](file://Scripts/power_up.gd)
- [oggetto.gd](file://Scripts/oggetto.gd)

## Detailed Component Analysis

### Global Settings
Responsibilities:
- Persist and apply user settings (volume, window mode, vsync, FPS cap, graphics preset, UI scale, language).
- Manage release checks via HTTP client and threading.
- Provide localized subtitles and FPS overlay.
- Apply graphics presets to nodes dynamically.

Best practices:
- Sanitize inputs against supported options and clamp ranges.
- Use threads for network operations and defer UI updates.
- Cache theme baseline values to efficiently scale fonts and constants.

```mermaid
classDiagram
class GlobalSettings {
+Dictionary settings
+Dictionary meta
+Dictionary release_info
+get_settings() Dictionary
+apply_settings(changes, persist) void
+request_release_check(force) void
+text(key, args) String
+show_subtitle(message, duration) void
}
```

**Diagram sources**
- [global_settings.gd](file://Scripts/global_settings.gd)

**Section sources**
- [global_settings.gd](file://Scripts/global_settings.gd)

### Resource Preloader
Responsibilities:
- Asynchronously load scenes and compile shaders to warm GPU caches.
- Track progress and emit completion signals.
- Change scenes when resources are ready without blocking the main thread.

Best practices:
- Load only top-level scenes; rely on Godot’s internal dependency loading.
- Avoid polling in _process; use minimal polling loop and emit progress deltas.
- Prefer change_scene_to_packed for cached scenes to avoid disk reads.

```mermaid
sequenceDiagram
participant UI as "MainMenu"
participant RP as "ResourcePreloader"
participant Tree as "SceneTree"
UI->>RP : preload_resources(paths)
UI->>RP : preload_shaders(paths)
RP->>RP : poll_pending()
RP-->>UI : progress_changed(overall)
RP-->>UI : all_loaded()
UI->>RP : change_scene_when_ready(path)
alt done
RP->>Tree : change_scene_to_packed(scene)
else not done
RP->>RP : store pending path
end
```

**Diagram sources**
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [main_menu.gd](file://Menu/main_menu.gd)

**Section sources**
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [main_menu.gd](file://Menu/main_menu.gd)

### Main Menu
Responsibilities:
- Orchestrate preloading and scene transitions.
- Integrate release checks and changelog display.
- Dynamically build overlays and handle input.

Best practices:
- Connect signals before starting preload to avoid missing progress updates.
- Use dynamic overlay creation sparingly; prefer scene-based overlays for performance.
- Keep UI text updates localized and reactive to language changes.

```mermaid
flowchart TD
Start(["Menu Ready"]) --> InitPreload["Connect Signals<br/>Start Preload"]
InitPreload --> Preloading{"Preload Done?"}
Preloading --> |No| ShowOverlay["Show Loading Overlay"]
Preloading --> |Yes| HideOverlay["Hide Overlay"]
ShowOverlay --> Wait["Wait for Completion"]
Wait --> Preloading
HideOverlay --> Choose{"Play Requested?"}
Choose --> |Yes| ChangeScene["Change Scene When Ready"]
Choose --> |No| Idle["Idle"]
```

**Diagram sources**
- [main_menu.gd](file://Menu/main_menu.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)

**Section sources**
- [main_menu.gd](file://Menu/main_menu.gd)

### Multiplayer Manager
Responsibilities:
- Host and join sessions, manage lobby state, and synchronize game start.
- Assign teams and broadcast updates to clients.
- Handle connection lifecycle and graceful disconnections.

Best practices:
- Normalize dictionary keys after RPC serialization to integers.
- Use authority-based RPCs for server-side authoritative actions.
- Keep lobby state consistent by broadcasting updates.

```mermaid
sequenceDiagram
participant Host as "Host"
participant Client as "Client"
participant MP as "MultiplayerManager"
participant Tree as "SceneTree"
Host->>MP : host_game(port, max_players)
Client->>MP : join_game(ip, port)
MP-->>Client : connected_to_server
Client->>MP : register_player_on_server(name, skin)
MP-->>All : broadcast_lobby_update(players_info)
Host->>MP : start_game()
MP-->>All : start_game_on_all(map_path, players_info, team_mode, team_count)
MP->>Tree : change_scene_to_file(map_path)
```

**Diagram sources**
- [multiplayer_manager.gd](file://Scripts/multiplayer_manager.gd)

**Section sources**
- [multiplayer_manager.gd](file://Scripts/multiplayer_manager.gd)

### Player Prototype
Responsibilities:
- Movement, aiming, shooting, reloading, and height-level transitions.
- Camera shake, nicknames, and multiplayer synchronization.
- Shader-based level effects and visibility.

Best practices:
- Limit sync frequency to reduce bandwidth and CPU overhead.
- Use raycasts for precise hit detection and level-aware collisions.
- Apply authority checks before applying feedback or modifying state.

```mermaid
flowchart TD
Input["Input Events"] --> Move["Update Velocity"]
Input --> Aim["Aim Direction"]
Input --> Fire{"Can Fire?"}
Fire --> |Yes| Shoot["Fire Projectile"]
Fire --> |No| ReloadCheck{"Ammo Empty?"}
ReloadCheck --> |Yes| Reload["Reload"]
ReloadCheck --> |No| Idle["Idle"]
Move --> Sync["Sync State (periodic)"]
Aim --> Sync
Shoot --> Effects["Screen Shake & Subtitles"]
Sync --> Network["RPC to Remotes"]
```

**Diagram sources**
- [player_prototype.gd](file://Scripts/player_prototype.gd)

**Section sources**
- [player_prototype.gd](file://Scripts/player_prototype.gd)

### Bot Prototype
Responsibilities:
- Pathfinding across height levels with ramps.
- Target tracking and smooth movement/rotation.
- Debug visualization of routes.

Best practices:
- Cache navigation regions per level to avoid repeated lookups.
- Use incremental route refresh on level changes to keep agents synchronized.
- Keep smoothing parameters tuned for responsiveness without overshooting.

```mermaid
flowchart TD
Start(["Bot Ready"]) --> Target["Resolve Target Position/Layer"]
Target --> Route["Build Best Route (Direct or Via Ramps)"]
Route --> Steps{"Steps Available?"}
Steps --> |Yes| NextStep["Advance to Next Step"]
Steps --> |No| Idle["Idle"]
NextStep --> Move["Move Along Path"]
Move --> Rotate["Rotate Towards Target"]
Rotate --> Debug["Update Debug Line"]
Debug --> Loop["Loop"]
```

**Diagram sources**
- [bot_prototype.gd](file://Scripts/bot_prototype.gd)

**Section sources**
- [bot_prototype.gd](file://Scripts/bot_prototype.gd)

### Power Up
Responsibilities:
- Level-aware visibility and collision masks.
- Authority-based effect application and subtitle notifications.
- Dynamic shader glow and light effects.

Best practices:
- Use groups to categorize items and simplify filtering.
- Apply quality-dependent visuals to balance performance and fidelity.
- Emit global events only from authority to prevent duplication.

```mermaid
sequenceDiagram
participant Player as "PlayerPrototype"
participant Item as "PowerUp"
participant GS as "GlobalSettings"
participant Tree as "SceneTree"
Player->>Item : area_entered(body)
alt Local Authority
Item->>GS : show_subtitle(text)
Item->>Player : apply_effect()
end
Item-->>Tree : queue_free()
```

**Diagram sources**
- [power_up.gd](file://Scripts/power_up.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)

**Section sources**
- [power_up.gd](file://Scripts/power_up.gd)

### Generic Object (Destructible)
Responsibilities:
- Health-based destruction and explosion mechanics.
- Level-aware collision masks and visibility.
- Particle and animation-based explosion effects.

Best practices:
- Server-authoritative destruction to prevent client-side manipulation.
- Scale particle effects with explosion radius and graphics preset.
- Disable collision after destruction to avoid further interactions.

```mermaid
flowchart TD
Damage["apply_damage(amount)"] --> Sync["Sync Health (RPC)"]
Sync --> Check{"Health <= 0?"}
Check --> |No| Update["Update Crack Shader"]
Check --> |Yes| Explode["Replicate Destroy (RPC)"]
Explode --> Server{"Server?"}
Server --> |Yes| Iterate["Iterate Damageable Targets"]
Iterate --> Radius["Within Explosion Radius?"]
Radius --> |Yes| Apply["Apply Falloff Damage"]
Radius --> |No| Skip["Skip"]
Apply --> Cleanup["Disable Collisions & Free"]
Skip --> Cleanup
```

**Diagram sources**
- [oggetto.gd](file://Scripts/oggetto.gd)

**Section sources**
- [oggetto.gd](file://Scripts/oggetto.gd)

## Dependency Analysis
Key dependencies and relationships:
- Autoloads: GlobalSettings, ResourcePreloader, MultiplayerManager, GameEvents are declared in the project configuration and used across scenes.
- UI and Gameplay: Main menu depends on ResourcePreloader and GlobalSettings; gameplay scripts depend on GlobalSettings for subtitles and camera shake.
- Multiplayer: PlayerPrototype and bots coordinate via MultiplayerManager; authoritative actions are enforced via RPCs.
- Level Systems: PlayerPrototype, bots, power-ups, and destructibles use groups and shader materials to enforce level-aware behavior.

```mermaid
graph TB
GS["GlobalSettings"] --> PP["PlayerPrototype"]
GS --> BP["BotPrototype"]
GS --> PU["PowerUp"]
GS --> OBJ["Oggetto"]
RE["ResourcePreloader"] --> MM["MainMenu"]
RE --> MM
ME["MultiplayerManager"] --> PP
ME --> BP
GE["GameEvents"] --> PP
```

**Diagram sources**
- [project.godot](file://project.godot)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [multiplayer_manager.gd](file://Scripts/multiplayer_manager.gd)
- [player_prototype.gd](file://Scripts/player_prototype.gd)
- [bot_prototype.gd](file://Scripts/bot_prototype.gd)
- [power_up.gd](file://Scripts/power_up.gd)
- [oggetto.gd](file://Scripts/oggetto.gd)

**Section sources**
- [project.godot](file://project.godot)

## Performance Considerations
- Use ResourcePreloader for asynchronous scene and shader warm-up to avoid frame drops.
- Limit multiplayer sync frequency (e.g., every N physics frames) to reduce bandwidth and CPU usage.
- Prefer change_scene_to_packed for cached scenes to bypass disk reads.
- Clamp shader parameter updates and disable expensive effects at lower graphics presets.
- Use groups and layered collision masks to minimize unnecessary collision checks.
- Avoid heavy computations in _process; prefer _physics_process for movement and timing-sensitive logic.
- Disable debug overlays and verbose logging in release builds.

## Asset Management Procedures
- Place assets under appropriate categories (Animation, Audio, Lighting, UI, Weapons, etc.) with import metadata.
- Keep import files (.import) alongside assets to preserve platform-specific settings.
- Use theme resources for UI scaling and font sizing; GlobalSettings caches baseline values for responsive scaling.
- Organize tilesets and sheets with clear naming conventions and consistent cell sizes.
- For shaders, preload and warm-up via ResourcePreloader to reduce first-use latency.

## Testing Strategies
- Unit-like tests for individual systems:
  - PlayerPrototype: movement, firing, reloading, level transitions, and multiplayer sync.
  - BotPrototype: pathfinding accuracy, ramp traversal, and target tracking.
  - PowerUp: collection triggers, authority checks, and effect application.
  - Generic Object: explosion radius, damage falloff, and particle scaling.
- Integration tests:
  - MultiplayerManager: host/join flows, lobby updates, and game start synchronization.
  - ResourcePreloader: progress reporting and scene switching readiness.
- Manual QA:
  - Verify level-aware visibility and collision masks across height levels.
  - Test release check flow and changelog display in Main Menu.
  - Validate input handling on desktop and mobile (virtual joystick).

## Debugging Techniques and Profiling Methods
- Use print statements strategically and avoid excessive logging in production.
- Utilize Godot’s built-in profiler to identify hotspots in scripts and rendering.
- For multiplayer issues, verify authority checks and RPC sequences.
- Inspect shader parameters and material assignments for level effects.
- Monitor FPS overlay and audio bus volumes controlled by GlobalSettings.

## Common Pitfalls and How to Avoid Them
- Avoid blocking the main thread: use ResourcePreloader and threaded loading APIs.
- Do not assume RPC dictionaries retain integer keys; normalize keys after deserialization.
- Prevent friendly fire by checking team IDs before applying damage.
- Ensure level-aware systems update groups and collision masks consistently.
- Do not modify state on non-authority instances; delegate to server or local authority.

## Contribution Workflows
- Branching: Use feature branches for new features and bug fixes.
- Commits: Keep commits small and focused; include clear messages referencing issues.
- Code review: Review scripts for adherence to naming conventions, performance, and multiplayer correctness.
- Testing: Run manual QA across platforms and include automated checks for core systems.
- Documentation: Update relevant documentation and inline comments for new features.

## Documentation Requirements
- Inline comments: Document exported variables, complex logic, and multiplayer considerations.
- Public APIs: Add function-level documentation for scripts intended for reuse.
- Architecture decisions: Record rationale for autoload usage, level systems, and multiplayer design choices.
- Release notes: Maintain changelogs and integrate with GlobalSettings’ release check flow.

## Conclusion
These guidelines establish a consistent foundation for developing TFA Agents. By adhering to the outlined standards—code organization, naming conventions, performance optimization, asset management, testing, and debugging—you contribute to a maintainable, scalable, and enjoyable codebase. Follow the workflows and documentation requirements to ensure smooth collaboration and high-quality releases.