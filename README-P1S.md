# Automatic nozzle wiping for Bambu Lab P1S

> [!IMPORTANT]
> `ImplementWipePostProcessP1S.ps1` is for a **Bambu Lab P1S with the stock rear nozzle wiper**. Its wipe coordinates are fixed to the stock wiper. Do not use it with a relocated, aftermarket, or modified wiper without adapting and validating the motion path.
>
> **Windows only:** the script uses Windows PowerShell.

This is a separate post-processing script for Bambu Studio. The [P2S script](README.md) uses different printer commands; select only the script for the printer that will run the job. Both scripts check the `printer_model` setting before modifying G-code.

## What the script does

The script adds a nozzle-wiping cycle:

- after the first completed layer, if another layer follows;
- after every configured number of completed layers;
- after the optional early layer;
- before the first `Top surface` section on a layer that has not already received a cycle.

The first-layer cycle has three wiping strokes. Other cycles have two. At a layer transition, the nozzle returns to the next layer's travel target. At a top surface, it returns to the interrupted position. Retraction and feed/acceleration state are restored before printing continues.

The script raises the nozzle 3 mm above its current position, approaches the stock rear wiper via X70, Y245, and Y265, wipes between X70 and X100, then exits via X165, Y256. These coordinates follow the approach and exit used by Bambu Studio's [P1S filament-change profile](https://github.com/bambulab/BambuStudio/blob/master/resources/profiles/BBL/machine/Bambu%20Lab%20P1S%200.4%20nozzle%20template%20change_filament_gcode.json). **Y265 is deliberately outside the 0–256 mm printable area:** it is a stock printer travel position, not a position for printing on the plate.

## Supported print conditions

The script requires:

- a P1S with the stock rear nozzle wiper and its normal travel path;
- a 256 × 256 mm printable area starting at X0 Y0;
- layer-by-layer printing, with spiral vase mode and firmware retraction disabled;
- a single-filament print without tool changes;
- G-code movements and retraction that the script can reconstruct safely.

It checks the printer model, return coordinates, clearance above the printed layer, printable height, coordinate and extrusion modes, and previously inserted wiping blocks. If a safe cycle cannot be established, it reports an error and does not change the G-code. Running it again with the same settings does not duplicate cycles.

## Setup

1. Save `ImplementWipePostProcessP1S.ps1` in a permanent location on your computer.
2. In Bambu Studio, open **Process → Others → Post-processing scripts**. Enable advanced settings if needed.
3. Save a separate Process profile for the P1S.
4. Enter the following as **one physical line**, replacing `D:\YOUR_PATH_HERE\` with the folder containing the script:

   ```text
   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP1S.ps1" -LayerInterval 20
   ```

   Bambu Studio appends the sliced G-code path as the last argument.

5. Select the P1S printer and the new Process profile before slicing and sending a job.

If you change parameters or update the script, slice the original project again.

## Options

| Option | Description | Default |
| --- | --- | --- |
| `-LayerInterval` | Wipe after every N completed layers. Must be positive. | `20` |
| `-EarlyWipeAfterLayers` | Add one early cycle after this layer; `0` disables it. | `0` |
| `-WipeRetractMm` | Set the target retraction during wiping, from 0 to 2 mm. | Value from the sliced profile |

Without an override, target retraction comes from `filament_retraction_length`, falling back to `retraction_length`. The script reuses the slicer's existing retraction where possible and compensates for any extra retraction before extrusion resumes.

## First print and safety

The stock wiper path is based on Bambu Studio's P1S profile, but a G-code check cannot verify the physical wiper, an obstruction, a warped print, or a change to the printer's motion limits. Watch the **complete** first wiping cycle: lift, travel to the rear, wiping, exit, return, and descent. Stop the print if the toolhead hits the model or frame, contacts the plate unexpectedly, or misses the wiper.

The script refuses a cycle when there is not enough Z clearance for the lift. Its supported conditions exclude modified start or machine G-code that changes the stock coordinate system or wiper access. For a custom wiper, its location and motion path must be measured and validated separately.
