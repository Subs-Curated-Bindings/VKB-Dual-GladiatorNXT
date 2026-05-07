<#
.SYNOPSIS
    Re-applies the [Enhanced] Dual VKB Gladiator NXT MFD binds to Star Citizen's
    live actionmaps.xml.

.DESCRIPTION
    Star Citizen has a long-standing bug where the vehicle_mfd action map gets
    cleared whenever a control profile is loaded over an existing one. The
    bindings that should be there are wiped (set to "js2_ ") and a couple of
    them are removed entirely. This script puts them back.

    WORKFLOW:
      1. Load the [ENH][NXT] layout in-game once (Customization > Control
         Profiles > Use this profile) so the vehicle_mfd actionmap exists in
         actionmaps.xml.
      2. Fully close Star Citizen and the RSI Launcher.
      3. Run this script.
      4. Launch SC and verify the MFD binds in Customization > Keybindings.

    A timestamped backup of actionmaps.xml is created before any change.

.PARAMETER InstallRoot
    Path to the Star Citizen install root that contains the LIVE / PTU / EPTU
    channel folders. Defaults to:
        C:\Program Files\Roberts Space Industries\StarCitizen

.PARAMETER Channel
    Apply the patch to only this channel. If omitted, you'll be prompted.

.EXAMPLE
    .\Fix MFD Binds [ENH][NXT].ps1
    Auto-detect channels, prompt to pick.

.EXAMPLE
    .\Fix MFD Binds [ENH][NXT].ps1 -Channel LIVE

.EXAMPLE
    .\Fix MFD Binds [ENH][NXT].ps1 -InstallRoot 'D:\Games\StarCitizen' -Channel PTU
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\Roberts Space Industries\StarCitizen',
    [ValidateSet('LIVE', 'PTU', 'EPTU', 'HOTFIX', 'TECH-PREVIEW')]
    [string]$Channel
)

$ErrorActionPreference = 'Stop'

# ===================================================================
#  STICK-SPECIFIC BIND DATA -- Gladiator NXT MFD layout
#  Do not edit unless you are customizing your own NXT MFD bindings.
# ===================================================================
$Binds = @(
    @{ name = 'v_mfd_interact_cycle_backwards_short'; input = 'js2_button54' }
    @{ name = 'v_mfd_interact_cycle_forwards_short';  input = 'js2_button52' }
    @{ name = 'v_mfd_movement_down_long';             input = 'js2_button53' }
    @{ name = 'v_mfd_movement_left_long';             input = 'js2_button54' }
    @{ name = 'v_mfd_movement_right_long';            input = 'js2_button52' }
    @{ name = 'v_mfd_movement_up_long';               input = 'js2_button51' }
    @{ name = 'v_mfd_quick_action_repair_all';        input = 'js2_button3'  }
    @{ name = 'v_mfd_soft_select_cast_left_short';    input = 'js2_button54'; multiTap = '2' }
    @{ name = 'v_mfd_soft_select_cast_right_short';   input = 'js2_button52'; multiTap = '2' }
)

$StickName = '[Enhanced] Dual VKB Gladiator NXT'

Write-Host ""
Write-Host "Fix MFD Binds -- $StickName" -ForegroundColor Cyan
Write-Host ("=" * 60)

# === Refuse if SC is running ===
$running = Get-Process -Name 'StarCitizen', 'RSI Launcher' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host ""
    Write-Host "Star Citizen / RSI Launcher is still running. Close it and re-run." -ForegroundColor Red
    Write-Host "Detected: $($running.ProcessName -join ', ')" -ForegroundColor Red
    exit 1
}

# === Validate install root ===
if (-not (Test-Path -LiteralPath $InstallRoot)) {
    Write-Host ""
    Write-Host "SC install root not found: $InstallRoot" -ForegroundColor Red
    Write-Host "If your install is elsewhere, re-run with:" -ForegroundColor Yellow
    Write-Host "  .\Fix MFD Binds [ENH][NXT].ps1 -InstallRoot 'X:\path\to\StarCitizen'" -ForegroundColor Yellow
    exit 1
}

# === Detect installed channels ===
$allChannels = @('LIVE', 'PTU', 'EPTU', 'HOTFIX', 'TECH-PREVIEW')
$installed = @($allChannels | Where-Object { Test-Path -LiteralPath (Join-Path $InstallRoot $_) })

if (-not $installed) {
    Write-Host ""
    Write-Host "No SC channel folders (LIVE/PTU/EPTU/...) found under:" -ForegroundColor Red
    Write-Host "  $InstallRoot" -ForegroundColor Red
    exit 1
}

