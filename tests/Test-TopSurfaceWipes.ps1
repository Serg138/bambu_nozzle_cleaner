# Run with: powershell.exe -NoProfile -File .\tests\Test-TopSurfaceWipes.ps1
# Uses synthetic G-code in disposable files; never connects to a printer.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$testDirectory = Join-Path $PSScriptRoot ('.top-surface-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testDirectory)
$script:checks = 0

function Assert-Equal($actual, $expected, [string] $message) {
    if ($actual -cne $expected) { throw "${message}: expected '$expected', got '$actual'." }
    $script:checks++
}

function New-TestGcode([string] $printer, [int[]] $topLayers = @(0, 1, 2, 4), [int] $layerCount = 6, [switch] $a1Optional) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in @(
        "; printer_model = Bambu Lab $printer",
        '; printable_area = 0x0,256x0,256x256,0x256',
        '; printable_height = 256',
        '; print_sequence = by layer',
        '; spiral_mode = 0',
        '; use_firmware_retraction = 0',
        '; filament_retraction_length = 0.4',
        "; total layer number: $layerCount",
        'G21', 'G90', 'M83', 'M204 S1000', 'G1 X100 Y100 Z0.2 F1200'
    )) { $lines.Add($line) }
    for ($layerIndex = 0; $layerIndex -lt $layerCount; $layerIndex++) {
        $height = (0.2 * ($layerIndex + 1)).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
        $travel = (0.2 * ($layerIndex + 1) + 0.4).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
        $lines.Add('; CHANGE_LAYER')
        if ($layerIndex -gt 0) {
            $lines.Add('; WIPE_START')
            $lines.Add('G1 E-0.4 F1800')
            $lines.Add('; WIPE_END')
        }
        $lines.Add("; Z_HEIGHT: $height")
        $lines.Add("G1 X100 Y100 Z$travel F12000")
        $lines.Add("G1 Z$height F1200")
        if ($layerIndex -gt 0) { $lines.Add('G1 E0.4 F1800') }
        $lines.Add('; FEATURE: Outer wall')
        $lines.Add('G1 X101 Y101 E0.05 F1200')
        if ($topLayers -contains $layerIndex) {
            if ($a1Optional -and $layerIndex -gt 1) {
                # A1 must defer wiping until unconditional motion and M204 restore state.
                foreach ($line in @(
                    '; SKIPPABLE_START', '; SKIPTYPE: timelapse', 'M622 J1',
                    'G1 X110 Y110 F9000', 'M623', '; SKIPTYPE: head_wrap_detect',
                    'M622 J1', 'G39', 'M623', '; SKIPPABLE_END',
                    "G1 X101 Y101 Z$height F1200"
                )) { $lines.Add($line) }
            }
            $lines.Add('; FEATURE: Top surface')
            $lines.Add('M204 S800')
            $lines.Add("G1 X103 Y104 E0.05 F1200 ; top extrusion layer=$layerIndex")
            $lines.Add('; FEATURE: Inner wall')
            $lines.Add('G1 X104 Y104 E0.05')
            $lines.Add('; FEATURE: Top surface')
            $lines.Add('G1 X104 Y105 E0.05')
        }
    }
    # A feature-like comment after printing must not change topmost detection.
    $lines.Add('; MACHINE_END_GCODE_START')
    $lines.Add('; FEATURE: Top surface')
    $lines.Add('M400')
    ($lines -join "`n") + "`n"
}

function Invoke-Processor([string] $scriptPath, [string] $path, [string[]] $options, [string] $expectedError = '') {
    # Use the exact -File entry point used by Studio, with the G-code path last.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @options $path 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($expectedError -ne '') {
        if ($exitCode -eq 0 -or ($result -join "`n") -notmatch $expectedError) {
            throw "Expected failure '$expectedError', got exit ${exitCode}: $result"
        }
    } elseif ($exitCode -ne 0) {
        throw "Processor failed with exit ${exitCode}: $result"
    }
    $script:checks++
}

