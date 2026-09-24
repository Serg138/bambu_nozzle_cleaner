# Nozzle wiping through a Bambu Studio profile

The project uses one way to add nozzle wiping: a post-processing script in the Bambu Studio **Process profile**. The script accepts sliced G-code for a printer with a 256 x 256 mm printable area (origin at X0 Y0), any nozzle diameter, and any filament type. It processes single-filament, layer-by-layer jobs when their movements and retraction state can be reconstructed. It checks the sliced G-code before changing the file.

The command examples below are for Windows only. Replace `D:\YOUR_PATH_HERE\` with the actual folder where you saved `ImplementWipePostProcess.ps1` before adding the final command to Bambu Studio.

## Profile setup

1. In Bambu Studio, open **Process → Others → Post-processing scripts**. Enable advanced settings if needed.
2. Save a copy of your Process profile under a separate name, for example `Nozzle wipe every 20 layers`.
3. Put this single physical line in the **Post-processing scripts** field:

   ```text
   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 20
   ```

   Bambu Studio appends the path to the sliced G-code as the last argument. Keep the `.ps1` file at the path shown above. `-LayerInterval` accepts a positive integer; if omitted, the default is 20.

4. Save the profile. After opening another 3MF, check that this Process profile is selected, then click **Slice plate** and **Print plate**.

Previously sliced G-code that has already passed through an older version of the script must be sliced again. Repeated Studio calls do not duplicate inserts when the current settings match.

## Invocation examples

Each example below is a separate line for the **Post-processing scripts** field. Use one complete option; Bambu Studio appends the G-code path automatically.

After the first layer, then every 20 layers — default interval:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1"
```

After the first layer, then every 15 layers:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 15
```

After the first layer, additionally after layer 15, then after layers 30, 60, and so on:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 30 -EarlyWipeAfterLayers 15
```

Use a target retraction of 0.6 mm where the script has to add the retraction itself:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 15 -WipeRetractMm 0.6
```

The interval does not guarantee that every G-code file can be processed. If the slicer changes coordinate or extrusion modes, or changes the movement order on a selected layer, the script can stop without changing the file.

## When wiping runs

- **After the first layer:** one cycle with three `G150.1 F8000` commands, if the model has another layer. Wiping runs after the normal `WIPE_END` section and before travel to the next layer.
- **After every N completed layers:** one cycle with two `G150.1 F8000` commands. The slicer's normal moves and retraction finish first, then wiping runs.
- **Before the first `Top surface` section on each layer that has one:** one cycle with two `G150.1 F8000` commands. Additional sections on the same layer do not add another cycle.

There is no wiping during the first layer, including when it contains a `Top surface` section.

If wiping after the first layer or at interval N has already run on the current layer, no second cycle is added before `Top surface`. If the first layer also matches the interval, one cycle with three repetitions remains.

The cycle starts with `G150.3`, followed by two or three `G150.1` commands. The firmware controls the actual path inside these commands. The horizontal return uses `F15000`, matching the normal travel from the wipe tower to the model in the supplied slice. During a layer transition, the script returns the lifted nozzle directly to the start of the next layer. It replaces the normal spiral lift with a controlled descent to the travel height; the slicer's following commands lower the nozzle to print height and restore extrusion. After the first layer, when the slicer combines XY and Z travel into one command, the script keeps only the Z descent at the already reached position.

## Retraction

The script reads the target length from the sliced profile: first `filament_retraction_length` when it contains a number, otherwise `retraction_length`. In the two supplied files this is **0.4 mm**: the filament override is 0.4 and the printer base setting is 0.8.

If another target length is needed, add it to the profile command, for example `-WipeRetractMm 0.6`. The allowed range is 0–2 mm. Between layers, the script uses the slicer's existing retraction without adding another one. If the slicer did not retract after the first layer, the script temporarily retracts to the target length and compensates for it immediately before the first extrusion on the next layer. Before a `Top surface` section, the script still adds and compensates only the missing part of the retraction. The slicer's own settings are not changed.

## What the script checks

- A 256 x 256 mm printable area starting at X0 Y0, a valid printable height, layer-by-layer printing, spiral vase disabled, and firmware retraction disabled. There are no blanket header checks for printer model, nozzle diameter, filament type, timelapse setting, or `wipe_tower_no_sparse_layers`; the generated movements are still checked below.
- No tool changes, coordinate resets, repeated homing, or unsupported G-code motion or mode commands during printing. Motion commands inside conditional or skippable blocks are also rejected.
- Explicit absolute XY/Z coordinates, millimeters, relative E extrusion, current feed rate, and acceleration. Unknown `M204` or `G92` formats during printing are rejected.
- The known current retraction amount. Processing stops if it cannot be reconstructed from the G-code movements.
- Return coordinates inside the 256 x 256 mm printable area; return Z is at least 0.15 mm and no lower than the printed layer height; the nozzle lifts by 3 mm before horizontal travel and stays within the printer's declared printable height. During a layer transition, the next descent must leave clearance above the printed layer. Processing stops if a safe transition cannot be confirmed.
- On a repeated Studio call, the inserted wiping, return, descent, and extrusion compensation commands are checked and wiping is not inserted a second time. Changing parameters requires slicing the original project again.

Local checking on the two supplied slices produced 8 inserts at a 15-layer interval for `Retraction test` (after the first layer and 7 more at the interval). These files do not contain `Top surface`; that path was checked on a test copy of the G-code with added section markers.

## Important safety boundary

The script uses `G150.3` and `G150.1 F8000` from the standard P2S templates. In the [P2S machine start profile](https://github.com/bambulab/BambuStudio/blob/v02.08.04.57/resources/profiles/BBL/machine/Bambu%20Lab%20P2S%200.4%20nozzle%20template%20machine_start_gcode.json), `G150.1` is used for station wiping; in the [P2S timelapse profile](https://github.com/bambulab/BambuStudio/blob/v02.08.04.57/resources/profiles/BBL/machine/Bambu%20Lab%20P2S%200.4%20nozzle%20template%20time_lapse_gcode.json), `G150.3` is used during printing to move to the waste collector. The [standard A1 machine start profile](https://github.com/bambulab/BambuStudio/blob/master/resources/profiles/BBL/machine/Bambu%20Lab%20A1%200.4%20nozzle%20template%20machine_start_gcode.json) uses explicit `G1/G2` wiping movements instead; this script's `G150` sequence has not been validated on A1. **These templates do not reveal the internal path or the conditions required for a safe mid-print `G150.1` call.** It is also unknown whether this firmware command changes the filament position or retraction state. G-code analysis therefore cannot guarantee that the head will avoid the model, the build plate, or the PEI sheet, or that extrusion will remain accurate afterward. Preview does not reveal the internal movements of this firmware command.

The wiping commands are inserted directly into the G-code. The timing and return speed were changed after print review; the new sequence has not yet been checked on the printer. During the first print, watch the full cycle: lift, travel to the station, wiping, return, and descent. Stop the print immediately if the head hits the model or frame, contacts the plate unexpectedly, or misses the wiper.
