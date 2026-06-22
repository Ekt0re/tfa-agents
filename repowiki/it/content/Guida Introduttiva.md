# Guida Introduttiva

<cite>
**File Referenziati in Questo Documento**
- [project.godot](file://project.godot)
- [export_presets.cfg](file://export_presets.cfg)
- [InputManager.tscn](file://Game/InputManager.tscn)
- [input_manager.gd](file://Game/input_manager.gd)
- [main_menu.tscn](file://Menu/main_menu.tscn)
- [main_menu.gd](file://Menu/main_menu.gd)
- [settings_menu.tscn](file://Menu/settings_menu.tscn)
- [settings_menu.gd](file://Menu/settings_menu.gd)
- [settings_panel.tscn](file://Menu/settings_panel.tscn)
- [settings_panel.gd](file://Menu/settings_panel.gd)
- [HUD_Game.tscn](file://Menu/HUD/HUD_Game.tscn)
- [hud_game.gd](file://Menu/HUD/hud_game.gd)
- [pause_menu.tscn](file://Menu/pause_menu.tscn)
- [pause_menu.gd](file://Menu/pause_menu.gd)
- [game_over_menu.tscn](file://Menu/game_over_menu.tscn)
- [game_over_menu.gd](file://Menu/game_over_menu.gd)
- [multiplayer_menu.tscn](file://Menu/multiplayer_menu.tscn)
- [multiplayer_menu.gd](file://Menu/multiplayer_menu.gd)
- [lobby.tscn](file://Menu/lobby.tscn)
- [lobby.gd](file://Menu/lobby.gd)
- [pvp_map.tscn](file://Maps/pvp_map.tscn)
- [dev_map.tscn](file://Maps/dev_map.tscn)
- [player.tscn](file://player.tscn)
- [bot.tscn](file://bot.tscn)
- [bot_simple.tscn](file://bot_simple.tscn)
- [virtual_joystick_plus.gd](file://addons/virtual_joystick_plus/virtual_joystick_plus.gd)
- [plugin.cfg](file://addons/virtual_joystick_plus/plugin.cfg)
- [global_settings.gd](file://Scripts/global_settings.gd)
- [game_events.gd](file://Scripts/game_events.gd)
- [resource_preloader.gd](file://Scripts/resource_preloader.gd)
- [markdown_to_bbcode.gd](file://Scripts/markdown_to_bbcode.gd)
- [mission_editor/plugin.cfg](file://addons/mission_editor/plugin.cfg)
- [shader-previewer/plugin.cfg](file://addons/shader-previewer/plugin.cfg)
</cite>

## Sommario
1. [Introduzione](#introduzione)
2. [Struttura Progetto](#struttura-progetto)
3. [Componenti Principali](#componenti-principali)
4. [Panoramica Architettura](#panoramica-architettura)
5. [Installazione e Configurazione](#installazione-e-configurazione)
6. [Configurazione Iniziale Progetto](#configurazione-iniziale-progetto)
7. [Procedure Primo Avvio](#procedure-primo-avvio)
8. [Tutorial Comandi Base](#tutorial-comandi-base)
9. [Navigazione Menu Principale](#navigazione-menu-principale)
10. [Loop Gameplay Base](#loop-gameplay-base)
11. [Configurazione Impostazioni Essenziali](#configurazione-impostazioni-essenziali)
12. [Guida Risoluzione Problemi](#guida-risoluzione-problemi)
13. [Verifica Requisiti Sistema](#verifica-requisiti-sistema)
14. [Conclusione](#conclusione)

## Introduzione
TFA Agents è un gioco d'azione 2D costruito con Godot Engine. Questa guida ti aiuta a installare, configurare e giocare il gioco su desktop Windows e dispositivi mobile. Copre prerequisiti, configurazione specifica della piattaforma, configurazione iniziale, primo avvio, comandi, menu, gameplay base, impostazioni e risoluzione dei problemi.

## Struttura Progetto
Il progetto segue un layout modulare Godot:
- Le scene definiscono le aree di gameplay e l'interfaccia utente (ad es. menu principali, HUD, mappe)
- Gli script implementano comportamenti per giocatori, bot, eventi e impostazioni
- Gli asset includono animazioni, audio, tileset, armi e temi dell'interfaccia
- I componenti aggiuntivi forniscono strumenti riutilizzabili (ad es. joystick virtuale per mobile, editor missioni, anteprima shader)
- I preset di esportazione definiscono i target di build e le versioni
