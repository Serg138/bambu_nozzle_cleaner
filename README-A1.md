# Automatic nozzle wiping for Bambu Lab A1

> [!IMPORTANT]
> `ImplementWipePostProcessA1.ps1` is for a **Bambu Lab A1 with the stock side purge wiper and stock machine G-code**. It uses the wiper at negative X. It does not use the rear brush near the build plate, and it is not for an A1 mini or a modified wiper.

See the [main README](README.md) for supported print conditions, setup, all parameters, top/topmost behavior, retraction, and first-print precautions. This page covers the A1 wiper path and commands.

## A1 wiper path

The script raises Z by 3 mm, moves to Y128, enters the side purge-wiper area via X0 and X−48.2, wipes between X−48.2 and X−38.2, and exits via X0. Bambu Studio's [A1 filament-change profile](https://github.com/bambulab/BambuStudio/blob/master/resources/profiles/BBL/machine/Bambu%20Lab%20A1%200.4%20nozzle%20template%20change_filament_gcode.json) uses the same side-wiper positions during printing. **Negative X is outside the printable area:** it is a stock printer travel position, not a position for printing on the plate.

This cycle does not extrude extra filament, change nozzle temperature, or use the rear brush. Its cleaning action is the side wiper's mechanical contact with the nozzle.

If the machine start G-code or wiper has been changed, the fixed negative-X path must be checked again. The A1's rear brush is a different mechanism and is outside this script's scope.

## Command examples

Use these lines with the [shared setup instructions](README.md#setup); replace `D:\YOUR_PATH_HERE\` with your script folder. See [Options](README.md#options) for flag combinations and defaults.

Default settings:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessA1.ps1" -LayerInterval 20
```

Topmost only, explicitly:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessA1.ps1" -WipeBeforeTop 0 -WipeBeforeTopmost 1
```

Every top surface, with both triggers enabled:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessA1.ps1" -WipeBeforeTop 1 -WipeBeforeTopmost 1
```

Only the every-top trigger:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessA1.ps1" -WipeBeforeTop 1 -WipeBeforeTopmost 0
```

Both top-surface triggers disabled:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessA1.ps1" -WipeBeforeTop 0 -WipeBeforeTopmost 0
```

Custom interval, early cycle, and retraction:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessA1.ps1" -LayerInterval 30 -EarlyWipeAfterLayers 15 -WipeRetractMm 0.6
```