# === Pick targets ===
if ($Channel) {
    if ($Channel -notin $installed) {
        Write-Host ""
        Write-Host "Channel '$Channel' not installed under $InstallRoot." -ForegroundColor Red
        Write-Host "Installed channels: $($installed -join ', ')" -ForegroundColor Yellow
        exit 1
    }
    $targets = @($Channel)
}
else {
    Write-Host ""
    Write-Host "Installed channels:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $installed.Count; $i++) {
        Write-Host "  [$($i + 1)] $($installed[$i])"
    }
    Write-Host "  [A]   All"
    $choice = (Read-Host "Pick").Trim()

    if ($choice -match '^[Aa]$') {
        $targets = $installed
    }
    elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $installed.Count) {
        $targets = @($installed[[int]$choice - 1])
    }
    else {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# === Patch each target ===
$totalUpdated = 0
$totalAdded = 0
$totalSkipped = 0

foreach ($ch in $targets) {
    $path = Join-Path $InstallRoot "$ch\user\client\0\Profiles\default\actionmaps.xml"

    Write-Host ""
    Write-Host "=== $ch ===" -ForegroundColor Cyan
    Write-Host "File: $path"

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "  actionmaps.xml not found. Load the layout in-game first, then re-run." -ForegroundColor Yellow
        $totalSkipped++
        continue
    }

    # === Read content (preserves CRLF and any BOM) ===
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $content = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)

    # === Locate vehicle_mfd actionmap block ===
    $mfdRegex = [regex]'(?s)<actionmap\s+name="vehicle_mfd"\s*>(.*?)</actionmap>'
    $mfdMatch = $mfdRegex.Match($content)

    if (-not $mfdMatch.Success) {
        Write-Host "  No vehicle_mfd actionmap in this file." -ForegroundColor Yellow
        Write-Host "  Load the [ENH][NXT] layout in-game first (Customization > Control Profiles)," -ForegroundColor Yellow
        Write-Host "  fully close SC, then re-run this script." -ForegroundColor Yellow
        $totalSkipped++
        continue
    }

    $blockBody = $mfdMatch.Groups[1].Value
    $blockBodyStart = $mfdMatch.Groups[1].Index
    $blockBodyLen = $mfdMatch.Groups[1].Length

    # Detect indentation from existing actions; fall back to 3-space if empty.
    $actionIndentMatch = [regex]::Match($blockBody, '(?m)^([ \t]+)<action\s')
    $actionIndent = if ($actionIndentMatch.Success) { $actionIndentMatch.Groups[1].Value } else { '   ' }

    $rebindIndentMatch = [regex]::Match($blockBody, '(?m)^([ \t]+)<rebind\s')
    $rebindIndent = if ($rebindIndentMatch.Success) { $rebindIndentMatch.Groups[1].Value } else { $actionIndent + ' ' }

    # === Apply each bind ===
    $newBlockBody = $blockBody
    $updated = 0
    $added = 0

    foreach ($b in $Binds) {
        $nameEsc = [regex]::Escape($b.name)
        $multiTapAttr = if ($b.ContainsKey('multiTap')) { ' multiTap="{0}"' -f $b.multiTap } else { '' }
        $newRebindTag = '<rebind input="{0}"{1}/>' -f $b.input, $multiTapAttr

        # Phase 1: try to update existing <action><rebind ... /></action> block
        $actionPattern = '(?s)(<action\s+name="{0}"\s*>\s*)<rebind[^/]*/>' -f $nameEsc
        $actionRegex = [regex]::new($actionPattern)
        $m = $actionRegex.Match($newBlockBody)
        if ($m.Success) {
            $prefix = $newBlockBody.Substring(0, $m.Index) + $m.Groups[1].Value
            $suffix = $newBlockBody.Substring($m.Index + $m.Length)
            $newBlockBody = $prefix + $newRebindTag + $suffix
            $updated++
        }
        else {
            # Phase 2: insert a new <action> after the last existing one,
            # before the trailing whitespace that precedes </actionmap>.
            $nl = "`r`n"
            $newAction = '{0}<action name="{1}">{2}{3}{4}{2}{0}</action>' -f $actionIndent, $b.name, $nl, $rebindIndent, $newRebindTag
            $lastClose = $newBlockBody.LastIndexOf('</action>')
            if ($lastClose -ge 0) {
                $insertAt = $lastClose + '</action>'.Length
                $newBlockBody = $newBlockBody.Substring(0, $insertAt) + "`r`n$newAction" + $newBlockBody.Substring($insertAt)
            }
            else {
                # actionmap is empty -- wrap the new action in newlines
                $newBlockBody = "`r`n$newAction" + $newBlockBody
            }
            $added++
        }
    }

    if ($updated -eq 0 -and $added -eq 0) {
        Write-Host "  Nothing to do (no matching actions found)." -ForegroundColor Yellow
        $totalSkipped++
        continue
    }

    # === Backup ===
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$path.bak-$stamp"
    Copy-Item -LiteralPath $path -Destination $backup -Force
    Write-Host "  Backup: $(Split-Path $backup -Leaf)"

    # === Reconstruct full content and write ===
    $newContent = $content.Substring(0, $blockBodyStart) + $newBlockBody + $content.Substring($blockBodyStart + $blockBodyLen)
    $enc = New-Object System.Text.UTF8Encoding $hasBom
    [System.IO.File]::WriteAllText($path, $newContent, $enc)

    Write-Host ("  Updated: {0,2}   Added: {1,2}" -f $updated, $added) -ForegroundColor Green
    $totalUpdated += $updated
    $totalAdded += $added
}

# === Summary ===
Write-Host ""
Write-Host ("-" * 60)
Write-Host ("Total: {0} updated, {1} added across {2} channel(s). Skipped: {3}." -f `
        $totalUpdated, $totalAdded, ($targets.Count - $totalSkipped), $totalSkipped) -ForegroundColor Green
Write-Host ""
Write-Host "Launch Star Citizen and verify the MFD binds in" -ForegroundColor Green
Write-Host "Customization > Keybindings > MFD." -ForegroundColor Green
Write-Host ""
