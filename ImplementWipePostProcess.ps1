param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $GcodeFile,
    [Alias('Interval')]
    [int] $LayerInterval = 20,
    [int] $EarlyWipeAfterLayers = 0,
    [string] $WipeRetractMm = ''
)

$ErrorActionPreference = 'Stop'
if ($LayerInterval -lt 1) { throw 'LayerInterval must be at least 1 layer.' }
if ($EarlyWipeAfterLayers -lt 0) { throw 'EarlyWipeAfterLayers cannot be negative.' }
$path = (Resolve-Path -LiteralPath $GcodeFile).Path
# Studio passes a .gcode path while slicing and an extensionless copy during upload.
$gcode = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
function Parse-Number([string] $value) {
    [double]::Parse($value, [Globalization.CultureInfo]::InvariantCulture)
}
function Format-Number([double] $value) {
    $value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}
function Get-Header([string] $key) {
    $pattern = '(?m)^; ' + [regex]::Escape($key) + ' = ([^\r\n]*)\r?$'
    $matches = [regex]::Matches($gcode, $pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one G-code setting: $key" }
    $matches[0].Groups[1].Value.Trim()
}
function Require-Header([string] $key, [string] $value) {
    if ((Get-Header $key) -ne $value) { throw "Unsupported G-code setting: $key = $value" }
}

$printableArea = Get-Header 'printable_area'
$areaPoints = $printableArea -split '\s*,\s*'
if ($areaPoints.Count -lt 4) { throw 'Unsupported printable area: expected a 256 x 256 mm build plate.' }
$minX = [double]::PositiveInfinity; $maxX = [double]::NegativeInfinity
$minY = [double]::PositiveInfinity; $maxY = [double]::NegativeInfinity
foreach ($point in $areaPoints) {
    if ($point -notmatch '^([-+]?(?:\d+(?:\.\d*)?|\.\d+))x([-+]?(?:\d+(?:\.\d*)?|\.\d+))$') {
        throw 'Unsupported printable area: invalid coordinate.'
    }
    $pointX = Parse-Number $Matches[1]; $pointY = Parse-Number $Matches[2]
    $minX = [Math]::Min($minX, $pointX); $maxX = [Math]::Max($maxX, $pointX)
    $minY = [Math]::Min($minY, $pointY); $maxY = [Math]::Max($maxY, $pointY)
}
if ($minX -ne 0 -or $maxX -ne 256 -or $minY -ne 0 -or $maxY -ne 256) {
    throw 'Unsupported printable area: expected a 256 x 256 mm build plate with origin at 0,0.'
}
$maxZ = Parse-Number (Get-Header 'printable_height')
if ([double]::IsNaN($maxZ) -or [double]::IsInfinity($maxZ) -or $maxZ -le 3.5) {
    throw 'Invalid printable height in G-code.'
}
$maxWipeStartZ = $maxZ - 3.5
Require-Header 'print_sequence' 'by layer'
Require-Header 'spiral_mode' '0'
Require-Header 'use_firmware_retraction' '0'
$declaredLayerMatch = [regex]::Match($gcode, '(?m)^; total layer number: (\d+)\r?$')
if (-not $declaredLayerMatch.Success) { throw 'Missing total layer count in G-code.' }
$declaredLayerCount = [int]$declaredLayerMatch.Groups[1].Value
$actualLayerCount = [regex]::Matches($gcode, '(?m)^; CHANGE_LAYER\r?$').Count
if ($declaredLayerCount -lt 1 -or $actualLayerCount -ne $declaredLayerCount) {
    throw 'Layer markers do not match the declared layer count.'
}
if ($WipeRetractMm -ne '') {
    $targetRetract = Parse-Number $WipeRetractMm
} else {
    # The filament override takes precedence over the printer's base value.
    $profileRetract = Get-Header 'filament_retraction_length'
    if ($profileRetract -eq 'nil') { $profileRetract = Get-Header 'retraction_length' }
    $targetRetract = Parse-Number $profileRetract
}
if ([double]::IsNaN($targetRetract) -or [double]::IsInfinity($targetRetract) -or
    $targetRetract -lt 0 -or $targetRetract -gt 2) {
    throw 'Wipe retraction target must be between 0 and 2 mm.'
}
$retractTag = Format-Number $targetRetract
$settingsTag = "routine_rev=9 layer_interval=$LayerInterval early_layers=$EarlyWipeAfterLayers retract_mm=$retractTag"
if ($gcode -match '(?m)^; (?!NOZZLE_WIPE_)[A-Z][A-Z0-9_]*_WIPE_(?:BEGIN|END|RESUME|PRIME)\b') {
    throw 'Obsolete nozzle wipe markers found in G-code. Slice the original model again.'
}
$beginCount = [regex]::Matches($gcode, '(?m)^; NOZZLE_WIPE_BEGIN(?:\s|$)').Count
$endCount = [regex]::Matches($gcode, '(?m)^; NOZZLE_WIPE_END\r?$').Count
if ($beginCount -ne $endCount) { throw 'Incomplete nozzle wipe block found in G-code.' }
$existingBlocks = [regex]::Matches($gcode, '(?ms)^; NOZZLE_WIPE_BEGIN[^\r\n]*\r?\n(.*?)^; NOZZLE_WIPE_END\r?$')
if ($existingBlocks.Count -ne $beginCount) { throw 'Malformed or nested nozzle wipe block found in G-code.' }
if ($beginCount -eq 0 -and $gcode -match '(?m)^; NOZZLE_WIPE_(?:RESUME|PRIME)\b') {
    throw 'Orphaned nozzle wipe resume or prime marker found in G-code.'
}

function New-WipeBlock([string] $label, [double] $x, [double] $y, [double] $z, [double] $feed, [double] $accel, [double] $printedHeight, [double] $extraRetract, [int] $repeats, [bool] $layerTransition = $false) {
    if ([double]::IsNaN($x) -or [double]::IsInfinity($x) -or
        [double]::IsNaN($y) -or [double]::IsInfinity($y) -or
        [double]::IsNaN($z) -or [double]::IsInfinity($z) -or
        [double]::IsNaN($feed) -or [double]::IsInfinity($feed) -or
        [double]::IsNaN($accel) -or [double]::IsInfinity($accel) -or
        [double]::IsNaN($printedHeight) -or [double]::IsInfinity($printedHeight) -or
        $z -gt $maxWipeStartZ -or $z -lt 0.15 -or $x -lt 0 -or $x -gt 256 -or $y -lt 0 -or $y -gt 256 -or
        $printedHeight -lt 0.15 -or $printedHeight -gt $maxWipeStartZ -or
        $z -lt ($printedHeight - 0.01) -or $z -gt ($printedHeight + 5.0) -or
        $feed -le 0 -or $accel -le 0 -or
        [double]::IsNaN($extraRetract) -or $extraRetract -lt 0 -or $extraRetract -gt 2 -or
        $repeats -lt 1 -or $repeats -gt 3) {
        throw "Unsafe return position for $label."
    }
    $sx = Format-Number $x; $sy = Format-Number $y
    $sz = Format-Number $z; $safeZ = Format-Number ($z + 3.0)
    $oldFeed = Format-Number $feed
    $oldAccel = Format-Number $accel
    $returnZ = if ($layerTransition) { $safeZ } else { $sz }
    $block = [Collections.Generic.List[string]]::new()
    $block.Add("; NOZZLE_WIPE_BEGIN $label repeats=$repeats extra_retract_mm=$(Format-Number $extraRetract) return_X=$sx return_Y=$sy return_Z=$returnZ old_feed=$oldFeed old_accel=$oldAccel printed_height=$(Format-Number $printedHeight)")
    $block.Add('M400'); $block.Add('G90'); $block.Add('M83')
    if ($extraRetract -gt 0.0005) { $block.Add("G1 E-$(Format-Number $extraRetract) F1800") }
    $block.Add("G1 Z$safeZ F1200")
    $block.Add('M400'); $block.Add('G150.3')
    for ($i = 0; $i -lt $repeats; $i++) {
        $block.Add('G150.1 F8000')
    }
    $block.Add('M400')
    $block.Add('G90'); $block.Add('M83')
    $block.Add("G1 Z$safeZ F1200")
    $block.Add("G1 X$sx Y$sy F15000")
    if (-not $layerTransition) {
        $block.Add("G1 Z$sz F1200")
        if ($extraRetract -gt 0.0005) { $block.Add("G1 E$(Format-Number $extraRetract) F1800") }
    }
    $block.Add("G1 F$oldFeed")
    $block.Add("M204 S$oldAccel")
    $block.Add('; NOZZLE_WIPE_END')
    $block
}

if ($beginCount -gt 0) {
    $boundaryCount = 0
    $primeCount = 0
    foreach ($block in $existingBlocks) {
        $marker = ($block.Value -split "`r?`n", 2)[0]
        if (-not $marker.Contains($settingsTag)) {
            throw 'Wipe settings differ from the existing G-code. Slice the original model again.'
        }
        $blockPattern = '^; NOZZLE_WIPE_BEGIN ' + [regex]::Escape($settingsTag) +
            ' (layer_index|top_surface_layer_index)=(\d+) repeats=([23]) extra_retract_mm=([\d.]+) return_X=([\d.]+) return_Y=([\d.]+) return_Z=([\d.]+) old_feed=([\d.]+) old_accel=([\d.]+) printed_height=([\d.]+)$'
        $fields = [regex]::Match($marker, $blockPattern)
        if (-not $fields.Success) { throw 'Malformed nozzle wipe marker found in G-code.' }
        $kind = $fields.Groups[1].Value
        $layerIndex = [int]$fields.Groups[2].Value
        $repeats = [int]$fields.Groups[3].Value
        $extra = Parse-Number $fields.Groups[4].Value
        $returnX = Parse-Number $fields.Groups[5].Value
        $returnY = Parse-Number $fields.Groups[6].Value
        $returnZ = Parse-Number $fields.Groups[7].Value
        $oldFeed = Parse-Number $fields.Groups[8].Value
        $oldAccel = Parse-Number $fields.Groups[9].Value
        $printed = Parse-Number $fields.Groups[10].Value
        $isBoundary = $kind -eq 'layer_index'
        $originalZ = if ($isBoundary) { $returnZ - 3.0 } else { $returnZ }
        $expected = @(New-WipeBlock "$settingsTag $kind=$layerIndex" $returnX $returnY $originalZ $oldFeed $oldAccel $printed $extra $repeats $isBoundary) -join "`n"
        if (($block.Value -replace "`r`n", "`n") -cne $expected) {
            throw 'Incomplete or modified nozzle wipe movements found in G-code.'
        }
        if (-not $isBoundary) { continue }
        $boundaryCount++
        $following = $gcode.Substring($block.Index + $block.Length)
        $nextLayer = [regex]::Match($following, '(?m)^; CHANGE_LAYER\r?$')
        if (-not $nextLayer.Success) { throw 'Missing next layer after nozzle wipe.' }
        $following = $following.Substring(0, $nextLayer.Index)
        $resume = [regex]::Matches($following, '(?m)^; NOZZLE_WIPE_RESUME layer_index=(\d+) travel_Z=([\d.]+) travel_feed=([\d.]+)\r?$')
        if ($resume.Count -ne 1 -or [int]$resume[0].Groups[1].Value -ne $layerIndex) {
            throw 'Missing or duplicated next-layer resume after nozzle wipe.'
        }
        $travelZ = Parse-Number $resume[0].Groups[2].Value
        $travelFeed = Parse-Number $resume[0].Groups[3].Value
        $resumeText = $following.Substring($resume[0].Index) -split "`r?`n"
        if ($travelZ -lt ($printed + 0.1) -or $travelZ -gt $maxZ -or $travelFeed -le 0 -or
            $resumeText.Count -lt 3 -or
            $resumeText[1] -cne "G1 Z$(Format-Number $travelZ) F1200" -or
            $resumeText[2] -cne "G1 F$(Format-Number $travelFeed)") {
            throw 'Incomplete next-layer Z resume after nozzle wipe.'
        }
        $primes = [regex]::Matches($following, '(?m)^; NOZZLE_WIPE_PRIME layer_index=(\d+) E=([\d.]+) feed=([\d.]+)\r?$')
        if ($extra -gt 0.0005) {
            if ($primes.Count -ne 1 -or [int]$primes[0].Groups[1].Value -ne $layerIndex -or
                $primes[0].Index -le $resume[0].Index -or
                [Math]::Abs((Parse-Number $primes[0].Groups[2].Value) - $extra) -gt 0.0005) {
                throw 'Missing or mismatched deferred prime after nozzle wipe.'
            }
            $primeFeed = Parse-Number $primes[0].Groups[3].Value
            $primeText = $following.Substring($primes[0].Index) -split "`r?`n"
            if ($primeFeed -le 0 -or $primeText.Count -lt 3 -or
                $primeText[1] -cne "G1 E$(Format-Number $extra) F1800" -or
                $primeText[2] -cne "G1 F$(Format-Number $primeFeed)") {
                throw 'Incomplete deferred prime after nozzle wipe.'
            }
            $primeCount++
        } elseif ($primes.Count -ne 0) {
            throw 'Unexpected deferred prime after nozzle wipe.'
        }
    }
    if ([regex]::Matches($gcode, '(?m)^; NOZZLE_WIPE_RESUME\b').Count -ne $boundaryCount -or
        [regex]::Matches($gcode, '(?m)^; NOZZLE_WIPE_PRIME\b').Count -ne $primeCount) {
        throw 'Orphaned nozzle wipe resume or prime marker found in G-code.'
    }
    Write-Output 'Wipes already present; upload copy left unchanged.'
    exit 0
}

$newline = if ($gcode.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $gcode -split "`r?`n"
function Find-LayerWipeInsertIndex([string[]] $sourceLines, [int] $markerIndex) {
    $wipeStarted = $false
    for ($j = $markerIndex + 1; $j -lt $sourceLines.Count; $j++) {
        $candidate = $sourceLines[$j]
        if ($candidate -match '^; (?:CHANGE_LAYER|FEATURE:|WIPE_TOWER_START)\b') { break }
        if ($candidate -match '^; WIPE_START\s*$') { $wipeStarted = $true }
        if ($wipeStarted -and $candidate -match '^; WIPE_END\s*$') {
            $insertAt = $j + 1
            # Allow non-motion progress and settings commands before a separate slicer retract.
            for ($k = $insertAt; $k -lt $sourceLines.Count; $k++) {
                if ($sourceLines[$k] -match '^; (?:CHANGE_LAYER|FEATURE:|WIPE_TOWER_START)\b') { break }
                $nextCode = ($sourceLines[$k] -split ';', 2)[0].Trim()
                if ($nextCode -eq '') { continue }
                if ($nextCode -match '^G1\s+E-(?:\d+(?:\.\d*)?|\.\d+)(?:\s+F\d+(?:\.\d*)?)?\s*$') {
                    $insertAt = $k + 1
                    continue
                }
                if ($nextCode -match '^(?:M73|M991|M204|M104|M140|M1003|M106|G17)(?:\s|$)' -or
                    $nextCode -match '^G1\s+F\d+(?:\.\d*)?\s*$') { continue }
                break
            }
            return $insertAt
        }
    }
    throw "Cannot locate the completed slicer wipe after layer marker at line $($markerIndex + 1)."
}
function Find-NextLayerTarget([string[]] $sourceLines, [int] $insertIndex, [double] $lastPrintedHeight) {
    for ($j = $insertIndex; $j -lt $sourceLines.Count; $j++) {
        $candidate = $sourceLines[$j]
        if ($candidate -match '^; (?:CHANGE_LAYER|MACHINE_END_GCODE_START)\b') { break }
        $motion = ($candidate -split ';', 2)[0].Trim()
        if ($motion -match '^(?:G91|M82)(?:\s|$)') {
            throw "Unsupported XYZ or extrusion mode before next-layer travel at line $($j + 1)."
        }
        if ($motion -notmatch '^G(?:0|1|2|3)(?:\s|$)') { continue }
        if ($motion -match '(?<![A-Za-z])E[-+\d.]') {
            throw "Extrusion or another retract precedes next-layer travel at line $($j + 1)."
        }
        if ($motion -match '(?<![A-Za-z])[XY][-+\d.]') {
            if ($motion -notmatch '^G1\s+X([-+.\d]+)\s+Y([-+.\d]+)\s+Z([-+.\d]+)(?:\s+F[-+.\d]+)?\s*$') {
                throw "Unsupported next-layer travel at line $($j + 1)."
            }
            $targetX = Parse-Number $Matches[1]
            $targetY = Parse-Number $Matches[2]
            $targetZ = Parse-Number $Matches[3]
            if ($targetX -lt 0 -or $targetX -gt 256 -or $targetY -lt 0 -or $targetY -gt 256 -or
                $targetZ -lt ($lastPrintedHeight + 0.1) -or $targetZ -gt $maxZ) {
                throw "Unsafe next-layer travel target at line $($j + 1)."
            }
            return [pscustomobject]@{ X = $targetX; Y = $targetY }
        }
    }
    throw 'Cannot find a safe travel target for the next layer.'
}
$out = [Collections.Generic.List[string]]::new()
$absoluteXYZ = $null
$relativeE = $false
$millimeters = $false
$x = $null; $y = $null; $z = $null; $feed = $null; $accel = $null
$layer = -1
$wipeCount = 0
$topSurfaceWipeCount = 0
$endGcode = $false
$insideWipeTower = $false
$conditionalDepth = 0
$skippableDepth = 0
$boundaryWiped = $false
$topSurfaceSeen = $false
$retractedAmount = $null
$printedHeight = $null
$pendingBoundaryIndex = $null
$pendingBoundaryLayer = $null
$pendingBoundaryHeight = $null
$pendingBoundaryRepeats = $null
$resumeAtTravel = $false
$resumePrintedHeight = $null
$resumeTargetX = $null
$resumeTargetY = $null
$resumeLayer = $null
$deferredPrime = 0.0

for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
    if ($null -ne $pendingBoundaryIndex -and $lineIndex -eq $pendingBoundaryIndex) {
        if ($resumeAtTravel -or $deferredPrime -gt 0.0005) { throw 'Previous layer transition did not finish before another wipe.' }
        if (-not $absoluteXYZ -or -not $relativeE -or -not $millimeters -or $null -eq $x -or $null -eq $y -or $null -eq $z -or $null -eq $feed -or $null -eq $accel -or $null -eq $pendingBoundaryHeight -or $null -eq $retractedAmount) {
            throw "Cannot establish safe XYZ/E/feed state after slicer retract for layer index $pendingBoundaryLayer."
        }
        # The slicer's retract remains in effect during travel to the next layer.
        $extraRetract = if ($retractedAmount -gt 0.0005) { 0.0 } else { $targetRetract }
        $nextTarget = Find-NextLayerTarget $lines $lineIndex $pendingBoundaryHeight
        foreach ($cmd in (New-WipeBlock "$settingsTag layer_index=$pendingBoundaryLayer" $nextTarget.X $nextTarget.Y $z $feed $accel $pendingBoundaryHeight $extraRetract $pendingBoundaryRepeats $true)) { $out.Add($cmd) }
        $resumeAtTravel = $true
        $resumePrintedHeight = $pendingBoundaryHeight
        $resumeTargetX = $nextTarget.X
        $resumeTargetY = $nextTarget.Y
        $resumeLayer = $pendingBoundaryLayer
        $deferredPrime = $extraRetract
        $wipeCount++
        $boundaryWiped = $true
        $pendingBoundaryIndex = $null
    }
    $line = $lines[$lineIndex]
    $code = ($line -split ';', 2)[0].Trim()
    if ($line -match '^; MACHINE_END_GCODE_START\s*$') { $endGcode = $true }
    if ($line -match '^; SKIPPABLE_START\s*$') { $skippableDepth++ }
    if ($line -match '^; SKIPPABLE_END\s*$') {
        if ($skippableDepth -eq 0) { throw 'Unmatched SKIPPABLE_END in G-code.' }
        $skippableDepth--
    }
    if ($code -match '^M622(?:\s|$)') { $conditionalDepth++ }
    if ($code -match '^M623(?:\s|$)') {
        if ($conditionalDepth -eq 0) { throw 'Unmatched M623 in G-code.' }
        $conditionalDepth--
    }
    if ($layer -ge 0 -and -not $endGcode) {
        if (($conditionalDepth -gt 0 -or $skippableDepth -gt 0) -and
            $code -match '^(?:G(?:0|1|2|3|10|11|20|21|28|90|91|92|150)(?:\.\d+)?|M(?:82|83|204))(?:\s|$)') {
            throw 'Optional motion or coordinate state during printing cannot be modeled safely.'
        }
    }
    if ($line -match '^; WIPE_TOWER_START\s*$') { $insideWipeTower = $true }
    if ($line -match '^; WIPE_TOWER_END\s*$') { $insideWipeTower = $false }
    if ($line -match '^; Z_HEIGHT: ([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*$') {
        $height = Parse-Number $Matches[1]
        if ($null -eq $printedHeight -or $height -gt $printedHeight) { $printedHeight = $height }
    }

    if (-not $endGcode -and $line -match '^; CHANGE_LAYER\s*$') {
        if ($conditionalDepth -ne 0 -or $skippableDepth -ne 0) { throw 'Layer boundary inside an optional G-code block.' }
        if ($insideWipeTower) { throw 'Layer boundary found inside a wipe tower section.' }
        $layer++
        $boundaryWiped = $false
        $topSurfaceSeen = $false
        # The first boundary wins over the periodic and top-surface triggers.
        $afterFirstLayer = ($layer -eq 1)
        $due = $afterFirstLayer -or ($layer -gt 0 -and $layer % $LayerInterval -eq 0) -or
               ($layer -eq $EarlyWipeAfterLayers -and $EarlyWipeAfterLayers -gt 0)
        if ($due) {
            $pendingBoundaryIndex = Find-LayerWipeInsertIndex $lines $lineIndex
            $pendingBoundaryLayer = $layer
            $pendingBoundaryHeight = $printedHeight
            $pendingBoundaryRepeats = if ($afterFirstLayer) { 3 } else { 2 }
        }
    }

    if (-not $endGcode -and $layer -gt 0 -and $line -match '^; FEATURE:\s*Top surface\s*$' -and -not $topSurfaceSeen) {
        if ($insideWipeTower -or $conditionalDepth -ne 0 -or $skippableDepth -ne 0) {
            throw 'Top surface begins inside a wipe tower or optional G-code block.'
        }
        # A layer may contain multiple separate top-surface islands.
        $topSurfaceSeen = $true
        if (-not $boundaryWiped) {
            if (-not $absoluteXYZ -or -not $relativeE -or -not $millimeters -or $null -eq $x -or $null -eq $y -or $null -eq $z -or $null -eq $feed -or $null -eq $accel -or $null -eq $printedHeight -or $null -eq $retractedAmount) {
                throw "Cannot establish safe XYZ/E/feed state before top surface on layer index $layer."
            }
            $extraRetract = [Math]::Max(0.0, $targetRetract - $retractedAmount)
            foreach ($cmd in (New-WipeBlock "$settingsTag top_surface_layer_index=$layer" $x $y $z $feed $accel $printedHeight $extraRetract 2)) { $out.Add($cmd) }
            $wipeCount++
            $topSurfaceWipeCount++
        }
    }

    $replacementLines = $null
    if (($resumeAtTravel -or $deferredPrime -gt 0.0005) -and $code -match '^(?:G91|M82)(?:\s|$)') {
        throw "XYZ or extrusion mode changed before next-layer resume at line $($lineIndex + 1)."
    }
    if ($resumeAtTravel) {
        if ($line -match '^; CHANGE_LAYER\s*$' -or $endGcode) { throw 'No safe travel height was found after a layer wipe.' }
        $zMove = [regex]::Match($code, '(?<![A-Za-z])Z([-+]?(?:\d+(?:\.\d*)?|\.\d+))(?:\s|$)')
        if ($code -match '^G(?:0|1|2|3)(?:\s|$)' -and $zMove.Success) {
            $travelZ = Parse-Number $zMove.Groups[1].Value
            if ($travelZ -lt ($resumePrintedHeight + 0.1) -or $travelZ -gt $maxZ) {
                throw "Unsafe travel height after layer wipe at line $($lineIndex + 1)."
            }
            if ($code -match '^G3\s+Z([-+.\d]+)\s+I([-+.\d]+)\s+J([-+.\d]+)\s+P1\s+F([-+.\d]+)\s*$') {
                $travelFeed = Parse-Number $Matches[4]
                if ($travelFeed -le 0) { throw 'Invalid layer travel feed rate.' }
                $replacementLines = @("G1 Z$(Format-Number $travelZ) F1200", "G1 F$(Format-Number $travelFeed)")
            } elseif ($code -match '^G1\s+X([-+.\d]+)\s+Y([-+.\d]+)\s+Z([-+.\d]+)(?:\s+F([-+.\d]+))?\s*$') {
                if ([Math]::Abs((Parse-Number $Matches[1]) - $resumeTargetX) -gt 0.001 -or
                    [Math]::Abs((Parse-Number $Matches[2]) - $resumeTargetY) -gt 0.001) {
                    throw 'Next-layer travel target changed before Z descent.'
                }
                $travelFeed = if ($Matches[4]) { Parse-Number $Matches[4] } else { $feed }
                if ($travelFeed -le 0) { throw 'Invalid layer travel feed rate.' }
                $replacementLines = @("G1 Z$(Format-Number $travelZ) F1200", "G1 F$(Format-Number $travelFeed)")
            } elseif ($code -match '^G1\s+Z[-+.\d]+(?:\s+F([-+.\d]+))?\s*$') {
                $travelFeed = if ($Matches[1]) { Parse-Number $Matches[1] } else { $feed }
                if ($travelFeed -le 0) { throw 'Invalid layer travel feed rate.' }
                $replacementLines = @("G1 Z$(Format-Number $travelZ) F1200", "G1 F$(Format-Number $travelFeed)")
            } else {
                throw "Unsupported layer travel after wipe at line $($lineIndex + 1)."
            }
            $replacementLines = @("; NOZZLE_WIPE_RESUME layer_index=$resumeLayer travel_Z=$(Format-Number $travelZ) travel_feed=$(Format-Number $travelFeed)") + $replacementLines
            $resumeAtTravel = $false
        }
    }
    if ($deferredPrime -gt 0.0005 -and $code -match '^G(?:0|1|2|3)(?:\s|$)') {
        $nextE = [regex]::Match($code, '(?<![A-Za-z])E([-+]?(?:\d+(?:\.\d*)?|\.\d+))(?:\s|$)')
        if ($nextE.Success) {
            $nextEMm = Parse-Number $nextE.Groups[1].Value
            if ($nextEMm -lt 0) { throw 'Unexpected second retract before deferred prime.' }
            if ($nextEMm -gt 0) {
                if ($resumeAtTravel -or -not $relativeE -or $null -eq $feed -or $feed -le 0) { throw 'Cannot prime safely before next-layer extrusion.' }
                $out.Add("; NOZZLE_WIPE_PRIME layer_index=$resumeLayer E=$(Format-Number $deferredPrime) feed=$(Format-Number $feed)")
                $out.Add("G1 E$(Format-Number $deferredPrime) F1800")
                $out.Add("G1 F$(Format-Number $feed)")
                $deferredPrime = 0.0
            }
        }
    }
    if ($null -ne $replacementLines) {
        foreach ($replacement in $replacementLines) { $out.Add($replacement) }
    } else {
        $out.Add($line)
    }

    if ($code -match '^G90(?:\s|$)') { $absoluteXYZ = $true; continue }
    if ($code -match '^G91(?:\s|$)') { $absoluteXYZ = $false; continue }
    if ($code -match '^G21(?:\s|$)') { $millimeters = $true; continue }
    if ($code -match '^G20(?:\s|$)') { throw 'Inch-mode G-code is not supported.' }
    if ($code -match '^M82(?:\s|$)') { $relativeE = $false; $retractedAmount = $null; continue }
    if ($code -match '^M83(?:\s|$)') { $relativeE = $true; continue }
    if ($code -match '^M204(?:\s|$)') {
        $accelMatch = [regex]::Match($code, '(?:^|\s)S([-+]?(?:\d+(?:\.\d*)?|\.\d+))(?:\s|$)')
        if ($accelMatch.Success) {
            $accel = Parse-Number $accelMatch.Groups[1].Value
        } elseif ($layer -ge 0 -and -not $endGcode) {
            throw 'Unsupported acceleration command during printing; safe acceleration restoration cannot be verified.'
        }
        continue
    }

    if ($layer -ge 0 -and -not $endGcode -and $code -match '^T\d+(?:\s|$)') {
        throw 'A tool change was found after printing began; multi-filament jobs are not supported.'
    }
    if ($layer -ge 0 -and -not $endGcode -and
        ($code -match '^G28(?:\s|$)' -or $code -match '^G5[3-9](?:\s|$)' -or
         $code -match '^G1[01](?:\s|$)' -or
         $code -match '^G(?:29|130|150|380|3811)(?:\.\d+)?(?:\s|$)' -or
         $code -match '^M(?:206|211|420)(?:\s|$)' -or
         ($code -match '^G92(?:\s|$)' -and
          ($code -match '(?<![A-Za-z])[XYZ][-+\d.]' -or $code -notmatch '(?<![A-Za-z])E[-+\d.]')))) {
        throw 'A motion state, probing, or coordinate reset command was found during printing; safe return cannot be verified.'
    }
    if ($layer -ge 0 -and -not $endGcode -and $code -match '^(G\d+(?:\.\d+)?)(?:\s|$)' -and
        $Matches[1] -notin @('G0', 'G1', 'G2', 'G3', 'G4', 'G17', 'G21', 'G90', 'G91', 'G92')) {
        throw "Unsupported G-code motion or mode during printing: $($Matches[1])"
    }
    if ($code -match '^G28(?:\s|$)' -or $code -match '^G150(?:\.\d+)?(?:\s|$)') {
        $x = $null; $y = $null; $z = $null
        $feed = $null
        $retractedAmount = $null
        continue
    }

    if ($code -match '^G92(?:\s|$)') {
        foreach ($match in [regex]::Matches($code, '(?<![A-Za-z])([XYZ])([-+]?(?:\d+(?:\.\d*)?|\.\d+))')) {
            $value = Parse-Number $match.Groups[2].Value
            switch ($match.Groups[1].Value) { X {$x=$value} Y {$y=$value} Z {$z=$value} }
        }
        continue
    }

    if ($code -match '^G(?:0|1|2|3)(?:\s|$)') {
        if ($layer -ge 0 -and $relativeE) {
            # Track slicer retractions so the wipe only adds the missing amount.
            # Treat XY extrusion after an unknown macro as resumed model printing.
            $eMatch = [regex]::Match($code, '(?<![A-Za-z])E([-+]?(?:\d+(?:\.\d*)?|\.\d+))(?:\s|$)')
            if ($eMatch.Success) {
                $eMove = Parse-Number $eMatch.Groups[1].Value
                if ($eMove -gt 0) {
                    if ($null -ne $retractedAmount) {
                        $retractedAmount = [Math]::Max(0.0, $retractedAmount - $eMove)
                    } elseif ($code -match '(?<![A-Za-z])[XY][-+\d.]') {
                        $retractedAmount = 0.0
                    }
                } elseif ($eMove -lt 0 -and $null -ne $retractedAmount) {
                    $retractedAmount += -$eMove
                }
            }
        }
        foreach ($match in [regex]::Matches($code, '(?<![A-Za-z])([XYZF])([-+]?(?:\d+(?:\.\d*)?|\.\d+))')) {
            $value = Parse-Number $match.Groups[2].Value
            switch ($match.Groups[1].Value) {
                X { if ($absoluteXYZ) {$x=$value} elseif ($null -ne $x) {$x+=$value} }
                Y { if ($absoluteXYZ) {$y=$value} elseif ($null -ne $y) {$y+=$value} }
                Z { if ($absoluteXYZ) {$z=$value} elseif ($null -ne $z) {$z+=$value} }
                F { $feed=$value }
            }
        }
    }
}

if ($conditionalDepth -ne 0) { throw 'Unclosed conditional G-code block during printing.' }
if ($skippableDepth -ne 0) { throw 'Unclosed skippable G-code block during printing.' }
if ($null -ne $pendingBoundaryIndex) { throw 'Unplaced layer-boundary wipe remains at the end of G-code.' }
if ($resumeAtTravel -or $deferredPrime -gt 0.0005) { throw 'Layer transition did not complete after wipe.' }
if ($wipeCount -eq 0) {
    Write-Output 'No wipe scheduled for the selected intervals; G-code left unchanged.'
    exit 0
}
$newGcode = $out -join $newline
$stagedPath = Join-Path ([IO.Path]::GetDirectoryName($path)) ([IO.Path]::GetRandomFileName())
$backupPath = Join-Path ([IO.Path]::GetDirectoryName($path)) ([IO.Path]::GetRandomFileName())
try {
    [IO.File]::WriteAllText($stagedPath, $newGcode, [Text.UTF8Encoding]::new($false))
    [IO.File]::Replace($stagedPath, $path, $backupPath)
    [IO.File]::Delete($backupPath)
} finally {
    if ([IO.File]::Exists($stagedPath)) { [IO.File]::Delete($stagedPath) }
}
Write-Output "Wipes inserted: $wipeCount (before top surface: $topSurfaceWipeCount)"
