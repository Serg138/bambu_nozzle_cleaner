# Automatic nozzle wiping for Bambu Studio

> [!IMPORTANT]
> This is the main guide for all three scripts: **Bambu Lab P2S, P1S, and A1**. Shared options and wiping rules are documented here. Printer-specific wiper details and copyable commands are in [README-P1S.md](README-P1S.md) and [README-A1.md](README-A1.md). Each printer has a separate script.
>
> **Windows only:** the current setup uses Windows PowerShell and is not supported on macOS or Linux.

## Support development

If this project is useful to you, you can [support its development on Boosty](https://boosty.to/bambu_nozzle_cleaner/donate).

Your support will help me improve and maintain the existing script, test it more thoroughly, and adapt it for other 3D printer models in the future.

## What the script does

These post-processing scripts for Bambu Studio add automatic nozzle-wiping cycles to sliced G-code:

- after the first completed layer, if another layer follows;
- after every configured number of completed layers;
- after an optional early layer;
- before the topmost surface by default;
- optionally before the first `Top surface` section on every layer containing one.

| Printer | Script | Wiper |
| --- | --- | --- |
| P2S | `ImplementWipePostProcessP2s.ps1` | Firmware-controlled wiping station |
| P1S | `ImplementWipePostProcessP1S.ps1` | Stock rear nozzle wiper; see [P1S details](README-P1S.md) |
| A1 | `ImplementWipePostProcessA1.ps1` | Stock side purge wiper; see [A1 details](README-A1.md) |

All three scripts use the same options and scheduling rules. They work with a 256 x 256 mm printable area whose origin is X0 Y0 and support any nozzle diameter and filament type, but currently process only single-filament, layer-by-layer prints whose movements and retraction state can be reconstructed safely.

Before making any changes, the script checks the sliced G-code. If the print is unsupported or a safe wiping cycle cannot be confirmed, processing stops with an error.

> [!NOTE]
> On large models, processing the sliced G-code may take several minutes. This is expected—please do not panic or try to disable or interrupt the script while it is running.

## Supported print conditions

The script currently requires:

- Windows with Windows PowerShell;
- a Bambu Lab P2S, P1S, or A1 with the matching script and supported wiper;
- a 256 x 256 mm printable area starting at X0 Y0;
- layer-by-layer printing;
- spiral vase mode disabled;
- firmware retraction disabled;
- a single-filament print without tool changes;
- G-code movements and retraction that the script can reconstruct safely.

Each script checks `printer_model` and validates return coordinates, clearance above the printed layer, printable height, coordinate and extrusion modes, and previously inserted wiping blocks. Running it repeatedly with the same settings does not duplicate wiping cycles.

If validation fails, the script reports an error instead of modifying the G-code.

## Setup

1. Save the script for your printer in a permanent location on your computer. The example below uses P2S; use the matching commands for [P1S](README-P1S.md#command-examples) or [A1](README-A1.md#command-examples).
2. In Bambu Studio, open **Process → Others → Post-processing scripts**. Enable advanced settings if needed.
3. Save a copy of your Process profile under a separate name, for example `Nozzle wipe every 20 layers`.
4. Add the following as a single physical line in the **Post-processing scripts** field, replacing `D:\YOUR_PATH_HERE\` with the actual folder containing the script:

   ```text
   C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1" -LayerInterval 20
   ```

   Bambu Studio automatically appends the path to the sliced G-code as the last argument.

5. Save the profile. When opening another 3MF project, make sure this Process profile is selected before clicking **Slice plate** and **Print plate**.

If you change the script parameters (including either top-surface flag) or update from an older version, slice the original project again before printing. The scripts reject previously processed G-code with different settings.

## Options

| Option | Description | Default |
| --- | --- | --- |
| `-LayerInterval` | Runs a wiping cycle after every N completed layers. Must be a positive integer. | `20` |
| `-EarlyWipeAfterLayers` | Adds one extra early wiping cycle after the specified layer. Use `0` to disable it. | `0` |
| `-WipeRetractMm` | Overrides the target retraction used during wiping. Accepted range: 0–2 mm. | Value from the sliced profile |
| `-WipeBeforeTop` | `1` enables wiping before the first `Top surface` section on every applicable layer; `0` disables this trigger. Includes the topmost surface. | `0` (off) |
| `-WipeBeforeTopmost` | `1` enables wiping before the first `Top surface` section on the last layer containing one; `0` disables this trigger. | `1` (on) |

Both top-surface flags accept `0` or `1`, so they can be passed directly through Windows PowerShell's `-File` command line in Bambu Studio. They are independent: disabling one does not disable the other.

| `-WipeBeforeTop` | `-WipeBeforeTopmost` | Top-surface wiping |
| --- | --- | --- |
| `0` | `1` | Only the topmost surface (default). |
| `1` | `0` | Every layer containing `Top surface`, including the topmost. |
| `1` | `1` | Every layer containing `Top surface`, with one cycle on the topmost layer. |
| `0` | `0` | No cycles triggered by top surfaces. First-layer, interval, and early-layer cycles still run. |

## Command examples

Each example below is one complete P2S line for the **Post-processing scripts** field. Bambu Studio appends the G-code path automatically. Unless overridden, all examples also enable topmost wiping.

Default: wipe after the first layer, every 20 layers, and before the topmost surface:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1"
```

Wipe after the first layer and then every 15 layers:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1" -LayerInterval 15
```

Wipe after the first layer, add an early cycle after layer 15, and then wipe after layers 30, 60, and so on:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1" -LayerInterval 30 -EarlyWipeAfterLayers 15
```

Use a target retraction of 0.6 mm when the script has to add retraction:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1" -LayerInterval 15 -WipeRetractMm 0.6
```

Enable wiping before every top-surface layer, with both triggers enabled:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1" -WipeBeforeTop 1 -WipeBeforeTopmost 1
```

Enable only the every-top trigger (which also covers the topmost surface):

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1" -WipeBeforeTop 1 -WipeBeforeTopmost 0
```

Disable both top-surface triggers, keeping the first-layer and periodic cycles:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP2s.ps1" -WipeBeforeTop 0 -WipeBeforeTopmost 0
```

## When wiping runs

- **After the first layer:** one cycle with three wiping passes, provided the model has another layer.
- **After every N completed layers:** one cycle with two wiping passes. Set N with `-LayerInterval`.
- **After the layer selected by `-EarlyWipeAfterLayers`:** one additional cycle with two wiping passes.
- **Before the topmost surface (`-WipeBeforeTopmost 1`, default):** one cycle with two wiping passes before the first `Top surface` section on the last layer containing that feature.
- **Before each top-surface layer (`-WipeBeforeTop 1`, optional):** one cycle with two wiping passes before the first `Top surface` section on each applicable layer.

**Topmost** means the last layer in the entire print containing Bambu Studio's `; FEATURE: Top surface` marker, even if later layers contain other features. It is not calculated separately for each object or island. If there are no `Top surface` markers, neither top-surface trigger adds a cycle.

There is no wiping during the first layer, even if it contains a `Top surface` section.

Only one wiping cycle is inserted per layer, even when both top-surface flags are enabled or a layer contains multiple top-surface islands. If a layer already receives a cycle at its start because of the first-layer, interval, or early-layer setting, another cycle is not added before `Top surface`. If the first-layer cycle also matches the configured interval, it remains a single cycle with three passes.

During a cycle, the nozzle is lifted by 3 mm, moved to the wiping station, wiped, and returned to the print. At a layer transition, it returns directly to the start of the next layer. At a top surface, it returns to the interrupted position. Retraction and feed/acceleration state are restored before printing continues. On A1, the top-surface cycle is placed immediately before its first extrusion, after the slicer restores the motion settings needed for a safe return.

## Retraction

By default, the script reads the target retraction from `filament_retraction_length` in the sliced profile. If that value is unavailable, it uses `retraction_length`.

To specify another target, use `-WipeRetractMm`. The accepted range is 0–2 mm.

Between layers, the script reuses the slicer's existing retraction whenever possible. If additional retraction is needed, it adds only the missing amount and compensates for it before extrusion resumes.

## Safety

The **P2S** script inserts `G150.3` and `G150.1 F8000` firmware commands directly into the G-code. The printer firmware controls the internal movements of these commands, and those movements are not visible in the Bambu Studio preview. P1S and A1 use fixed stock-wiper paths described in their printer-specific guides.

G-code validation cannot guarantee that the toolhead will avoid every model, build plate configuration, or unexpected obstacle. Carefully watch the complete wiping cycle during the first print with a new setup: lift, travel to the wiping station, wiping, return, and descent.

Stop the print immediately if the toolhead hits the model or frame, contacts the build plate unexpectedly, or misses the wiper.

## Development checks

From the repository folder, run the regression checks in Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-TopSurfaceWipes.ps1
```

The tests use temporary synthetic G-code for all three printers. They cover flag combinations, topmost detection, overlapping triggers, repeated processing, invalid settings, and A1's deferred top-surface wipe.
