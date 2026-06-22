# Main Menu API

<cite>
**Referenced Files in This Document**
- [main_menu.gd](file://Menu/main_menu.gd)
- [main_menu.tscn](file://Menu/main_menu.tscn)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [settings_menu.gd](file://Menu/settings_menu.gd)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [global_settings.gd](file://Scripts/global_settings.gd)
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

## Introduction
This document provides comprehensive API documentation for the main menu system, covering navigation, button events, scene transitions, initialization, user interaction handlers, state management, persistence, user preferences integration, and accessibility features. The main menu serves as the primary entry point for launching single-player gameplay, accessing settings, and navigating to multiplayer functionality.

## Project Structure
The main menu system consists of the following key components:
- Main Menu Script: Handles initialization, button events, scene transitions, and integration with global settings and resource preloading.
- Main Menu Scene: Defines the UI layout and nodes used by the main menu script.
- Multiplayer Menu: Provides host/join functionality and integrates with the multiplayer manager.
- Settings Menu: Manages settings panel navigation and back transitions.
- Pause Menu: Controls pause functionality and integrates with the main menu.
- Global Settings: Centralized settings management with persistence, language support, and release update checks.

```mermaid
graph TB
MainMenu["Main Menu<br/>main_menu.gd"] --> GlobalSettings["Global Settings<br/>global_settings.gd"]
MainMenu --> Preloader["Resource Preloader<br/>(autoload)"]
MainMenu --> SettingsOverlay["Settings Overlay<br/>visible via settings_menu.gd"]
MainMenu --> ChangelogOverlay["Changelog Overlay<br/>visible on startup"]
MainMenu --> ReleaseBanner["Release Banner<br/>GitHub updates"]
MainMenu --> LoadOverlay["Load Overlay<br/>preloading feedback"]
MultiplayerMenu["Multiplayer Menu<br/>multiplayer_menu.gd"] --> GlobalSettings
MultiplayerMenu --> MPManager["Multiplayer Manager<br/>(autoload)"]
SettingsMenu["Settings Menu<br/>settings_menu.gd"] --> GlobalSettings
PauseMenu["Pause Menu<br/>pause_menu.gd"] --> GlobalSettings
GlobalSettings --> SettingsCFG["settings.cfg<br/>user://settings.cfg"]
GlobalSettings --> ThemeResource["global_theme.tres"]
```

**Diagram sources**
- [main_menu.gd:1-416](file://Menu/main_menu.gd#L1-L416)
- [multiplayer_menu.gd:1-121](file://Menu/multiplayer_menu.gd#L1-L121)
- [settings_menu.gd:1-20](file://Menu/settings_menu.gd#L1-L20)
- [pause_menu.gd:1-143](file://Menu/pause_menu.gd#L1-L143)
- [global_settings.gd:1-618](file://Scripts/global_settings.gd#L1-L618)

**Section sources**
- [main_menu.gd:1-416](file://Menu/main_menu.gd#L1-L416)
- [main_menu.tscn:1-324](file://Menu/main_menu.tscn#L1-L324)

## Core Components
The main menu system comprises several interconnected components that handle different aspects of menu functionality:

### Main Menu Controller
The main menu script extends Control and manages:
- Initialization and UI setup
- Button event handling
- Scene transitions
- Resource preloading integration
- Release update notifications
- Language and accessibility support

### Multiplayer Menu
Handles network-based gameplay with:
- Host creation functionality
- Join functionality
- Player name management
- Team mode configuration

### Settings Management
Provides centralized settings handling through:
- Persistent configuration storage
- Language switching
- Graphics preset application
- Volume and UI scaling controls

### Pause Menu Integration
Manages pause functionality that integrates with:
- Single-player vs multiplayer modes
- HUD presence detection
- Settings panel navigation

**Section sources**
- [main_menu.gd:1-416](file://Menu/main_menu.gd#L1-L416)
- [multiplayer_menu.gd:1-121](file://Menu/multiplayer_menu.gd#L1-L121)
- [settings_menu.gd:1-20](file://Menu/settings_menu.gd#L1-L20)
- [pause_menu.gd:1-143](file://Menu/pause_menu.gd#L1-L143)
- [global_settings.gd:1-618](file://Scripts/global_settings.gd#L1-L618)

## Architecture Overview
The main menu system follows a modular architecture with clear separation of concerns:

```mermaid
classDiagram
class MainMenu {
+Signal play_requested
+Signal exit_requested
+String play_scene_path
+Array PRELOAD_RESOURCES
+Array PRELOAD_SHADERS
+void _ready()
+void _on_play_pressed()
+void _on_settings_pressed()
+void _on_exit_pressed()
+void _on_multiplayer_pressed()
+void _build_load_overlay()
+void _hide_load_overlay()
}
class GlobalSettings {
+Dictionary settings
+Dictionary meta
+Dictionary release_info
+String SETTINGS_PATH
+void apply_settings(changes, persist)
+void set_meta_value(key, value, persist)
+void request_release_check(force)
+String get_current_version()
}
class MultiplayerMenu {
+LineEdit _player_name_field
+LineEdit _host_port_field
+LineEdit _join_ip_field
+Button _create_button
+Button _join_button
+void _ready()
+void _on_create_button_pressed()
+void _on_join_button_pressed()
+void _on_back_button_pressed()
}
class SettingsMenu {
+String back_scene_path
+void _ready()
+void _on_back_requested()
}
class PauseMenu {
+String pause_action
+bool freeze_game_on_pause
+bool _menu_is_open
+void _open_pause_menu()
+void _close_pause_menu()
+void _on_resume_pressed()
+void _on_main_menu_pressed()
}
MainMenu --> GlobalSettings : "uses"
MultiplayerMenu --> GlobalSettings : "uses"
SettingsMenu --> GlobalSettings : "uses"
PauseMenu --> GlobalSettings : "uses"
MainMenu --> MultiplayerMenu : "navigates to"
MainMenu --> SettingsMenu : "navigates to"
PauseMenu --> MainMenu : "returns to"
```

**Diagram sources**
- [main_menu.gd:1-416](file://Menu/main_menu.gd#L1-L416)
- [global_settings.gd:1-618](file://Scripts/global_settings.gd#L1-L618)
- [multiplayer_menu.gd:1-121](file://Menu/multiplayer_menu.gd#L1-L121)
- [settings_menu.gd:1-20](file://Menu/settings_menu.gd#L1-L20)
- [pause_menu.gd:1-143](file://Menu/pause_menu.gd#L1-L143)

## Detailed Component Analysis

### Main Menu Component Analysis

#### Initialization and Setup
The main menu initializes through the `_ready()` method, which handles:
- UI element binding and configuration
- Language change signal connections
- Release check initialization
- Dynamic button creation for multiplayer functionality
- Resource preloading integration

```mermaid
sequenceDiagram
participant Scene as "Main Menu Scene"
participant Script as "main_menu.gd"
participant Settings as "GlobalSettings"
participant Preloader as "ResourcePreloader"
Scene->>Script : _ready()
Script->>Script : process_mode = ALWAYS
Script->>Script : hide overlays
Script->>Settings : connect language_changed
Script->>Settings : connect release_check_completed
Script->>Settings : connect update_status_changed
alt release_info.status == "idle"
Script->>Settings : request_release_check()
else
Script->>Script : _on_release_check_completed()
end
Script->>Script : create dynamic MultiplayerButton
Script->>Preloader : connect progress_changed
Script->>Preloader : connect all_loaded
Script->>Preloader : preload_resources()
Script->>Script : _build_load_overlay() if needed
```

**Diagram sources**
- [main_menu.gd:56-106](file://Menu/main_menu.gd#L56-L106)
- [global_settings.gd:192-224](file://Scripts/global_settings.gd#L192-L224)

#### Button Event Handlers
The main menu provides comprehensive button event handling:

```mermaid
flowchart TD
Start([Button Pressed]) --> CheckType{"Which Button?"}
CheckType --> |Play| PlayHandler["Play Handler"]
CheckType --> |Multiplayer| MPHandler["Multiplayer Handler"]
CheckType --> |Settings| SettingsHandler["Settings Handler"]
CheckType --> |Exit| ExitHandler["Exit Handler"]
PlayHandler --> ClearCheckpoint["Clear Mission Checkpoint Data"]
ClearCheckpoint --> CheckPreloader{"Preloader Done?"}
CheckPreloader --> |No| ShowOverlay["Show Load Overlay"]
CheckPreloader --> |Yes| ChangeScene["Change Scene Immediately"]
ShowOverlay --> WaitPreload["Wait for Preloader"]
WaitPreload --> ChangeScene
MPHandler --> ChangeMP["Change to Multiplayer Menu"]
SettingsHandler --> ShowSettings["Show Settings Overlay"]
ExitHandler --> QuitGame["Quit Game"]
ChangeScene --> End([Transition Complete])
ChangeMP --> End
ShowSettings --> End
QuitGame --> End
```

**Diagram sources**
- [main_menu.gd:119-154](file://Menu/main_menu.gd#L119-L154)

#### Scene Transition Management
The main menu handles various scene transitions:
- Single-player game launch with resource preloading
- Multiplayer menu navigation
- Settings panel integration
- Exit to desktop

#### State Management
Key state management features include:
- Dynamic button creation and configuration
- Visibility state management for overlays
- Progress tracking during resource preloading
- Release update state handling

**Section sources**
- [main_menu.gd:56-154](file://Menu/main_menu.gd#L56-L154)

### Multiplayer Menu Component Analysis

#### Host Creation Functionality
The multiplayer menu provides comprehensive host creation capabilities:
- Port configuration with validation
- Maximum player count adjustment
- Team mode selection (teams vs FFA)
- Team count configuration for team mode

#### Join Functionality
Network joining features include:
- IP address validation
- Port configuration with defaults
- Connection status reporting
- Error handling for connection failures

#### Player Name Management
Player name persistence and management:
- Loading saved player names from global settings
- Default name assignment
- Real-time name updates to multiplayer manager

**Section sources**
- [multiplayer_menu.gd:22-121](file://Menu/multiplayer_menu.gd#L22-L121)

### Settings Management Component Analysis

#### Persistence Layer
Settings persistence through the GlobalSettings system:
- Configuration file storage (user://settings.cfg)
- Default value management
- Type-safe setting retrieval and modification
- Automatic serialization/deserialization

#### Language Support
Comprehensive internationalization:
- Supported language codes (Italian, English)
- Runtime language switching
- Translation key system
- Theme font size adaptation

#### Release Update Integration
Automated release checking:
- GitHub API integration
- Version comparison logic
- Update notification system
- Download progress tracking

**Section sources**
- [global_settings.gd:8-618](file://Scripts/global_settings.gd#L8-L618)

### Pause Menu Integration

#### Mode Detection
Intelligent mode detection:
- Single-player vs multiplayer differentiation
- HUD presence detection
- Automatic pause button visibility management

#### Settings Panel Navigation
Integrated settings management:
- Settings panel visibility control
- Back navigation handling
- Settings persistence during pause

**Section sources**
- [pause_menu.gd:28-143](file://Menu/pause_menu.gd#L28-L143)

## Dependency Analysis

```mermaid
graph LR
subgraph "Main Menu Dependencies"
MM[main_menu.gd] --> GS[global_settings.gd]
MM --> RP[ResourcePreloader]
MM --> SM[settings_menu.gd]
MM --> PM[multiplayer_menu.gd]
end
subgraph "Settings System"
GS --> CFG[settings.cfg]
GS --> TR[Translations]
GS --> TH[Theme Resources]
end
subgraph "External Systems"
GS --> GH[GitHub API]
GS --> AS[AudioServer]
GS --> DS[DisplayServer]
GS --> OSN[OS]
end
subgraph "UI Components"
MM --> UI[main_menu.tscn]
SM --> SP[settings_panel.tscn]
PM --> LO[lobby.tscn]
end
```

**Diagram sources**
- [main_menu.gd:23-25](file://Menu/main_menu.gd#L23-L25)
- [global_settings.gd:8-79](file://Scripts/global_settings.gd#L8-L79)
- [main_menu.tscn:1-324](file://Menu/main_menu.tscn#L1-L324)

### Component Coupling
The main menu system demonstrates appropriate separation of concerns:
- Loose coupling between UI and logic through exported signals
- Clear dependency injection for external systems
- Modular design enabling easy testing and maintenance

### Circular Dependencies
No circular dependencies detected in the main menu system architecture.

**Section sources**
- [main_menu.gd:1-416](file://Menu/main_menu.gd#L1-L416)
- [global_settings.gd:1-618](file://Scripts/global_settings.gd#L1-L618)

## Performance Considerations

### Resource Preloading Strategy
The main menu implements efficient resource preloading:
- Background loading of scenes and shaders
- Progress indication overlay
- Conditional loading based on completion status
- Memory-efficient resource management

### UI Responsiveness
Performance optimizations include:
- Deferred UI updates using call_deferred
- Throttled FPS counter updates
- Efficient theme application
- Minimal garbage collection during runtime

### Network Operations
Multiplayer menu performance considerations:
- Non-blocking connection attempts
- Graceful error handling
- Connection timeout management
- Resource cleanup on failure

## Troubleshooting Guide

### Common Issues and Solutions

#### Menu Not Responding to Input
- Verify `_unhandled_input` method is properly connected
- Check `process_mode` is set to `PROCESS_MODE_ALWAYS`
- Ensure nodes are properly bound in `_ready()`

#### Scene Transition Failures
- Validate scene file paths exist
- Check resource preloader completion status
- Verify autoload nodes are available

#### Settings Not Persisting
- Confirm settings.cfg file write permissions
- Check `_save_config()` method execution
- Verify settings dictionary keys match defaults

#### Multiplayer Connection Issues
- Validate IP address format
- Check port availability
- Ensure firewall allows connections
- Verify multiplayer manager autoload

**Section sources**
- [main_menu.gd:109-117](file://Menu/main_menu.gd#L109-L117)
- [multiplayer_menu.gd:80-94](file://Menu/multiplayer_menu.gd#L80-L94)
- [global_settings.gd:238-244](file://Scripts/global_settings.gd#L238-L244)

## Conclusion
The main menu system provides a robust, extensible foundation for game navigation with comprehensive features for resource management, user preferences, and multiplayer connectivity. The modular architecture ensures maintainability while the integrated settings system provides seamless user experience across different platforms and languages. The implementation demonstrates best practices in UI responsiveness, error handling, and performance optimization.