function Test-Case([string] $scriptPath, [string] $name, [string] $source, [string[]] $options,
                   [int[]] $expectedTop, [int[]] $expectedBoundary = @(1)) {
    $path = Join-Path $testDirectory ($name + '.gcode')
    [IO.File]::WriteAllText($path, $source)
    Invoke-Processor $scriptPath $path $options
    $processed = [IO.File]::ReadAllText($path)
    $tops = @([regex]::Matches($processed, '(?m)^; NOZZLE_WIPE_BEGIN[^\r\n]* top_surface_layer_index=(\d+) ') |
        ForEach-Object { [int]$_.Groups[1].Value })
    $boundaries = @([regex]::Matches($processed, '(?m)^; NOZZLE_WIPE_BEGIN[^\r\n]* layer_index=(\d+) ') |
        ForEach-Object { [int]$_.Groups[1].Value })
    Assert-Equal ($tops -join ',') ($expectedTop -join ',') "$name top layers"
    Assert-Equal ($boundaries -join ',') ($expectedBoundary -join ',') "$name boundary layers"
    $actualLayer = -1
    $seen = @{}
    foreach ($line in ($processed -split "`r?`n")) {
        if ($line -eq '; CHANGE_LAYER') { $actualLayer++ }
        if ($line -match '^; NOZZLE_WIPE_BEGIN.* (?:top_surface_)?layer_index=(\d+) repeats=(\d+) ') {
            Assert-Equal $actualLayer ([int]$Matches[1]) "$name actual insertion layer"
            Assert-Equal $seen.ContainsKey($actualLayer) $false "$name duplicate cycle"
            Assert-Equal ([int]$Matches[2]) $(if ($actualLayer -eq 1) { 3 } else { 2 }) "$name wiping passes"
            $seen[$actualLayer] = $true
        }
    }
    foreach ($topLayer in $tops) {
        $wipeOffset = $processed.IndexOf(" top_surface_layer_index=$topLayer ")
        $extrusionOffset = $processed.IndexOf("G1 X103 Y104 E0.05 F1200 ; top extrusion layer=$topLayer")
        Assert-Equal ($wipeOffset -lt $extrusionOffset) $true "$name wipe before extrusion"
    }
    if ($expectedTop.Count + $expectedBoundary.Count -eq 0) {
        Assert-Equal $processed $source "$name unchanged when no wipe is due"
    }
    # Upload copies may have no extension. Reprocessing must be byte-for-byte stable.
    $uploadPath = Join-Path $testDirectory ($name + '-upload')
    [IO.File]::Copy($path, $uploadPath)
    $hashBefore = (Get-FileHash -LiteralPath $uploadPath).Hash
    Invoke-Processor $scriptPath $uploadPath $options
    Assert-Equal (Get-FileHash -LiteralPath $uploadPath).Hash $hashBefore "$name repeat processing"
    Write-Host "PASS $name"
    $path
}

try {
    foreach ($printer in @('A1', 'P1S', 'P2S')) {
        $scriptPath = Join-Path $repoRoot "ImplementWipePostProcess$printer.ps1"
        $source = New-TestGcode $printer
        $defaultPath = Test-Case $scriptPath "$printer-default" $source @() @(4)
        foreach ($top in @(0, 1)) {
            foreach ($topmost in @(0, 1)) {
                $expected = if ($top -eq 1) { @(2, 4) } elseif ($topmost -eq 1) { @(4) } else { @() }
                $options = @('-WipeBeforeTop', "$top", '-WipeBeforeTopmost', "$topmost")
                $null = Test-Case $scriptPath "$printer-$top-$topmost" ($source -replace "`n", "`r`n") $options $expected
            }
        }
        $both = @('-WipeBeforeTop', '1', '-WipeBeforeTopmost', '1')
        $null = Test-Case $scriptPath "$printer-interval" $source ($both + @('-LayerInterval', '2')) @() @(1, 2, 4)
        $null = Test-Case $scriptPath "$printer-early" $source @('-EarlyWipeAfterLayers', '4') @() @(1, 4)
        $null = Test-Case $scriptPath "$printer-first-boundary" (New-TestGcode $printer @(1) 2) ($both + @('-LayerInterval', '1')) @() @(1)
        $null = Test-Case $scriptPath "$printer-no-top" (New-TestGcode $printer @()) @() @()
        $null = Test-Case $scriptPath "$printer-first-layer-top" (New-TestGcode $printer @(0)) $both @()
        $null = Test-Case $scriptPath "$printer-single-layer" (New-TestGcode $printer @(0) 1) $both @() @()
        $null = Test-Case $scriptPath "$printer-last-layer-top" (New-TestGcode $printer @(2, 5)) @() @(5)

        $hashBefore = (Get-FileHash -LiteralPath $defaultPath).Hash
        foreach ($changed in @(@('-WipeBeforeTop', '1'), @('-WipeBeforeTopmost', '0'))) {
            Invoke-Processor $scriptPath $defaultPath $changed 'Wipe settings differ'
            Assert-Equal (Get-FileHash -LiteralPath $defaultPath).Hash $hashBefore "$printer changed flags preserve file"
        }
        foreach ($flag in @('-WipeBeforeTop', '-WipeBeforeTopmost')) {
            foreach ($invalid in @('-1', '2')) {
                Invoke-Processor $scriptPath $defaultPath @($flag, $invalid) 'ValidateSet|validation|Cannot validate'
                Assert-Equal (Get-FileHash -LiteralPath $defaultPath).Hash $hashBefore "$printer invalid flag preserves file"
            }
        }
    }
    $a1Script = Join-Path $repoRoot 'ImplementWipePostProcessA1.ps1'
    $a1Source = New-TestGcode 'A1' -a1Optional
    $null = Test-Case $a1Script 'A1-optional-default' $a1Source @() @(4)
    $null = Test-Case $a1Script 'A1-optional-both' $a1Source @('-WipeBeforeTop', '1') @(2, 4)
    Write-Host "All $script:checks checks passed in Windows PowerShell."
} finally {
    # Only remove this run's generated directory after verifying its resolved location.
    $resolvedTestDirectory = (Resolve-Path -LiteralPath $testDirectory).Path
    if ((Split-Path -Parent $resolvedTestDirectory) -ne $PSScriptRoot -or
        (Split-Path -Leaf $resolvedTestDirectory) -notmatch '^\.top-surface-[0-9a-f]{32}$') {
        throw "Refusing to remove unexpected test directory: $resolvedTestDirectory"
    }
    Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
}
