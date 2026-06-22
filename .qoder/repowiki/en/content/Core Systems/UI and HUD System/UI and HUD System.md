# UI and HUD System

<cite>
**Referenced Files in This Document**
- [HUD_Game.tscn](file://Menu/HUD/HUD_Game.tscn)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [health_bar.gdshader](file://Shaders/HUD/health_bar.gdshader)
- [minimap_overlay.gdshader](file://Shaders/HUD/minimap_overlay.gdshader)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [settings_menu.gd](file://Menu/settings_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [lobby.gd](file://Menu/lobby.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [global_theme.tres](file://Assets/UI/global_theme.tres)
- [Global.tscn](file://Global.tscn)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [translations.csv](file://Locale/translations.csv)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Conclusion](#conclusion)
10. [Appendices](#appendices)

## Introduction
This document describes the UI and HUD system for TFA Agents, focusing on the in-game HUD (health, ammo, minimap, mission panel, subtitles), main menu, settings, pause menu, and game over screens. It explains UI component organization, signal-driven updates, responsive design, minimap rendering and radar effects, theming, localization, and accessibility. It also provides examples of HUD customization, menu navigation, and UI state management.

## Project Structure
The UI system is organized around several scenes and scripts:
- HUD scene and scripts for health, ammo, minimap, mission panel, and subtitles
- Main menu with integrated resource preloading and release checks
- Settings and pause menus
- Game over screen supporting single-player restart and multiplayer spectator modes
- Global settings singleton controlling themes, language, and runtime settings
- Shared theme resource and translation database

```mermaid
graph TB
subgraph "HUD"
HUDScene["HUD_Game.tscn"]
HUDScript["hud_game.gd"]
Minimap["minimap.gd"]
MissionPanel["mission_panel.gd"]
HealthShader["health_bar.gdshader"]
RadarShader["minimap_overlay.gdshader"]
end
subgraph "Menus"
MainMenu["main_menu.gd"]
SettingsMenu["settings_menu.gd"]
PauseMenu["pause_menu.gd"]
GameOver["game_over_menu.gd"]
MultiplayerMenu["multiplayer_menu.gd"]
Lobby["lobby.gd"]
end
subgraph "Global"
GlobalSettings["global_settings.gd"]
GlobalScene["Global.tscn"]
Theme["global_theme.tres"]
Preloader["resource_preloader.gd"]
Translations["translations.csv"]
end
HUDScene --> HUDScript
HUDScript --> Minimap
HUDScript --> MissionPanel
HUDScript --> GlobalSettings
HUDScript --> HealthShader
Minimap --> RadarShader
MainMenu --> Preloader
MainMenu --> GlobalSettings
SettingsMenu --> GlobalSettings
PauseMenu --> GlobalSettings
GameOver --> GlobalSettings
MultiplayerMenu --> GlobalSettings
GlobalScene --> GlobalSettings
GlobalSettings --> Theme
GlobalSettings --> Translations
```

**Diagram sources**
- [HUD_Game.tscn](file://Menu/HUD/HUD_Game.tscn)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [health_bar.gdshader](file://Shaders/HUD/health_bar.gdshader)
- [minimap_overlay.gdshader](file://Shaders/HUD/minimap_overlay.gdshader)
- [main_menu.gd](file://Menu/main_menu.gd)
- [settings_menu.gd](file://Menu/settings_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [lobby.gd](file://Menu/lobby.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [Global.tscn](file://Global.tscn)
- [global_theme.tres](file://Assets/UI/global_theme.tres)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [translations.csv](file://Locale/translations.csv)

**Section sources**
- [HUD_Game.tscn](file://Menu/HUD/HUD_Game.tscn)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [settings_menu.gd](file://Menu/settings_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [lobby.gd](file://Menu/lobby.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [Global.tscn](file://Global.tscn)
- [global_theme.tres](file://Assets/UI/global_theme.tres)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [translations.csv](file://Locale/translations.csv)

## Core Components
- HUD scene and scripts:
  - Health bar with shader-based color and glow effects
  - Ammo display with reload warning animation
  - Minimap with radar overlay and height-filtered entities
  - Mission panel with progress bar or counter, animated states
  - Subtitles overlay controlled by GlobalSettings
- Menus:
  - Main menu with preloading, release checks, and changelog
  - Settings menu with language and graphics presets
  - Pause menu with resume, settings, and main menu transitions
  - Game over screen with restart and spectator modes
  - Multiplayer lobby with chat and ready states
- Global systems:
  - GlobalSettings for theme, language, FPS, subtitles, and graphics presets
  - ResourcePreloader for async scene and shader warm-up
  - Shared theme and translations

**Section sources**
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [settings_menu.gd](file://Menu/settings_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [lobby.gd](file://Menu/lobby.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [global_theme.tres](file://Assets/UI/global_theme.tres)
- [translations.csv](file://Locale/translations.csv)

## Architecture Overview
The UI system relies on:
- Signal-driven updates: HUD subscribes to player signals and GlobalSettings signals
- Quality-aware rendering: shaders and animations activate based on graphics preset
- Centralized settings: GlobalSettings applies theme, language, and runtime effects
- Async resource loading: ResourcePreloader avoids UI freezes during scene transitions
- Localization: CSV-backed translations with dynamic refresh

```mermaid
sequenceDiagram
participant Player as "Player"
participant HUD as "hud_game.gd"
participant GS as "GlobalSettings"
participant GP as "Global.tscn"
participant Theme as "global_theme.tres"
Player->>HUD : "health_changed(current,max)"
HUD->>HUD : "update ProgressBar value"
HUD->>HUD : "set shader parameter health_pct"
Player->>HUD : "ammo_changed(current,total)"
HUD->>HUD : "update ammo labels"
Player->>HUD : "reload_started(duration)"
HUD->>HUD : "flash ammo label color"
GS->>GP : "settings_changed(settings)"
GS->>HUD : "quality_changed(level)"
HUD->>HUD : "emit quality_changed(level)"
GS->>Theme : "apply UI scale and fonts"
GS->>HUD : "subtitle_requested(message,duration)"
HUD->>HUD : "show subtitle panel"
```

**Diagram sources**
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [Global.tscn](file://Global.tscn)
- [global_theme.tres](file://Assets/UI/global_theme.tres)

## Detailed Component Analysis

### HUD Scene and Scripts
- Health bar:
  - Uses a ProgressBar with a ShaderMaterial driven by a shader parameter
  - Color transitions and subtle glow animate based on health percentage
- Ammo display:
  - Current and total labels update on ammo changes
  - Reload events trigger a flashing animation on the current ammo label
- Subtitles:
  - Controlled by GlobalSettings subtitle requests; managed by HUD panel visibility and timer
- Pause button:
  - Emits a parsed input action to open the pause menu
- Quality system:
  - Emits a quality_changed signal to child components (minimap, mission panel)

```mermaid
classDiagram
class HudGame {
+health_bar : ProgressBar
+ammo_current_label : Label
+ammo_total_label : Label
+subtitle_panel : PanelContainer
+pause_btn : Button
+scoreboard_label : Label
+update_scoreboard(text)
+_on_player_health_changed(current,max)
+_on_player_ammo_changed(current,total)
+_on_player_reload_started(duration)
+_on_subtitle_requested(message,duration)
+_on_pause_pressed()
+_apply_quality(level)
}
class Minimap {
+scale_factor : float
+player : Node2D
+_quality_level : int
+_draw()
+_on_settings_changed(new_settings)
}
class MissionPanel {
+style_active : StyleBoxFlat
+style_completed : StyleBoxFlat
+style_failed : StyleBoxFlat
+_ready()
+_on_mission_started(data)
+_on_progress_changed(current,target)
+_on_mission_completed(data)
+_on_mission_failed(data)
+_on_mission_cleared()
+_build_animations()
}
class GlobalSettings {
+apply_settings(changes,persist)
+get_setting(key,fallback)
+settings_changed(settings)
+language_changed(code)
+subtitle_requested(message,duration)
}
HudGame --> Minimap : "uses"
HudGame --> MissionPanel : "receives quality_changed"
HudGame --> GlobalSettings : "subscribes to"
MissionPanel --> GlobalSettings : "subscribes to"
```

**Diagram sources**
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)

**Section sources**
- [HUD_Game.tscn](file://Menu/HUD/HUD_Game.tscn)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [health_bar.gdshader](file://Shaders/HUD/health_bar.gdshader)
- [minimap_overlay.gdshader](file://Shaders/HUD/minimap_overlay.gdshader)

### Minimap Rendering and Radar
- Minimap draws a centered player marker and nearby entities filtered by height level
- Radar overlay shader adds vignetting, grid, sweep, concentric rings, scanlines, and border glow
- Quality level controls whether overlays are drawn and how many details are shown

```mermaid
flowchart TD
Start(["Minimap._draw()"]) --> CheckVisible{"Visible?"}
CheckVisible --> |No| End(["Return"])
CheckVisible --> |Yes| GetSize["Get map size and center"]
GetSize --> DrawBg{"Quality >= 1?"}
DrawBg --> |Yes| DrawBackground["Draw background and border"]
DrawBg --> |No| SkipBg["Skip background"]
DrawBackground --> FindPlayer["Find player node"]
SkipBg --> FindPlayer
FindPlayer --> HasPlayer{"Player found?"}
HasPlayer --> |No| End
HasPlayer --> |Yes| DrawPlayer["Draw player diamond at center"]
DrawPlayer --> GatherEntities["Collect pvp_all_players, team_1, team_2"]
GatherEntities --> FilterByHeight{"Filter by height level"}
FilterByHeight --> DrawEntities["Draw friend/enemy dots"]
DrawEntities --> GatherItems["Collect items"]
GatherItems --> FilterItems{"Quality >= 2 and height filter?"}
FilterItems --> |Yes| DrawItems["Draw item circles"]
FilterItems --> |No| DrawItems
DrawItems --> End
```

**Diagram sources**
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [minimap_overlay.gdshader](file://Shaders/HUD/minimap_overlay.gdshader)

**Section sources**
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [minimap_overlay.gdshader](file://Shaders/HUD/minimap_overlay.gdshader)

### Mission Panel and Progress Tracking
- MissionPanel listens to MissionManager signals and updates label, counter, or progress bar
- Animated states for active, completed, and failed missions
- Shader parameters drive panel and progress bar visuals synchronized with state

```mermaid
sequenceDiagram
participant MM as "MissionManager"
participant MP as "MissionPanel"
participant HUD as "HUD"
participant GS as "GlobalSettings"
MM->>MP : "mission_started(data)"
MP->>MP : "configure labels and counters"
MP->>MP : "play slide_in animation"
MP->>GS : "quality_changed(level)"
MM->>MP : "mission_progress_changed(current,target)"
MP->>MP : "update counter or progress bar"
MM->>MP : "mission_completed(data)"
MP->>MP : "show status 'completed'"
MP->>MP : "play complete_flash"
MM->>MP : "mission_failed(data)"
MP->>MP : "show status 'failed'"
MP->>MP : "play fail_flash"
MM->>MP : "mission_cleared()"
MP->>MP : "play slide_out"
MP->>MP : "hide if no active mission"
```

**Diagram sources**
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)

**Section sources**
- [mission_panel.gd](file://Scripts/mission_panel.gd)

### Main Menu System
- Integrates resource preloading and shader warm-up
- Release checking and changelog display
- Dynamic creation of multiplayer button and localized text refresh
- Overlay for loading progress during scene transitions

```mermaid
sequenceDiagram
participant UI as "main_menu.gd"
participant RP as "ResourcePreloader"
participant GS as "GlobalSettings"
UI->>RP : "preload_resources(PRELOAD_RESOURCES)"
UI->>RP : "preload_shaders(PRELOAD_SHADERS)"
RP-->>UI : "progress_changed(overall)"
UI->>UI : "_update_load_bar(overall)"
UI->>UI : "_on_preload_complete()"
UI->>GS : "request_release_check()"
GS-->>UI : "release_check_completed(info)"
UI->>UI : "_refresh_release_ui()"
UI->>UI : "_maybe_show_startup_changelog()"
```

**Diagram sources**
- [main_menu.gd](file://Menu/main_menu.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)

**Section sources**
- [main_menu.gd](file://Menu/main_menu.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)

### Settings Interface
- Applies settings immediately and emits signals for other systems
- Controls language, UI scale, graphics preset, subtitles, and FPS overlay
- Back navigation returns to the main menu

**Section sources**
- [settings_menu.gd](file://Menu/settings_menu.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [global_theme.tres](file://Assets/UI/global_theme.tres)
- [translations.csv](file://Locale/translations.csv)

### Pause Menu
- Opens and closes via input action or button
- Supports single-player and multiplayer pause modes
- Shows mode label and language-refreshed texts

**Section sources**
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [translations.csv](file://Locale/translations.csv)

### Game Over Screens
- Single-player: restart from checkpoint or beginning, main menu
- Multiplayer: spectator mode cycling through living players, lobby return

**Section sources**
- [game_over_menu.gd](file://Menu/game_over_menu.gd)

### Multiplayer and Lobby
- Host/join flows with team mode selection and ready states
- Chat messaging and lobby updates

**Section sources**
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [lobby.gd](file://Menu/lobby.gd)

## Dependency Analysis
- HUD depends on:
  - Player signals for health/ammo/reload
  - GlobalSettings for quality and subtitles
  - Minimap and MissionPanel for subsystems
- Menus depend on:
  - GlobalSettings for theme, language, and runtime settings
  - ResourcePreloader for seamless scene transitions
- GlobalSettings centralizes:
  - Theme application and UI scaling
  - Language switching and translation refresh
  - Graphics preset application to lights and glows
  - FPS overlay visibility and text updates

```mermaid
graph LR
GS["global_settings.gd"] --> Theme["global_theme.tres"]
GS --> Trans["translations.csv"]
GS --> HUD["hud_game.gd"]
GS --> MP["mission_panel.gd"]
GS --> MM["main_menu.gd"]
GS --> PM["pause_menu.gd"]
GS --> GO["game_over_menu.gd"]
GS --> MMENU["multiplayer_menu.gd"]
HUD --> Minimap["minimap.gd"]
HUD --> HealthShader["health_bar.gdshader"]
Minimap --> RadarShader["minimap_overlay.gdshader"]
MM --> RP["resource_preloader.gd"]
```

**Diagram sources**
- [global_settings.gd](file://Scripts/global_settings.gd)
- [global_theme.tres](file://Assets/UI/global_theme.tres)
- [translations.csv](file://Locale/translations.csv)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [health_bar.gdshader](file://Shaders/HUD/health_bar.gdshader)
- [minimap_overlay.gdshader](file://Shaders/HUD/minimap_overlay.gdshader)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)

**Section sources**
- [global_settings.gd](file://Scripts/global_settings.gd)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [mission_panel.gd](file://Scripts/mission_panel.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)

## Performance Considerations
- Asynchronous resource preloading prevents UI stalls during scene transitions
- Graphics preset reduces shader and lighting complexity for lower tiers
- Minimap drawing is bounded by visibility and simple circle/diamond primitives
- Subtitles and FPS overlays are conditionally shown to reduce overdraw

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
- HUD not updating:
  - Verify player signals are connected and player nodes are in the “players” group
  - Confirm GlobalSettings is emitting settings_changed and quality_changed
- Minimap missing entities:
  - Ensure entities are in the correct groups and share the same height level as the player
- Subtitles not appearing:
  - Check GlobalSettings subtitles setting and subtitle_requested signal emission
- Pause menu not opening:
  - Confirm pause action mapping and that pause menu is not hidden by HUD presence
- Multiplayer lobby issues:
  - Validate port availability and network connectivity; check connection_failed callbacks

**Section sources**
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)

## Conclusion
The UI and HUD system in TFA Agents is modular, signal-driven, and responsive. It integrates health and ammo feedback, a configurable minimap with radar effects, mission progress tracking, and robust menus with localization and settings. GlobalSettings centralizes theming and runtime adjustments, while ResourcePreloader ensures smooth scene transitions. The system scales visually across quality presets and supports both single-player and multiplayer contexts.

[No sources needed since this section summarizes without analyzing specific files]

## Appendices

### UI Theming and Accessibility
- Theme resource defines consistent styles, fonts, and colors across all UI elements
- UI scale adjusts font sizes and constants proportionally
- Language switching updates all labels and subtitles dynamically

**Section sources**
- [global_theme.tres](file://Assets/UI/global_theme.tres)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [translations.csv](file://Locale/translations.csv)

### Localization Workflow
- Translations are stored in CSV and refreshed when language changes
- Menus and HUD labels use translation keys and dynamic refresh

**Section sources**
- [translations.csv](file://Locale/translations.csv)
- [main_menu.gd](file://Menu/main_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)

### Examples Index
- HUD customization:
  - Adjust ProgressBar styles and shader parameters in the HUD scene
  - Modify minimap scale factor and colors in the minimap script
- Menu navigation:
  - Use pause action or pause button to toggle pause menu
  - Navigate from main menu to settings and multiplayer menus
- UI state management:
  - Observe settings_changed and quality_changed signals to synchronize UI elements

**Section sources**
- [HUD_Game.tscn](file://Menu/HUD/HUD_Game.tscn)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [minimap.gd](file://Menu/HUD/minimap.gd)
- [main_menu.gd](file://Menu/main_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [lobby.gd](file://Menu/lobby.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)