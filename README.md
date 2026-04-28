# careermode-hub-lua-export
Lua export file for Aranaktu’s EAFC Live Editor. This script is used to export EA FC career mode data and prepare it for integration with the iOS app “CareerMode Hub”.

## Purpose

This repository contains Lua scripts that run inside the EAFC Live Editor on PC.  
The scripts export selected career mode data into JSON files, which can then be used by the CareerMode Hub iOS app or by a backend service.

The iOS app does not execute these Lua scripts directly.  
The scripts are only used as a PC-side export tool.

## Files

| File | Description |
|---|---|
| `mRbRaIn-fc25-careerhub.lua` | Career mode export script for FC 25 |
| `mRbRaIn-fc26-careerhub.lua` | Career mode export script for FC 26 |
| `mRbRaIn-fc26-all-players-export.lua` | Exports all FC 26 players into a JSON structure |

## Requirements

- EA SPORTS FC on PC
- Aranaktu’s EAFC Live Editor
- A loaded career mode save
- Lua script execution through the Live Editor

## Usage

1. Start EA SPORTS FC on PC.
2. Open Aranaktu’s EAFC Live Editor.
3. Load your career mode save.
4. Open the Lua Engine in the Live Editor.
5. Load one of the scripts from this repository.
6. Execute the script.
7. The exported JSON files will be written to the Windows Downloads folder.

## Output

The scripts generate JSON files that can be used for further processing, app integration or local analysis.

Example output files:

```text
FC25-Transfers-*.json
FC25-PlayerStats-*.json
FC25-Game-*.json
FC26-Transfers-*.json
FC26-PlayerStats-*.json
FC26-Game-*.json
FC26_all_players.json
