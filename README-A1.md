# Automatic nozzle wiping for Bambu Lab A1

> [!IMPORTANT]
> `ImplementWipePostProcessA1.ps1` is for a **Bambu Lab A1 with the stock side purge wiper and stock machine G-code**. It uses the wiper at negative X. It does not use the rear brush near the build plate, and it is not for an A1 mini or a modified wiper.
>
> **Windows only:** the script uses Windows PowerShell.

The [P2S](README.md) and [P1S](README-P1S.md) scripts use different cleaning paths. Each script checks the `printer_model` setting before modifying G-code.

## What the script does

The script adds a wiping cycle:

- after the first completed layer, if another layer follows;
- after every configured number of completed layers;
- after the optional early layer;
- before the first `Top surface` section on a layer that has not already received a cycle.

The first-layer cycle has three wiping strokes. Other cycles have two. At a layer transition, the nozzle returns to the next layer's travel target. At a top surface, it returns to the interrupted position. Retraction and feed/acceleration state are restored before printing continues.

The script raises Z by 3 mm, moves to Y128, enters the side purge-wiper area via X0 and X−48.2, wipes between X−48.2 and X−38.2, and exits via X0. Bambu Studio's [A1 filament-change profile](https://github.com/bambulab/BambuStudio/blob/master/resources/profiles/BBL/machine/Bambu%20Lab%20A1%200.4%20nozzle%20template%20change_filament_gcode.json) uses the same side-wiper positions during printing. **Negative X is outside the printable area:** it is a stock printer travel position, not a position for printing on the plate.

This cycle does not extrude extra filament, change nozzle temperature, or use the rear brush. Its cleaning action is the side wiper's mechanical contact with the nozzle.

## Supported print conditions

The script requires:

- an A1 with the stock side purge wiper and stock machine G-code;
- a 256 × 256 mm printable area starting at X0 Y0;
- layer-by-layer printing, with spiral vase mode and firmware retraction disabled;
- a single-filament print without tool changes;
- G-code movements and retraction that the script can reconstruct safely.

It checks the printer model, return coordinates, clearance above the printed layer, printable height, coordinate and extrusion modes, and previously inserted wiping blocks. If a safe cycle cannot be established, it reports an error and does not change the G-code. Running it again with the same settings does not duplicate cycles.

## Setup

1. Save `ImplementWipePostProcessA1.ps1` in a permanent location on your computer.
2. In Bambu Studio, open **Process → Others → Post-processing scripts**. Enable advanced settings if needed.
3. Save a separate Process profile for the A1.
4. Enter the following as **one physical line**, replacing `D:\YOUR_PATH_HERE\` with the folder containing the script:

   ```text
   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessA1.ps1" -LayerInterval 20
   ```

   Bambu Studio appends the sliced G-code path as the last argument.

5. Select the A1 printer and the new Process profile before slicing and sending a job.

If you change parameters or update the script, slice the original project again.

## Options

| Option | Description | Default |
| --- | --- | --- |
| `-LayerInterval` | Wipe after every N completed layers. Must be positive. | `20` |
| `-EarlyWipeAfterLayers` | Add one early cycle after this layer; `0` disables it. | `0` |
| `-WipeRetractMm` | Set the target retraction during wiping, from 0 to 2 mm. | Value from the sliced profile |

Without an override, target retraction comes from `filament_retraction_length`, falling back to `retraction_length`. The script reuses the slicer's existing retraction where possible and compensates for any extra retraction before extrusion resumes.

## First print and safety

The side-wiper path is based on Bambu Studio's A1 profile, but G-code checks cannot verify the physical wiper, an obstruction, a warped print, or changes to the printer's motion limits. Watch the **complete** first wiping cycle: Z lift, travel to the side, wiping, return, and descent. Stop the print if the toolhead hits the model or frame, contacts the plate unexpectedly, or misses the wiper.

The script refuses a cycle when there is not enough Z clearance for the lift. If the machine start G-code or wiper has been changed, the fixed negative-X path must be checked again. The A1's rear brush is a different mechanism and is outside this script's scope.
