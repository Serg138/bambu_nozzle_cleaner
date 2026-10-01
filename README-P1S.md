# Automatic nozzle wiping for Bambu Lab P1S

> [!IMPORTANT]
> `ImplementWipePostProcessP1S.ps1` is for a **Bambu Lab P1S with the stock rear nozzle wiper**. Its wipe coordinates are fixed to the stock wiper. Do not use it with a relocated, aftermarket, or modified wiper without adapting and validating the motion path.

See the [main README](README.md) for supported print conditions, setup, all parameters, top/topmost behavior, retraction, and first-print precautions. This page covers the P1S wiper path and commands.

## P1S wiper path

The script raises the nozzle 3 mm above its current position, approaches the stock rear wiper via X70, Y245, and Y265, wipes between X70 and X100, then exits via X165, Y256. These coordinates follow the approach and exit used by Bambu Studio's [P1S filament-change profile](https://github.com/bambulab/BambuStudio/blob/master/resources/profiles/BBL/machine/Bambu%20Lab%20P1S%200.4%20nozzle%20template%20change_filament_gcode.json). **Y265 is deliberately outside the 0–256 mm printable area:** it is a stock printer travel position, not a position for printing on the plate.

Modified start or machine G-code that changes the stock coordinate system or wiper access is unsupported. For a custom wiper, its location and motion path must be measured and validated separately.

## Command examples

Use these lines with the [shared setup instructions](README.md#setup); replace `D:\YOUR_PATH_HERE\` with your script folder. See [Options](README.md#options) for flag combinations and defaults.

Default settings:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP1S.ps1" -LayerInterval 20
```

Topmost only, explicitly:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP1S.ps1" -WipeBeforeTop 0 -WipeBeforeTopmost 1
```

Every top surface, with both triggers enabled:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP1S.ps1" -WipeBeforeTop 1 -WipeBeforeTopmost 1
```

Only the every-top trigger:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP1S.ps1" -WipeBeforeTop 1 -WipeBeforeTopmost 0
```

Both top-surface triggers disabled:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP1S.ps1" -WipeBeforeTop 0 -WipeBeforeTopmost 0
```

Custom interval, early cycle, and retraction:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\YOUR_PATH_HERE\ImplementWipePostProcessP1S.ps1" -LayerInterval 30 -EarlyWipeAfterLayers 15 -WipeRetractMm 0.6
```
