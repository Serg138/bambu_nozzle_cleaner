# Automatic nozzle wiping for Bambu Studio

> [!IMPORTANT]
> The script currently supports only **Bambu Lab P1S and P2S** printers.
>
> **Windows only:** the current setup uses Windows PowerShell and is not supported on macOS or Linux.

## Support development

If this project is useful to you, you can [support its development on Boosty](https://boosty.to/bambu_nozzle_cleaner/donate).

Your support will help me improve and maintain the existing script, test it more thoroughly, and adapt it for other 3D printer models in the future.

## What the script does

`ImplementWipePostProcess.ps1` is a post-processing script for Bambu Studio. It adds automatic nozzle-wiping cycles to sliced G-code:

- after the first layer;
- after every configured number of completed layers;
- before the first `Top surface` section on a layer.

The script works with a 256 x 256 mm printable area whose origin is X0 Y0. It supports any nozzle diameter and filament type, but currently processes only single-filament, layer-by-layer prints whose movements and retraction state can be reconstructed safely.

Before making any changes, the script checks the sliced G-code. If the print is unsupported or a safe wiping cycle cannot be confirmed, processing stops with an error.

> [!NOTE]
> On large models, processing the sliced G-code may take several minutes. This is expected—please do not panic or try to disable or interrupt the script while it is running.

## Supported print conditions

The script currently requires:

- Windows with Windows PowerShell;
- a Bambu Lab P1S or P2S printer;
- a 256 x 256 mm printable area starting at X0 Y0;
- layer-by-layer printing;
- spiral vase mode disabled;
- firmware retraction disabled;
- a single-filament print without tool changes;
- G-code movements and retraction that the script can reconstruct safely.

The script validates return coordinates, clearance above the printed layer, printable height, coordinate and extrusion modes, and previously inserted wiping blocks. Running it repeatedly with the same settings does not duplicate wiping cycles.

If validation fails, the script reports an error instead of modifying the G-code.

## Setup

1. Save `ImplementWipePostProcess.ps1` in a permanent location on your computer.
2. In Bambu Studio, open **Process → Others → Post-processing scripts**. Enable advanced settings if needed.
3. Save a copy of your Process profile under a separate name, for example `Nozzle wipe every 20 layers`.
4. Add the following as a single physical line in the **Post-processing scripts** field, replacing `D:\YOUR_PATH_HERE\` with the actual folder containing the script:

   ```text
   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 20
   ```

   Bambu Studio automatically appends the path to the sliced G-code as the last argument.

5. Save the profile. When opening another 3MF project, make sure this Process profile is selected before clicking **Slice plate** and **Print plate**.

If you change the script parameters or update from an older version, slice the original project again before printing.

## Options

| Option | Description | Default |
| --- | --- | --- |
| `-LayerInterval` | Runs a wiping cycle after every N completed layers. Must be a positive integer. | `20` |
| `-EarlyWipeAfterLayers` | Adds one extra early wiping cycle after the specified layer. Use `0` to disable it. | `0` |
| `-WipeRetractMm` | Overrides the target retraction used during wiping. Accepted range: 0–2 mm. | Value from the sliced profile |

## Command examples

Each example below is one complete line for the **Post-processing scripts** field. Bambu Studio appends the G-code path automatically.

Wipe after the first layer and then every 20 layers:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1"
```

Wipe after the first layer and then every 15 layers:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 15
```

Wipe after the first layer, add an early cycle after layer 15, and then wipe after layers 30, 60, and so on:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 30 -EarlyWipeAfterLayers 15
```

Use a target retraction of 0.6 mm when the script has to add retraction:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcess.ps1" -LayerInterval 15 -WipeRetractMm 0.6
```

## When wiping runs

- **After the first layer:** one cycle with three wiping passes, provided the model has another layer.
- **After every N completed layers:** one cycle with two wiping passes. Set N with `-LayerInterval`.
- **After the layer selected by `-EarlyWipeAfterLayers`:** one additional cycle with two wiping passes.
- **Before the first `Top surface` section on each applicable layer:** one cycle with two wiping passes.

There is no wiping during the first layer, even if it contains a `Top surface` section.

Only one wiping cycle is inserted at a given point. If a layer already receives a cycle because of the interval or the early-layer setting, a duplicate cycle is not added before `Top surface`. If the first-layer cycle also matches the configured interval, it remains a single cycle with three passes.

During a cycle, the nozzle is lifted by 3 mm, moved to the wiping station, wiped, and returned to the print. At a layer transition, it returns directly to the start of the next layer.

## Retraction

By default, the script reads the target retraction from `filament_retraction_length` in the sliced profile. If that value is unavailable, it uses `retraction_length`.

To specify another target, use `-WipeRetractMm`. The accepted range is 0–2 mm.

Between layers, the script reuses the slicer's existing retraction whenever possible. If additional retraction is needed, it adds only the missing amount and compensates for it before extrusion resumes.

## Safety

The script inserts `G150.3` and `G150.1 F8000` firmware commands directly into the G-code. The printer firmware controls the internal movements of these commands, and those movements are not visible in the Bambu Studio preview.

G-code validation cannot guarantee that the toolhead will avoid every model, build plate configuration, or unexpected obstacle. Carefully watch the complete wiping cycle during the first print with a new setup: lift, travel to the wiping station, wiping, return, and descent.

Stop the print immediately if the toolhead hits the model or frame, contacts the build plate unexpectedly, or misses the wiper.
