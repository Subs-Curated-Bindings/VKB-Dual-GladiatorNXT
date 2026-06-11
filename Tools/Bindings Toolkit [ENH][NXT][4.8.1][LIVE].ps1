<#
.SYNOPSIS
    Bindings Toolkit for [Enhanced] Dual VKB Gladiator NXT. Menu-driven utility
    that handles the common Star Citizen binding maintenance tasks.

.DESCRIPTION
    Replaces the single-purpose "Fix MFD Binds" script. Same safety pattern
    (refuse to run while SC is alive, timestamped backups before every change,
    idempotent, preserves CRLF/BOM encoding) but exposes seven operations
    behind a menu:

      1. Fix MFD binds            -- reinjects the MFD binds SC's import wipes
      2. Reset axis inversions    -- strips custom invert overrides from
                                     actionmaps.xml so engine defaults reassert
      3. Clear all binds          -- deletes actionmaps.xml (destructive, with
                                     a typed-confirmation prompt and a backup)
      4. Restore from backup      -- picks a previous timestamped backup and
                                     copies it back over actionmaps.xml
      5. Show diagnostic report   -- read-only summary of actionmaps.xml state,
                                     MFD wipe status, and existing backups
      6. Prune old backups        -- delete older actionmaps.xml.bak-* files,
                                     keeping a configurable count of recent ones
      7. Non-EVO axis flip        -- flips the three response curves the non-EVO
                                     NXT base reports inverted (left stick X+Y
                                     and right stick Y). Edits the JG profile
                                     XML, not actionmaps.xml. EVO users skip.

    The menu loops after each operation so you can chain (e.g. clear then fix
    MFD) in one session. Quit returns to the wrapper.

    WORKFLOW (typical case -- right after loading the NXT layout):
      1. Fully close Star Citizen and the RSI Launcher.
      2. Double-click "Bindings Toolkit [ENH][NXT][4.8.1][LIVE].bat".
      3. Pick the channel (or All) and the operation.
      4. Launch SC, verify in Customization > Keybindings.

.PARAMETER InstallRoot
    Path to the Star Citizen install root that contains the LIVE / PTU / EPTU
    channel folders. Defaults to:
        C:\Program Files\Roberts Space Industries\StarCitizen

.PARAMETER Channel
    Apply to only this channel. Skips the channel prompt.

.PARAMETER Action
    Skip the menu and run a single operation. One of: MFD, Invert, Clear,
    Restore, Diagnostic, Prune, NonEvoFlip. Useful for scripted /
    non-interactive runs. Clear, Restore, Prune, and NonEvoFlip still
    prompt for the confirm step.

.PARAMETER ProfilePath
    Path to the JG R14 profile XML to operate on (used only by NonEvoFlip).
    Defaults to the profile sibling-of-this-script:
        ..\Joystick Gremlin Profile [ENH][NXT][4.8.1][LIVE][R14].xml
    Override if you've moved the profile into JG's own profiles folder.

.EXAMPLE
    .\Bindings Toolkit [ENH][NXT][4.8.1][LIVE].ps1
    Show the menu, prompt for channel as needed.

.EXAMPLE
    .\Bindings Toolkit [ENH][NXT][4.8.1][LIVE].ps1 -Action MFD -Channel LIVE

.EXAMPLE
    .\Bindings Toolkit [ENH][NXT][4.8.1][LIVE].ps1 -Action Invert -Channel PTU
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\Roberts Space Industries\StarCitizen',
    [ValidateSet('LIVE', 'PTU', 'EPTU', 'HOTFIX', 'TECH-PREVIEW')]
    [string]$Channel,
    [ValidateSet('MFD', 'Invert', 'Clear', 'Restore', 'Diagnostic', 'Prune', 'NonEvoFlip')]
    [string]$Action,
    [string]$ProfilePath
)

$ErrorActionPreference = 'Stop'

# =====================================================================
#  STICK-SPECIFIC DATA -- Gladiator NXT
#  When extending to another stick, change these two values and rename
#  the file. Everything below this block is shared logic.
# =====================================================================

$StickName = '[Enhanced] Dual VKB Gladiator NXT'

# MFD bind table. Each entry: name = SC action, input = vJoy button.
# Add multiTap = '2' for actions that need double-tap activation.
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

# =====================================================================
#  SHARED HELPERS
# =====================================================================

function Test-ScRunning {
    $running = Get-Process -Name 'StarCitizen', 'RSI Launcher' -ErrorAction SilentlyContinue
    return $running
}

function Resolve-InstalledChannels {
    param([string]$Root)
    $all = @('LIVE', 'PTU', 'EPTU', 'HOTFIX', 'TECH-PREVIEW')
    return @($all | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) })
}

function Get-ActionmapsPath {
    param([string]$Root, [string]$Ch)
    return Join-Path $Root "$Ch\user\client\0\Profiles\default\actionmaps.xml"
}

function New-TimestampedBackup {
    param([string]$Path)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$Path.bak-$stamp"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    return $backup
}

function Read-ActionmapsFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $content = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    return [PSCustomObject]@{ Content = $content; HasBom = $hasBom }
}

function Write-ActionmapsFile {
    param([string]$Path, [string]$Content, [bool]$HasBom)
    $enc = New-Object System.Text.UTF8Encoding $HasBom
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Select-Channels {
    param(
        [string[]]$Installed,
        [string]$DefaultChannel,
        [bool]$AllowAll,
        [string]$Verb
    )
    if ($DefaultChannel) {
        if ($DefaultChannel -in $Installed) { return @($DefaultChannel) }
        Write-Host "  Channel '$DefaultChannel' not installed." -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "  Installed channels:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Installed.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $Installed[$i])
    }
    if ($AllowAll) {
        Write-Host "    [A] All"
    }
    Write-Host "    [Q] Cancel"

    $prompt = if ($Verb) { "  Pick channel for $Verb" } else { "  Pick channel" }
    $choice = (Read-Host $prompt).Trim()

    if ($choice -match '^[Qq]$') { return $null }
    if ($AllowAll -and $choice -match '^[Aa]$') { return $Installed }
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Installed.Count) {
        return @($Installed[[int]$choice - 1])
    }
    Write-Host "  Unrecognized choice." -ForegroundColor Yellow
    return $null
}

# =====================================================================
#  OPERATION: FIX MFD BINDS
#  Refactored from the original Fix MFD Binds [ENH][NXT].ps1.
# =====================================================================

function Invoke-FixMfd-Channel {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  actionmaps.xml not found at this path." -ForegroundColor Yellow
        Write-Host "  Load the NXT layout in-game first (Customization > Control Profiles)," -ForegroundColor Yellow
        Write-Host "  close SC, then re-run." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-actionmaps'; Updated = 0; Added = 0 }
    }

    $file = Read-ActionmapsFile -Path $Path
    $content = $file.Content
    $hasBom = $file.HasBom

    $mfdRegex = [regex]'(?s)<actionmap\s+name="vehicle_mfd"\s*>(.*?)</actionmap>'
    $mfdMatch = $mfdRegex.Match($content)

    $updated = 0
    $added = 0

    if (-not $mfdMatch.Success) {
        # Phase 0 -- whole vehicle_mfd actionmap is missing. Build it.
        Write-Host "  vehicle_mfd actionmap missing -- inserting full block with all binds." -ForegroundColor Yellow

        $sibIndentMatch = [regex]::Match($content, '(?m)^([ \t]*)<actionmap\s+name="\w')
        $apIndent = if ($sibIndentMatch.Success) { $sibIndentMatch.Groups[1].Value } else { '  ' }
        $sibActionMatch = [regex]::Match($content, '(?ms)<actionmap\s+name="\w[^"]*"\s*>\s*\r?\n([ \t]+)<action\s')
        $actionIndent = if ($sibActionMatch.Success) { $sibActionMatch.Groups[1].Value } else { $apIndent + ' ' }
        $sibRebindMatch = [regex]::Match($content, '(?ms)<action[^>]*>\s*\r?\n([ \t]+)<rebind\s')
        $rebindIndent = if ($sibRebindMatch.Success) { $sibRebindMatch.Groups[1].Value } else { $actionIndent + ' ' }

        $nl = "`r`n"
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append("$apIndent<actionmap name=`"vehicle_mfd`">$nl")
        foreach ($b in $Binds) {
            $multiTapAttr = if ($b.ContainsKey('multiTap')) { ' multiTap="{0}"' -f $b.multiTap } else { '' }
            $rebindTag = '<rebind input="{0}"{1}/>' -f $b.input, $multiTapAttr
            [void]$sb.Append("$actionIndent<action name=`"$($b.name)`">$nl")
            [void]$sb.Append("$rebindIndent$rebindTag$nl")
            [void]$sb.Append("$actionIndent</action>$nl")
            $added++
        }
        [void]$sb.Append("$apIndent</actionmap>$nl")
        $newActionmap = $sb.ToString()

        $closeIdx = $content.LastIndexOf('</ActionProfiles>')
        if ($closeIdx -lt 0) {
            Write-Host "  Could not locate </ActionProfiles> closing tag; aborting." -ForegroundColor Red
            return [PSCustomObject]@{ Status = 'parse-error'; Updated = 0; Added = 0 }
        }
        $lineStart = $content.LastIndexOf("`n", $closeIdx) + 1
        $newContent = $content.Substring(0, $lineStart) + $newActionmap + $content.Substring($lineStart)
    }
    else {
        # Phase 1 + Phase 2 -- update existing rebinds, insert any missing actions.
        $blockBody = $mfdMatch.Groups[1].Value
        $blockBodyStart = $mfdMatch.Groups[1].Index
        $blockBodyLen = $mfdMatch.Groups[1].Length

        $actionIndentMatch = [regex]::Match($blockBody, '(?m)^([ \t]+)<action\s')
        $actionIndent = if ($actionIndentMatch.Success) { $actionIndentMatch.Groups[1].Value } else { '   ' }

        $rebindIndentMatch = [regex]::Match($blockBody, '(?m)^([ \t]+)<rebind\s')
        $rebindIndent = if ($rebindIndentMatch.Success) { $rebindIndentMatch.Groups[1].Value } else { $actionIndent + ' ' }

        $newBlockBody = $blockBody

        foreach ($b in $Binds) {
            $nameEsc = [regex]::Escape($b.name)
            $multiTapAttr = if ($b.ContainsKey('multiTap')) { ' multiTap="{0}"' -f $b.multiTap } else { '' }
            $newRebindTag = '<rebind input="{0}"{1}/>' -f $b.input, $multiTapAttr

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
                $nl = "`r`n"
                $newAction = '{0}<action name="{1}">{2}{3}{4}{2}{0}</action>' -f $actionIndent, $b.name, $nl, $rebindIndent, $newRebindTag
                $lastClose = $newBlockBody.LastIndexOf('</action>')
                if ($lastClose -ge 0) {
                    $insertAt = $lastClose + '</action>'.Length
                    $newBlockBody = $newBlockBody.Substring(0, $insertAt) + "`r`n$newAction" + $newBlockBody.Substring($insertAt)
                }
                else {
                    $newBlockBody = "`r`n$newAction" + $newBlockBody
                }
                $added++
            }
        }

        if ($updated -eq 0 -and $added -eq 0) {
            Write-Host "  Nothing to do (no matching actions found)." -ForegroundColor Yellow
            return [PSCustomObject]@{ Status = 'no-changes'; Updated = 0; Added = 0 }
        }

        $newContent = $content.Substring(0, $blockBodyStart) + $newBlockBody + $content.Substring($blockBodyStart + $blockBodyLen)
    }

    $backup = New-TimestampedBackup -Path $Path
    Write-Host "  Backup: $(Split-Path $backup -Leaf)" -ForegroundColor Gray
    Write-ActionmapsFile -Path $Path -Content $newContent -HasBom $hasBom
    Write-Host ("  Updated: {0,2}   Added: {1,2}" -f $updated, $added) -ForegroundColor Green

    return [PSCustomObject]@{ Status = 'ok'; Updated = $updated; Added = $added }
}

function Invoke-FixMfd-Selection {
    param([string[]]$Installed, [string]$Root, [string]$ChannelArg)

    $targets = Select-Channels -Installed $Installed -DefaultChannel $ChannelArg -AllowAll $true -Verb 'Fix MFD binds'
    if (-not $targets) { return }

    $totalUpdated = 0
    $totalAdded = 0
    foreach ($ch in $targets) {
        $path = Get-ActionmapsPath -Root $Root -Ch $ch
        Write-Host ""
        Write-Host "=== $ch ===" -ForegroundColor Cyan
        Write-Host "File: $path"
        $r = Invoke-FixMfd-Channel -Path $path
        $totalUpdated += $r.Updated
        $totalAdded += $r.Added
    }

    Write-Host ""
    Write-Host ("Done. {0} updated, {1} added across {2} channel(s)." -f $totalUpdated, $totalAdded, $targets.Count) -ForegroundColor Green
    Write-Host "Launch SC and verify Customization > Keybindings > MFD." -ForegroundColor Green
}

# =====================================================================
#  OPERATION: RESET AXIS INVERSIONS
#  Finds every <options type="joystick" instance="N" Product="..."> block
#  in actionmaps.xml and strips child elements whose attribute is invert=
#  "0" or invert="1". Blocks that end up empty collapse to self-closing.
#  Engine defaults reassert (mining_throttle + ground-vehicle move
#  forward/back remain inverted unless explicitly overridden).
# =====================================================================

function Invoke-ResetInversions-Channel {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  actionmaps.xml not found at this path." -ForegroundColor Yellow
        Write-Host "  Nothing to reset." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-actionmaps' }
    }

    $file = Read-ActionmapsFile -Path $Path
    $content = $file.Content
    $hasBom = $file.HasBom

    $pattern = '(?s)(<options\s+type="joystick"\s+instance="\d+"\s+Product="[^"]+")\s*(/>|>(.*?)</options>)'
    $matches = [regex]::Matches($content, $pattern)

    if ($matches.Count -eq 0) {
        Write-Host "  No <options type=`"joystick`"> blocks found." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-blocks' }
    }

    $invertLineRegex = '(?m)^[ \t]*<\w+\s+invert="[01]"\s*/>\s*\r?\n?'

    $sb = New-Object System.Text.StringBuilder
    $lastEnd = 0
    $totalRemoved = 0
    $totalCollapsed = 0
    $totalAlreadyClean = 0

    foreach ($m in $matches) {
        [void]$sb.Append($content.Substring($lastEnd, $m.Index - $lastEnd))

        $tail = $m.Groups[2].Value
        if ($tail -eq '/>') {
            # Already self-closing -- nothing to do, preserve verbatim.
            [void]$sb.Append($m.Value)
            $totalAlreadyClean++
        }
        else {
            $openTag = $m.Groups[1].Value
            $inner = $m.Groups[3].Value
            $removed = ([regex]::Matches($inner, $invertLineRegex)).Count
            $cleanedInner = [regex]::Replace($inner, $invertLineRegex, '')
            $totalRemoved += $removed

            if ($cleanedInner -match '^\s*$') {
                # All children stripped -- collapse to self-closing form.
                [void]$sb.Append($openTag + '/>')
                if ($removed -gt 0) { $totalCollapsed++ } else { $totalAlreadyClean++ }
            }
            else {
                # Some non-invert children remain (unexpected, but preserve them).
                [void]$sb.Append($openTag + '>' + $cleanedInner + '</options>')
            }
        }

        $lastEnd = $m.Index + $m.Length
    }
    [void]$sb.Append($content.Substring($lastEnd))

    if ($totalRemoved -eq 0) {
        Write-Host "  No invert overrides found in joystick options blocks." -ForegroundColor Yellow
        Write-Host "  Already at engine defaults -- nothing to do." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-changes'; Removed = 0 }
    }

    $backup = New-TimestampedBackup -Path $Path
    Write-Host "  Backup: $(Split-Path $backup -Leaf)" -ForegroundColor Gray
    Write-ActionmapsFile -Path $Path -Content $sb.ToString() -HasBom $hasBom

    Write-Host ("  Removed: {0} invert override(s) across {1} block(s)." -f $totalRemoved, $totalCollapsed) -ForegroundColor Green
    Write-Host "  Engine defaults reassert on next launch:" -ForegroundColor Gray
    Write-Host "    mining_throttle and ground-vehicle move forward/back stay inverted." -ForegroundColor Gray
    Write-Host "    Every other joystick axis is non-inverted." -ForegroundColor Gray
    return [PSCustomObject]@{ Status = 'ok'; Removed = $totalRemoved }
}

function Invoke-ResetInversions-Selection {
    param([string[]]$Installed, [string]$Root, [string]$ChannelArg)

    $targets = Select-Channels -Installed $Installed -DefaultChannel $ChannelArg -AllowAll $true -Verb 'Reset axis inversions'
    if (-not $targets) { return }

    foreach ($ch in $targets) {
        $path = Get-ActionmapsPath -Root $Root -Ch $ch
        Write-Host ""
        Write-Host "=== $ch ===" -ForegroundColor Cyan
        Write-Host "File: $path"
        [void](Invoke-ResetInversions-Channel -Path $path)
    }
}

# =====================================================================
#  OPERATION: CLEAR ALL BINDS
#  Backs up actionmaps.xml, then deletes it. SC regenerates from engine
#  defaults on next launch. The user must re-import a layout via SC's
#  Customization > Control Profiles to get binds back.
#  Single-channel only -- intentionally won't All-target.
# =====================================================================

function Invoke-ClearAllBinds-Channel {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  actionmaps.xml not found at this path." -ForegroundColor Yellow
        Write-Host "  Already in cleared state." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'already-clear' }
    }

    Write-Host ""
    Write-Host "  ACTION: Delete actionmaps.xml" -ForegroundColor Yellow
    Write-Host "  Path:   $Path" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  A backup will be created first." -ForegroundColor Gray
    Write-Host "  Restore at any time via menu option [4]." -ForegroundColor Gray
    Write-Host ""
    $confirm = Read-Host "  Type DELETE (uppercase) to confirm"
    if ($confirm -cne 'DELETE') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'cancelled' }
    }

    $backup = New-TimestampedBackup -Path $Path
    Write-Host "  Backup: $(Split-Path $backup -Leaf)" -ForegroundColor Gray
    Remove-Item -LiteralPath $Path -Force
    Write-Host "  Deleted." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    1. Launch Star Citizen." -ForegroundColor Cyan
    Write-Host "    2. Customization > Control Profiles > Use this profile -- pick the NXT layout." -ForegroundColor Cyan
    Write-Host "    3. Close SC, re-run this script with [1] to fix MFD binds." -ForegroundColor Cyan

    return [PSCustomObject]@{ Status = 'deleted'; BackupPath = $backup }
}

function Invoke-ClearAllBinds-Selection {
    param([string[]]$Installed, [string]$Root, [string]$ChannelArg)

    $targets = Select-Channels -Installed $Installed -DefaultChannel $ChannelArg -AllowAll $false -Verb 'Clear all binds'
    if (-not $targets) { return }

    foreach ($ch in $targets) {
        $path = Get-ActionmapsPath -Root $Root -Ch $ch
        Write-Host ""
        Write-Host "=== $ch ===" -ForegroundColor Cyan
        Write-Host "File: $path"
        [void](Invoke-ClearAllBinds-Channel -Path $path)
    }
}

# =====================================================================
#  OPERATION: RESTORE FROM BACKUP
#  Lists actionmaps.xml.bak-* files in the channel's Profiles\default\
#  directory, sorted newest first. User picks one. Current actionmaps.xml
#  (if present) is backed up before the restore so the restore itself is
#  reversible.
# =====================================================================

function Invoke-RestoreBackup-Channel {
    param([string]$Path)

    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Host "  Profiles directory not found." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-profile-dir' }
    }

    $backups = @(Get-ChildItem -LiteralPath $dir -Filter "actionmaps.xml.bak-*" -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending)

    if (-not $backups -or $backups.Count -eq 0) {
        Write-Host "  No backups found in this Profiles directory." -ForegroundColor Yellow
        Write-Host "  Backups are only created when this script runs -- nothing to restore." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-backups' }
    }

    Write-Host ""
    Write-Host "  Available backups (newest first):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
        $age = (Get-Date) - $b.LastWriteTime
        $ageStr = if ($age.TotalDays -ge 1) {
            "{0:N0}d ago" -f $age.TotalDays
        }
        elseif ($age.TotalHours -ge 1) {
            "{0:N0}h ago" -f $age.TotalHours
        }
        else {
            "{0:N0}m ago" -f $age.TotalMinutes
        }
        Write-Host ("    [{0,2}] {1}  ({2} KB, {3})" -f ($i + 1), $b.Name, [int]($b.Length / 1KB), $ageStr)
    }
    Write-Host "    [Q] Cancel"
    Write-Host ""

    $choice = (Read-Host "  Pick a backup to restore").Trim()
    if ($choice -match '^[Qq]$') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'cancelled' }
    }
    if (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $backups.Count) {
        Write-Host "  Unrecognized choice." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'cancelled' }
    }

    $picked = $backups[[int]$choice - 1]

    if (Test-Path -LiteralPath $Path) {
        $preRestoreBackup = New-TimestampedBackup -Path $Path
        Write-Host "  Pre-restore backup of current actionmaps.xml: $(Split-Path $preRestoreBackup -Leaf)" -ForegroundColor Gray
    }
    Copy-Item -LiteralPath $picked.FullName -Destination $Path -Force
    Write-Host "  Restored: $($picked.Name)" -ForegroundColor Green

    return [PSCustomObject]@{ Status = 'restored'; BackupRestored = $picked.Name }
}

function Invoke-RestoreBackup-Selection {
    param([string[]]$Installed, [string]$Root, [string]$ChannelArg)

    $targets = Select-Channels -Installed $Installed -DefaultChannel $ChannelArg -AllowAll $false -Verb 'Restore from backup'
    if (-not $targets) { return }

    foreach ($ch in $targets) {
        $path = Get-ActionmapsPath -Root $Root -Ch $ch
        Write-Host ""
        Write-Host "=== $ch ===" -ForegroundColor Cyan
        [void](Invoke-RestoreBackup-Channel -Path $path)
    }
}

# =====================================================================
#  STACK HEALTH HELPERS
#  Read-only probes for the wider stick stack: Joystick Gremlin install
#  location and runtime state, vJoy device presence, HidHide cloak
#  state. Surfaced in the diagnostic report so a single screenshot
#  carries enough signal for support without 3-app screenshots.
# =====================================================================

function Get-HidHideCliPath {
    $candidates = @(
        'C:\Program Files\Nefarius Software Solutions\HidHide\x64\HidHideCLI.exe',
        'C:\Program Files\Nefarius Software Solutions\HidHide\HidHideCLI.exe',
        "${env:ProgramFiles(x86)}\Nefarius Software Solutions\HidHide\x64\HidHideCLI.exe"
    )
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}

function Get-JoystickGremlinPaths {
    # Returns a de-duplicated list of joystick_gremlin.exe paths found via
    # any signal: running process, HidHide app-list, common install dirs.
    # Process / WMI lookups often return blank ExecutablePath when JG runs
    # at a different elevation than this script -- so we fall back to
    # HidHide's registered-app list (it remembers every JG ever launched
    # with HidHide cloaking) and a directory walk.
    $found = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($p in (Get-Process -Name joystick_gremlin -ErrorAction SilentlyContinue)) {
        try { if ($p.MainModule -and $p.MainModule.FileName) { [void]$found.Add($p.MainModule.FileName) } } catch {}
    }
    foreach ($wp in (Get-CimInstance Win32_Process -Filter "Name = 'joystick_gremlin.exe'" -ErrorAction SilentlyContinue)) {
        if ($wp.ExecutablePath) { [void]$found.Add($wp.ExecutablePath) }
    }

    $hh = Get-HidHideCliPath
    if ($hh) {
        try {
            $apps = & $hh --app-list 2>$null
            foreach ($line in $apps) {
                if ($line -match '"([^"]+joystick_gremlin\.exe)"') {
                    [void]$found.Add($Matches[1])
                }
            }
        } catch {}
    }

    $walkDirs = @(
        "$env:ProgramFiles\JoystickGremlin",
        "${env:ProgramFiles(x86)}\JoystickGremlin",
        "${env:ProgramFiles(x86)}\H2ik\Joystick Gremlin",
        "$env:LOCALAPPDATA\Programs\JoystickGremlin",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop"
    )
    foreach ($dir in $walkDirs) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -Filter 'joystick_gremlin.exe' -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                ForEach-Object { [void]$found.Add($_.FullName) }
        }
    }

    # Filter out paths that no longer exist (HidHide remembers deleted apps)
    return @($found) | Where-Object { Test-Path -LiteralPath $_ }
}

function Test-JoystickGremlinLocation {
    param([string]$Path)
    # Risk levels: 'ok' (green), 'warn' (yellow), 'err' (red)
    if ($Path -like "$env:USERPROFILE\Downloads\*") {
        return @{ Risk = 'warn'; Reason = "in Downloads -- Windows Storage Sense can auto-delete this after 30/60/90 days" }
    }
    if ($Path -like "$env:TEMP\*" -or $Path -like "$env:LOCALAPPDATA\Temp\*") {
        return @{ Risk = 'err'; Reason = "in %TEMP% -- WILL be wiped on cleanup" }
    }
    if ($Path -like '*\OneDrive\*' -or $Path -like '*\OneDrive - *' -or $Path -like '*\OneDrive_*') {
        return @{ Risk = 'warn'; Reason = "in OneDrive -- sync can corrupt a running exe or .xml profile mid-write" }
    }
    if ($Path -like "$env:USERPROFILE\Desktop\*") {
        return @{ Risk = 'warn'; Reason = "on Desktop -- easy to delete by accident; consider a permanent location" }
    }
    if ($Path -like "$env:ProgramFiles\*" -or $Path -like "${env:ProgramFiles(x86)}\*") {
        return @{ Risk = 'ok'; Reason = "Program Files install" }
    }
    if ($Path -like "$env:LOCALAPPDATA\Programs\*") {
        return @{ Risk = 'ok'; Reason = "per-user install (LocalAppData\Programs)" }
    }
    return @{ Risk = 'ok'; Reason = "custom location (no known risk)" }
}

function Test-JoystickGremlinRunning {
    return [bool](Get-Process -Name joystick_gremlin -ErrorAction SilentlyContinue)
}

function Get-VJoyStatus {
    # Returns @{ DriverLoaded; DeviceCount; DriverVersion }
    $driverLoaded = $false
    try {
        $driverLoaded = [bool](Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'vJoy' -and $_.Status -eq 'OK' })
    } catch {}
    $count = 0
    $paramsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\vjoy\Parameters'
    if (Test-Path $paramsPath) {
        $count = @(Get-ChildItem $paramsPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^Device\d+$' }).Count
    }
    # vJoy driver version lives on vjoy.sys (the user-mode DLL exports FileVersion
    # 0.0.0 -- it's the .sys driver that carries the real version string).
    $driverVersion = $null
    $sys = "$env:SystemRoot\System32\drivers\vjoy.sys"
    if (Test-Path -LiteralPath $sys) {
        $driverVersion = (Get-Item -LiteralPath $sys).VersionInfo.FileVersion
    }
    return @{ DriverLoaded = $driverLoaded; DeviceCount = $count; DriverVersion = $driverVersion }
}

function Get-HidHideAppList {
    # Returns the raw list of paths registered with HidHide's "allowed apps" list.
    param([string]$Cli)
    if (-not $Cli -or -not (Test-Path -LiteralPath $Cli)) { return @() }
    $out = @()
    try {
        & $Cli --app-list 2>&1 | ForEach-Object {
            if ($_ -match '--app-reg\s+"([^"]+)"') { $out += $Matches[1] }
        }
    } catch {}
    return ,$out
}

function Get-HidHideHiddenDevices {
    # Returns the list of device instance paths that HidHide is cloaking.
    param([string]$Cli)
    if (-not $Cli -or -not (Test-Path -LiteralPath $Cli)) { return @() }
    $out = @()
    try {
        & $Cli --dev-list 2>&1 | ForEach-Object {
            if ($_ -match '--dev-hide\s+"([^"]+)"') { $out += $Matches[1] }
        }
    } catch {}
    return ,$out
}

function Get-HidHideStatus {
    $cli = Get-HidHideCliPath
    if (-not $cli) { return @{ Installed = $false } }
    $svc = Get-Service -Name HidHide -ErrorAction SilentlyContinue
    $svcState = if ($svc) { $svc.Status.ToString() } else { 'unknown' }
    $cloak = 'unknown'
    $version = $null
    try {
        $raw = (& $cli --cloak-state 2>&1) -join "`n"
        if     ($raw -match '--cloak-on')  { $cloak = 'on' }
        elseif ($raw -match '--cloak-off') { $cloak = 'off' }
        $version = ((& $cli --version 2>&1) -join "`n").Trim()
    } catch {}
    $apps = Get-HidHideAppList -Cli $cli
    $hidden = Get-HidHideHiddenDevices -Cli $cli

    # Flag SC binaries in the app-list. SC should NEVER be in this list --
    # the whole point of HidHide is that SC ONLY sees vJoy, not the physical
    # sticks. Any SC binary here means physicals leak through and binds will
    # double-fire.
    $scBins = @('StarCitizen.exe', 'StarCitizen_Launcher.exe', 'RSI Launcher.exe', 'RSILauncher.exe')
    $scBypass = @($apps | Where-Object {
        $leaf = Split-Path -Leaf $_
        $scBins -contains $leaf
    })

    return @{
        Installed       = $true
        CliPath         = $cli
        ServiceState    = $svcState
        CloakState      = $cloak
        Version         = $version
        HiddenDevices   = $hidden.Count
        HiddenList      = $hidden
        RegisteredApps  = $apps.Count
        AppList         = $apps
        ScBypassApps    = $scBypass
    }
}

function Get-JoystickGremlinLoadedProfile {
    param([string]$ShippedProfile)
    # JG R14 puts the loaded profile path in its window title, format:
    #   "<full path>.xml - Joystick Gremlin[ R14.x]"  (version suffix optional)
    # That's the authoritative signal for what file JG has open right now --
    # works whether the user loaded the shipped profile or did Save As to a
    # different name/location. Also hash-compare the LOADED file's contents
    # against the shipped XML so we can distinguish "same content, different
    # path" (clean Save As copy) from "different content" (actual edits).
    $proc = Get-Process joystick_gremlin -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        return @{ JgRunning = $false }
    }
    $title = $proc.MainWindowTitle
    $loadedPath = $null
    if ($title -match '^(.+\.xml)\s+-\s+Joystick Gremlin') {
        $loadedPath = $Matches[1].Trim()
    }
    $shippedExists = (Test-Path -LiteralPath $ShippedProfile)
    $loadedExists  = ($loadedPath -and (Test-Path -LiteralPath $loadedPath))
    $pathMatchesShipped = $false
    $contentMatchesShipped = $false
    if ($loadedPath -and $shippedExists) {
        try {
            $shippedFull = [System.IO.Path]::GetFullPath($ShippedProfile)
            $loadedFull  = [System.IO.Path]::GetFullPath($loadedPath)
            $pathMatchesShipped = ($shippedFull -ieq $loadedFull)
        } catch {}
    }
    if ($loadedExists -and $shippedExists) {
        try {
            $h1 = (Get-FileHash -LiteralPath $loadedPath -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $ShippedProfile -Algorithm SHA256).Hash
            $contentMatchesShipped = ($h1 -eq $h2)
        } catch {}
    }
    return @{
        JgRunning             = $true
        TitleRaw              = $title
        LoadedPath            = $loadedPath
        LoadedExists          = $loadedExists
        PathMatchesShipped    = $pathMatchesShipped
        ContentMatchesShipped = $contentMatchesShipped
    }
}

# --- Tier 2 additions appended to STACK HEALTH HELPERS ----------------

function Get-ProfileDevices {
    param([string]$ProfilePath)
    # Parses the shipped JG profile's top-level <devices> block. Returns
    # objects with Name + Id for each physical-stick device entry. vJoy
    # and keyboard/mouse virtual devices are filtered out -- only the
    # entries that map to real sticks are surfaced.
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return @() }
    try {
        [xml]$doc = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8
    } catch { return @() }
    $out = @()
    foreach ($d in @($doc.profile.devices.device)) {
        $name = if ($d.'device-name') { $d.'device-name'.Trim() } else { '(unnamed)' }
        $id   = if ($d.'device-id')   { $d.'device-id'.Trim() }   else { '' }
        if ($name -match '^(vJoy|Keyboard|Mouse|VirtualKeyboard)') { continue }
        $out += [PSCustomObject]@{ Name = $name; Id = $id }
    }
    return ,$out
}

function Get-ConnectedVkbDevices {
    # VKB Sim vendor id is 231D. PnP enumerates each device twice (USB
    # surface + HID surface) so we dedupe by PID, which uniquely
    # identifies the stick model. Returns a hashtable: PID -> FriendlyName.
    $devs = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId -match 'VID_231D' -and $_.Status -eq 'OK'
    })
    $byPid = @{}
    foreach ($d in $devs) {
        if ($d.InstanceId -match 'PID_([0-9A-Fa-f]{4})') {
            $vkbPid = $Matches[1].ToUpper()
            if (-not $byPid.ContainsKey($vkbPid)) {
                $byPid[$vkbPid] = $d.FriendlyName
            }
        }
    }
    return $byPid
}

function Get-JoystickGremlinVersion {
    param([string]$ExePath)
    # JG R14 PyInstaller builds ship with empty VersionInfo metadata so
    # we fall back to a file-size + year heuristic. R13 ~ 2.4 MB / 2019,
    # R14 ~ 4 MB / 2026.
    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) {
        return @{ Major = $null; Display = '(exe not found)' }
    }
    $info = Get-Item -LiteralPath $ExePath
    $v = $info.VersionInfo.ProductVersion
    if (-not $v) { $v = $info.VersionInfo.FileVersion }
    if ($v -and ($v -match '^\s*(\d+)\.')) {
        return @{ Major = [int]$Matches[1]; Display = $v.Trim() }
    }
    $sizeMb = [math]::Round($info.Length / 1MB, 1)
    $year   = $info.LastWriteTime.Year
    if ($info.Length -gt 3500000) {
        return @{ Major = 14; Display = "R14.x heuristic ($sizeMb MB, $year)" }
    } elseif ($info.Length -gt 1500000) {
        return @{ Major = 13; Display = "R13.x heuristic ($sizeMb MB, $year)" }
    }
    return @{ Major = $null; Display = "unknown ($sizeMb MB, $year)" }
}

function Get-VkbConfiguratorPath {
    # Returns path to VKBDevCfg-C.exe if installed, $null otherwise.
    $candidates = @(
        'C:\Program Files\VKB Sim\VKBDevCfg\VKBDevCfg-C.exe',
        "${env:ProgramFiles(x86)}\VKB Sim\VKBDevCfg\VKBDevCfg-C.exe",
        'C:\Program Files\VKBsim\VKBDevCfg\VKBDevCfg-C.exe',
        "${env:ProgramFiles(x86)}\VKBsim\VKBDevCfg\VKBDevCfg-C.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-GameControllersVisibleToSC {
    # Approximates the joy.cpl device list -- i.e. what SC sees through
    # DirectInput. Computed as (raw HID-class game controllers currently
    # present) MINUS (devices HidHide is cloaking). vJoy collections show
    # up with instance ids like 'HID\HIDCLASS&COLnn\...' so we relabel
    # them as 'vJoy device N'; physical sticks get their friendly name
    # from the joy.cpl OEM friendly-name registry table.
    param([string[]]$HiddenInstanceIds)
    $raw = @(Get-PnpDevice -PresentOnly -Class HIDClass -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'OK' -and $_.FriendlyName -match 'game controller|joystick'
    })
    $hidden = if ($HiddenInstanceIds) { @($HiddenInstanceIds) } else { @() }

    $oemKey = 'HKCU:\System\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM'
    $out = @()
    foreach ($d in $raw) {
        $isHidden = $false
        foreach ($h in $hidden) {
            if ($d.InstanceId -ieq $h) { $isHidden = $true; break }
        }
        if ($isHidden) { continue }

        $label = $d.FriendlyName
        # vJoy collections
        if ($d.InstanceId -match 'HIDCLASS&COL(\d+)') {
            $label = "vJoy device (HIDCLASS COL$($Matches[1]))"
        }
        # OEM friendly name lookup for VID/PID devices
        elseif ($d.InstanceId -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
            $vp = "VID_$($Matches[1].ToUpper())&PID_$($Matches[2].ToUpper())"
            $oem = Get-ItemProperty -LiteralPath (Join-Path $oemKey $vp) -ErrorAction SilentlyContinue
            if ($oem -and $oem.OEMName) { $label = $oem.OEMName.Trim() + " ($vp)" }
            else { $label = "$($d.FriendlyName) ($vp)" }
        }
        $out += [PSCustomObject]@{ Label = $label; InstanceId = $d.InstanceId }
    }
    return ,$out
}

function Test-LayoutXmlForChannel {
    # Returns @{ Present; Path; SizeKB; MTime } -- the NXT layout file
    # that SC reads on import from <channel>\user\client\0\controls\mappings\
    param([string]$Root, [string]$Channel)
    $mappings = Join-Path $Root "$Channel\user\client\0\controls\mappings"
    if (-not (Test-Path -LiteralPath $mappings)) {
        return @{ Present = $false; Reason = 'controls\mappings dir missing' }
    }
    $found = @(Get-ChildItem -LiteralPath $mappings -Filter 'layout_ENH_NXT_*_exported.xml' -ErrorAction SilentlyContinue)
    if ($found.Count -eq 0) {
        return @{ Present = $false; Reason = 'no layout_ENH_NXT_*_exported.xml in mappings dir' }
    }
    $newest = $found | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return @{ Present = $true; Path = $newest.FullName; SizeKB = [int]($newest.Length / 1KB); MTime = $newest.LastWriteTime }
}

function Get-LegacyLayoutsForChannel {
    # Returns a list of .xml files in <channel>\user\client\0\controls\mappings\
    # that look like LEGACY clear-bindings or stale layouts the user should
    # remove. Pattern-matches the docs FAQ examples:
    #   - Hyphenated 'Clear-Bindings' (older spelling; current is underscored
    #     'Clear_Bindings')
    #   - Layouts lacking the _NNN_ patch token (pre-4.x naming)
    #   - layouts without an _exported suffix
    # We INTENTIONALLY don't flag the current-shipped layouts (ENH_<stick>_*
    # and SUB_Clear_Bindings_*) -- only ones that look like legacy leftovers.
    param([string]$Root, [string]$Channel)
    $mappings = Join-Path $Root "$Channel\user\client\0\controls\mappings"
    if (-not (Test-Path -LiteralPath $mappings)) { return @() }
    $all = @(Get-ChildItem -LiteralPath $mappings -Filter 'layout_*.xml' -ErrorAction SilentlyContinue)
    $legacy = @()
    foreach ($f in $all) {
        $n = $f.Name
        # Hyphenated old "Clear-Bindings" -- replaced 2026 by underscored form
        if ($n -match 'Clear-Bindings') { $legacy += $f; continue }
        # Anything missing _exported suffix isn't an SC-importable layout export
        if ($n -notmatch '_exported\.xml$') { $legacy += $f; continue }
        # No patch token (_NNN_) in older releases -- catch anything older than _400_
        if ($n -match 'layout_SUB_Clear_Bindings(_exported)?\.xml$') { $legacy += $f; continue }
    }
    return ,$legacy
}

function Get-StarCitizenInstalls {
    # Scans common drives for "<root>\Roberts Space Industries\StarCitizen"
    # directories that contain at least one channel subfolder (LIVE/PTU/...).
    # Multiple hits = multiple SC installs, which is a known support-case
    # since users edit the wrong one. Returns array of absolute paths.
    # We don't walk full drives (slow); we check the standard install roots
    # per drive letter that has any SC-looking folder.
    $channels = @('LIVE','PTU','EPTU','HOTFIX','TECH-PREVIEW')
    $roots = @()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Used -ne $null })) {
        $letter = $drive.Root  # e.g. 'C:\'
        $candidates = @(
            (Join-Path $letter 'Program Files\Roberts Space Industries\StarCitizen'),
            (Join-Path $letter 'Program Files (x86)\Roberts Space Industries\StarCitizen'),
            (Join-Path $letter 'Games\Roberts Space Industries\StarCitizen'),
            (Join-Path $letter 'Roberts Space Industries\StarCitizen'),
            (Join-Path $letter 'StarCitizen')
        )
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath $c) {
                # Check it has at least one channel subfolder; ignores empty shells
                $hasChannel = $false
                foreach ($ch in $channels) {
                    if (Test-Path -LiteralPath (Join-Path $c $ch)) { $hasChannel = $true; break }
                }
                if ($hasChannel) { $roots += $c }
            }
        }
    }
    return ,@($roots | Select-Object -Unique)
}


function Show-StackHealth {
    param([string]$ScriptRoot)

    Write-Host ""
    Write-Host "=== Stack health ===" -ForegroundColor Cyan

    # --- Joystick Gremlin: process state ---
    $jgRunning = Test-JoystickGremlinRunning
    if ($jgRunning) {
        Write-Host "  JG process: running" -ForegroundColor Green
        Write-Host "              (activation state can't be read from outside JG -- blue Activate icon must be ON for binds to fire)" -ForegroundColor Gray
    }
    else {
        Write-Host "  JG process: NOT running -- profile is not active until JG is launched + Activate" -ForegroundColor Yellow
    }

    # --- Joystick Gremlin: install location(s) + version ---
    $jgPaths = Get-JoystickGremlinPaths
    if (-not $jgPaths -or $jgPaths.Count -eq 0) {
        Write-Host "  JG install: not found on disk (check process / HidHide app-list / common install dirs)" -ForegroundColor Yellow
    }
    else {
        if ($jgPaths.Count -gt 1) {
            Write-Host ("  JG installs found: {0} -- multiple installs can cause version confusion (R13 vs R14)" -f $jgPaths.Count) -ForegroundColor Yellow
        }
        foreach ($path in $jgPaths) {
            $risk = Test-JoystickGremlinLocation -Path $path
            $ver  = Get-JoystickGremlinVersion -ExePath $path
            $colour = switch ($risk.Risk) { 'err' { 'Red' } 'warn' { 'Yellow' } default { 'Green' } }
            $label  = switch ($risk.Risk) { 'err' { 'BAD ' } 'warn' { 'WARN' } default { 'OK  ' } }
            Write-Host ("    [{0}] {1}" -f $label, $path) -ForegroundColor $colour
            Write-Host ("           version: {0} -- {1}" -f $ver.Display, $risk.Reason) -ForegroundColor Gray
            if ($ver.Major -eq 13) {
                Write-Host "           !! R13 cannot load R14 profiles -- update to R14.x or this profile won't open" -ForegroundColor Red
            }
        }
    }

    # --- JG's currently-loaded profile (parsed from window title) ---
    $shipped = Join-Path $ScriptRoot '..\Joystick Gremlin Profile [ENH][NXT][4.8.1][LIVE][R14].xml'
    $shipped = [System.IO.Path]::GetFullPath($shipped)
    $loaded = Get-JoystickGremlinLoadedProfile -ShippedProfile $shipped
    if (-not $loaded.JgRunning) {
        Write-Host "  JG loaded profile: (JG not running -- launch it + open the shipped profile to verify)" -ForegroundColor Gray
    }
    elseif (-not $loaded.LoadedPath) {
        Write-Host ("  JG loaded profile: JG running but title doesn't show a profile path") -ForegroundColor Yellow
        Write-Host ("                     title: '{0}'" -f $loaded.TitleRaw) -ForegroundColor Gray
        Write-Host  "                     open the shipped profile via File -> Open in JG" -ForegroundColor Gray
    }
    elseif ($loaded.PathMatchesShipped -and $loaded.ContentMatchesShipped) {
        Write-Host ("  JG loaded profile: {0}" -f $loaded.LoadedPath) -ForegroundColor Green
        Write-Host  "                     matches shipped profile (path + content)" -ForegroundColor Gray
    }
    elseif ($loaded.ContentMatchesShipped) {
        Write-Host ("  JG loaded profile: {0}" -f $loaded.LoadedPath) -ForegroundColor Green
        Write-Host  "                     content matches shipped profile (clean Save-As copy at a different path)" -ForegroundColor Gray
    }
    else {
        Write-Host ("  JG loaded profile: {0}" -f $loaded.LoadedPath) -ForegroundColor Yellow
        Write-Host  "                     content differs from shipped profile (customized / edited / different stick)" -ForegroundColor Gray
    }

    # --- Sticks: profile expectations vs connected VKB hardware (raw, pre-cloak) ---
    $profDevs = Get-ProfileDevices -ProfilePath $shipped
    $vkb      = Get-ConnectedVkbDevices
    $vkbPids  = @($vkb.Keys | Sort-Object)
    if ($profDevs.Count -eq 0) {
        Write-Host "  VKB hardware: profile declares no physical devices (check <devices> block in profile XML)" -ForegroundColor Yellow
    }
    elseif ($vkbPids.Count -eq 0) {
        Write-Host ("  VKB hardware: profile expects {0} VKB device(s), 0 connected -- plug them in, re-check" -f $profDevs.Count) -ForegroundColor Red
        foreach ($d in $profDevs) { Write-Host ("                expects: {0}" -f $d.Name) -ForegroundColor Gray }
    }
    else {
        $stickColour = if ($vkbPids.Count -ge $profDevs.Count) { 'Green' } else { 'Yellow' }
        Write-Host ("  VKB hardware: {0} stick(s) plugged in (PIDs: {1}); profile expects {2}" -f $vkbPids.Count, ($vkbPids -join ', '), $profDevs.Count) -ForegroundColor $stickColour
        foreach ($d in $profDevs) { Write-Host ("                expects: {0}" -f $d.Name) -ForegroundColor Gray }
        if ($vkbPids -notcontains '0200') {
            Write-Host "                note: no PID 0200 (EVO Premium base) detected -- if you're on a non-EVO" -ForegroundColor Yellow
            Write-Host "                      base, run [7] Non-EVO axis flip to invert L-X / L-Y / R-Y" -ForegroundColor Yellow
        }
    }

    # --- Game controllers visible to SC (HidHide-aware joy.cpl approximation) ---
    # NB: this runs AFTER we already have $hh; defer until HidHide block below
    # so we can pass its hidden-list in. Captured locally then printed below.

    # --- vJoy ---
    $vj = Get-VJoyStatus
    $vVer = if ($vj.DriverVersion) { "driver v$($vj.DriverVersion)" } else { 'driver version unknown' }
    if (-not $vj.DriverLoaded -and $vj.DeviceCount -eq 0) {
        Write-Host "  vJoy: not installed -- binds cannot reach SC without vJoy" -ForegroundColor Red
    }
    elseif (-not $vj.DriverLoaded) {
        Write-Host ("  vJoy: {0} but driver not loaded ({1} device(s) configured -- reinstall / restart needed)" -f $vVer, $vj.DeviceCount) -ForegroundColor Red
    }
    elseif ($vj.DeviceCount -lt 2) {
        Write-Host ("  vJoy: {0} loaded, {1} device(s) configured -- NXT profile expects 2 (use vJoyConf to add a second)" -f $vVer, $vj.DeviceCount) -ForegroundColor Yellow
    }
    else {
        Write-Host ("  vJoy: {0} loaded, {1} device(s) configured" -f $vVer, $vj.DeviceCount) -ForegroundColor Green
    }

    # --- HidHide ---
    $hh = Get-HidHideStatus
    if (-not $hh.Installed) {
        Write-Host "  HidHide: not installed -- SC may see physical sticks + vJoy together (binds double-fire)" -ForegroundColor Yellow
    }
    else {
        $svcColour = if ($hh.ServiceState -eq 'Running') { 'Green' } else { 'Yellow' }
        $hhVer = if ($hh.Version) { "v$($hh.Version)" } else { 'version unknown' }
        Write-Host ("  HidHide: $hhVer, service {0}, cloak {1}, {2} hidden device(s), {3} app(s) registered" -f $hh.ServiceState, $hh.CloakState, $hh.HiddenDevices, $hh.RegisteredApps) -ForegroundColor $svcColour
        if ($hh.CloakState -ne 'on') {
            Write-Host "    cloak is OFF -- physical sticks are visible to SC right now" -ForegroundColor Yellow
        }
        if ($hh.ScBypassApps -and $hh.ScBypassApps.Count -gt 0) {
            Write-Host "    !! SC binary is registered with HidHide -- REMOVE IT (SC seeing physicals double-fires binds):" -ForegroundColor Red
            foreach ($app in $hh.ScBypassApps) { Write-Host ("       $app") -ForegroundColor Red }
        }
    }

    # --- Game controllers visible to SC (joy.cpl approximation) ---
    $visible = Get-GameControllersVisibleToSC -HiddenInstanceIds $hh.HiddenList
    $vCount = $visible.Count
    if ($vCount -eq 0) {
        Write-Host "  Visible to SC: 0 game controllers (something is wrong -- vJoy should be visible at minimum)" -ForegroundColor Red
    }
    else {
        $vjoyVisible = @($visible | Where-Object { $_.Label -like 'vJoy device*' })
        $extras      = @($visible | Where-Object { $_.Label -notlike 'vJoy device*' })
        $vColour = if ($extras.Count -eq 0) { 'Green' } else { 'Yellow' }
        Write-Host ("  Visible to SC: {0} game controller(s) -- {1} vJoy + {2} other" -f $vCount, $vjoyVisible.Count, $extras.Count) -ForegroundColor $vColour
        foreach ($d in $visible) { Write-Host ("                 $($d.Label)") -ForegroundColor Gray }
        if ($extras.Count -gt 0) {
            Write-Host "                 ! the 'other' devices above will fight your binds -- unplug or add to HidHide cloak list" -ForegroundColor Yellow
        }
    }

    # --- VKB Configurator ---
    $vkbCfg = Get-VkbConfiguratorPath
    if ($vkbCfg) {
        Write-Host ("  VKB Configurator: installed -- {0}" -f $vkbCfg) -ForegroundColor Green
    }
    else {
        Write-Host "  VKB Configurator: not installed -- needed for firmware updates and stick-level config (download from vkbcontrollers.com)" -ForegroundColor Yellow
    }

    # --- SC installs: multiple = wrong-folder editing risk ---
    $scInstalls = Get-StarCitizenInstalls
    if ($scInstalls.Count -le 1) {
        if ($scInstalls.Count -eq 1) {
            Write-Host ("  SC installs: 1 (at {0})" -f $scInstalls[0]) -ForegroundColor Green
        }
        else {
            Write-Host "  SC installs: none found at known locations (RSI Launcher may have a custom path)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host ("  SC installs: {0} found -- you may be editing the WRONG one" -f $scInstalls.Count) -ForegroundColor Yellow
        foreach ($p in $scInstalls) { Write-Host ("                $p") -ForegroundColor Gray }
        Write-Host "                (RSI Launcher only points at one; use -InstallRoot to target the right path)" -ForegroundColor Gray
    }

    # --- Star Citizen runtime ---
    $sc = Test-ScRunning
    if ($sc) {
        Write-Host ("  Star Citizen: RUNNING ({0}) -- profile / layout / actionmaps changes won't apply until SC restarts" -f ($sc.ProcessName -join ', ')) -ForegroundColor Yellow
    }
    else {
        Write-Host "  Star Citizen: not running" -ForegroundColor Green
    }

    # --- This script's elevation (informational hint for the silent-mouse-aim trap) ---
    # SC and JG must run at the SAME elevation level or mouse-axis binds (mo1_*)
    # silently no-op. We can detect our own elevation but not SC's / JG's from a
    # non-elevated probe -- so this line is a hint, not an assertion.
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $amAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $elevTag = if ($amAdmin) { 'elevated (Administrator)' } else { 'not elevated' }
    Write-Host ("  This script: $elevTag -- if mouse-aim binds aren't firing, check that JG and SC run at the SAME elevation") -ForegroundColor Gray
}


# =====================================================================
#  OPERATION: SHOW DIAGNOSTIC REPORT
#  Read-only summary of the actionmaps.xml state for one or more
#  channels. Useful for support: paste this output into Discord so
#  someone can see what your live binds look like without screenshots.
# =====================================================================

function Invoke-ShowDiagnostic-Channel {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  actionmaps.xml: not present" -ForegroundColor Yellow
        Write-Host "  (channel is at SC engine defaults until a layout is loaded)" -ForegroundColor Gray
    }
    else {
        $info = Get-Item -LiteralPath $Path
        Write-Host ("  actionmaps.xml: {0} KB, modified {1}" -f [int]($info.Length / 1KB), $info.LastWriteTime)

        $content = (Read-ActionmapsFile -Path $Path).Content

        $rebindCount = ([regex]::Matches($content, '<rebind\s')).Count
        $unboundCount = ([regex]::Matches($content, '<rebind\s+input="(?:js[12]_|kb1_|mo1_|gp1_)\s*"')).Count
        Write-Host ("  Rebinds: {0} total ({1} unbound placeholders)" -f $rebindCount, $unboundCount)

        $invertCount = ([regex]::Matches($content, 'invert="[01]"')).Count
        Write-Host "  Invert overrides in joystick options: $invertCount"

        # Which vJoy slots does SC actually bind in this channel? Count distinct
        # jsN_ prefixes used in <rebind input="..."> across all action maps. The
        # old "<deviceoptions> count" metric was misleading -- SC only writes a
        # <deviceoptions> block when the user CUSTOMIZED something on that
        # device, so an all-defaults vJoy device left no trace and the count
        # under-reported. js1/js2 prefix presence in rebinds is the real signal.
        $js1Used = [regex]::IsMatch($content, '<rebind\s+input="js1_')
        $js2Used = [regex]::IsMatch($content, '<rebind\s+input="js2_')
        $slots = @()
        if ($js1Used) { $slots += 'js1' }
        if ($js2Used) { $slots += 'js2' }
        if ($slots.Count -eq 2) {
            Write-Host "  vJoy slots in use: js1 + js2 (both)" -ForegroundColor Green
        }
        elseif ($slots.Count -eq 1) {
            Write-Host ("  vJoy slots in use: {0} only -- NXT profile expects both js1 and js2" -f $slots[0]) -ForegroundColor Yellow
        }
        else {
            Write-Host "  vJoy slots in use: none -- no js1/js2 rebinds present (layout not imported?)" -ForegroundColor Yellow
        }

        $mfdMatch = [regex]::Match($content, '<actionmap\s+name="vehicle_mfd"\s*>([\s\S]*?)</actionmap>')
        if ($mfdMatch.Success) {
            $mfdBody = $mfdMatch.Groups[1].Value
            $mfdActions = ([regex]::Matches($mfdBody, '<action\s')).Count
            $mfdUnbound = ([regex]::Matches($mfdBody, '<rebind\s+input="js[12]_\s*"')).Count
            if ($mfdUnbound -gt 0) {
                Write-Host ("  vehicle_mfd: {0} actions, {1} unbound  [WIPED -- run [1] Fix MFD binds]" -f $mfdActions, $mfdUnbound) -ForegroundColor Yellow
            }
            else {
                Write-Host ("  vehicle_mfd: {0} actions, all bound  [OK]" -f $mfdActions) -ForegroundColor Green
            }
        }
        else {
            Write-Host "  vehicle_mfd: MISSING (full block dropped by SC) -- run [1] Fix MFD binds" -ForegroundColor Yellow
        }
    }

    # Backup summary
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (Test-Path -LiteralPath $dir) {
        $backups = @(Get-ChildItem -LiteralPath $dir -Filter "actionmaps.xml.bak-*" -ErrorAction SilentlyContinue)
        if ($backups.Count -gt 0) {
            $newest = ($backups | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            $totalSize = ($backups | Measure-Object -Property Length -Sum).Sum
            Write-Host ("  Backups: {0} file(s), {1} KB total, newest {2}" -f $backups.Count, [int]($totalSize / 1KB), $newest)
        }
        else {
            Write-Host "  Backups: none"
        }
    }

    return [PSCustomObject]@{ Status = 'ok' }
}

function Invoke-ShowDiagnostic-Selection {
    param([string[]]$Installed, [string]$Root, [string]$ChannelArg)

    Show-StackHealth -ScriptRoot $PSScriptRoot

    $targets = Select-Channels -Installed $Installed -DefaultChannel $ChannelArg -AllowAll $true -Verb 'Show diagnostic report'
    if (-not $targets) { return }

    foreach ($ch in $targets) {
        $path = Get-ActionmapsPath -Root $Root -Ch $ch
        Write-Host ""
        Write-Host "=== $ch ===" -ForegroundColor Cyan
        Write-Host "  File: $path" -ForegroundColor Gray

        # Layout XML presence (the file SC imports via Control Profiles)
        $layout = Test-LayoutXmlForChannel -Root $Root -Channel $ch
        if ($layout.Present) {
            Write-Host ("  Layout XML: present ({0} KB, modified {1})" -f $layout.SizeKB, $layout.MTime) -ForegroundColor Green

            # Mtime drift: if layout XML is NEWER than actionmaps.xml, SC
            # hasn't re-imported since the layout was last edited. Catches the
            # "I updated the layout but SC still shows old binds" case.
            if (Test-Path -LiteralPath $path) {
                $amInfo = Get-Item -LiteralPath $path
                if ($layout.MTime -gt $amInfo.LastWriteTime) {
                    $skew = New-TimeSpan -Start $amInfo.LastWriteTime -End $layout.MTime
                    $when = if ($skew.TotalDays -ge 1) { "{0:N0}d" -f $skew.TotalDays } elseif ($skew.TotalHours -ge 1) { "{0:N0}h" -f $skew.TotalHours } else { "{0:N0}m" -f $skew.TotalMinutes }
                    Write-Host ("              !! layout is $when newer than actionmaps -- SC hasn't re-imported since the layout was last edited") -ForegroundColor Yellow
                    Write-Host  "                 (re-import in SC -> Control Profiles, OR run with -Action MFD/etc to push via this toolkit)" -ForegroundColor Gray
                }
            }
        }
        else {
            Write-Host ("  Layout XML: MISSING -- {0}" -f $layout.Reason) -ForegroundColor Yellow
            Write-Host  "              (SC -> Options -> Keybindings -> Control Profiles -> Import to load it)" -ForegroundColor Gray
        }

        # Legacy / stale layout files in the same mappings dir -- catches
        # users who imported an old Clear-Bindings or pre-4xx file.
        $legacy = Get-LegacyLayoutsForChannel -Root $Root -Channel $ch
        if ($legacy.Count -gt 0) {
            Write-Host ("  Legacy layouts: {0} stale file(s) in controls\mappings\ -- consider removing:" -f $legacy.Count) -ForegroundColor Yellow
            foreach ($f in $legacy) { Write-Host ("                  {0}" -f $f.Name) -ForegroundColor Gray }
        }

        [void](Invoke-ShowDiagnostic-Channel -Path $path)
    }
}

# =====================================================================
#  OPERATION: PRUNE OLD BACKUPS
#  Lists actionmaps.xml.bak-* files in the channel's Profiles\default\
#  directory, asks how many to keep, deletes the rest after confirmation.
#  Per-channel: same keep count applies to each chosen channel.
# =====================================================================

function Invoke-PruneBackups-Channel {
    param([string]$Path)

    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Host "  Profiles directory not found." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-profile-dir' }
    }

    $backups = @(Get-ChildItem -LiteralPath $dir -Filter "actionmaps.xml.bak-*" -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending)

    if ($backups.Count -eq 0) {
        Write-Host "  No backups found -- nothing to prune." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-backups' }
    }

    Write-Host ""
    Write-Host "  Found $($backups.Count) backup(s)." -ForegroundColor Cyan
    $keepStr = (Read-Host "  How many most-recent backups to keep? [default 10]").Trim()
    if ([string]::IsNullOrEmpty($keepStr)) {
        $keep = 10
    }
    elseif ($keepStr -match '^\d+$') {
        $keep = [int]$keepStr
    }
    else {
        Write-Host "  Invalid number. Cancelled." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'invalid-input' }
    }

    if ($backups.Count -le $keep) {
        Write-Host "  Already at or under the keep limit ($keep). Nothing to prune." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'no-prune-needed' }
    }

    $toDelete = @($backups | Select-Object -Skip $keep)
    $totalSize = ($toDelete | Measure-Object -Property Length -Sum).Sum

    Write-Host ""
    Write-Host ("  Will delete the {0} oldest backup(s), reclaiming {1} KB:" -f $toDelete.Count, [int]($totalSize / 1KB)) -ForegroundColor Yellow
    foreach ($b in $toDelete) {
        Write-Host ("    - {0}  ({1} KB, {2})" -f $b.Name, [int]($b.Length / 1KB), $b.LastWriteTime)
    }
    Write-Host ""
    $confirm = Read-Host "  Type DELETE (uppercase) to confirm"
    if ($confirm -cne 'DELETE') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return [PSCustomObject]@{ Status = 'cancelled' }
    }

    $deleted = 0
    foreach ($b in $toDelete) {
        Remove-Item -LiteralPath $b.FullName -Force
        $deleted++
    }
    Write-Host ("  Deleted: {0} backup(s), {1} KB reclaimed." -f $deleted, [int]($totalSize / 1KB)) -ForegroundColor Green
    return [PSCustomObject]@{ Status = 'pruned'; Deleted = $deleted }
}

function Invoke-PruneBackups-Selection {
    param([string[]]$Installed, [string]$Root, [string]$ChannelArg)

    $targets = Select-Channels -Installed $Installed -DefaultChannel $ChannelArg -AllowAll $true -Verb 'Prune old backups'
    if (-not $targets) { return }

    foreach ($ch in $targets) {
        $path = Get-ActionmapsPath -Root $Root -Ch $ch
        Write-Host ""
        Write-Host "=== $ch ===" -ForegroundColor Cyan
        Write-Host "  Profile dir: $([System.IO.Path]::GetDirectoryName($path))" -ForegroundColor Gray
        [void](Invoke-PruneBackups-Channel -Path $path)
    }
}

# =====================================================================
#  OPERATION: NON-EVO AXIS FLIP
#  Edits the JG profile XML (not actionmaps.xml). Flips the response
#  curves on left stick X+Y and right stick Y, which the non-EVO NXT
#  base reports inverted relative to the EVO base.
#
#  Acts as a toggle -- running twice returns each curve to its prior
#  state. Curve detection is by Y-negate of every control point, so
#  it works on flat curves AND shaped curves equally.
# =====================================================================

function Test-JgRunning {
    return Get-Process -Name 'joystick_gremlin' -ErrorAction SilentlyContinue
}

function Invoke-NonEvoAxisFlip-Profile {
    param([string]$ProfilePath)

    # Resolve default profile path if caller didn't supply one.
    if (-not $ProfilePath) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $default = Join-Path (Split-Path -Parent $scriptDir) 'Joystick Gremlin Profile [ENH][NXT][4.8.1][LIVE][R14].xml'
        $ProfilePath = $default
    }

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        Write-Host ""
        Write-Host "  JG profile not found at:" -ForegroundColor Red
        Write-Host "    $ProfilePath" -ForegroundColor Red
        Write-Host ""
        Write-Host "  If you moved the profile, re-run with:" -ForegroundColor Yellow
        Write-Host "    .\Bindings Toolkit [ENH][NXT][4.8.1][LIVE].ps1 -Action NonEvoFlip -ProfilePath '<path>'" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Non-EVO axis flip" -ForegroundColor Cyan
    Write-Host "  -----------------" -ForegroundColor Cyan
    Write-Host "  This flips the response curves on three axes that the non-EVO NXT"
    Write-Host "  base reports inverted: left stick X, left stick Y, right stick Y."
    Write-Host "  Running this on EVO hardware will INVERT axes that were working"
    Write-Host "  correctly, so only proceed if you're on a non-EVO base."
    Write-Host ""
    Write-Host "  Profile: $ProfilePath" -ForegroundColor Gray
    Write-Host ""

    # Refuse if JG is open (the file save would race with JG's in-memory copy).
    if (Test-JgRunning) {
        Write-Host "  Joystick Gremlin is running. Close it first so this edit doesn't" -ForegroundColor Red
        Write-Host "  race with JG's in-memory copy of the profile." -ForegroundColor Red
        return
    }

    # Confirm hardware.
    $confirm = (Read-Host "  Are you on a non-EVO NXT base? (y/N)").Trim().ToLower()
    if ($confirm -ne 'y' -and $confirm -ne 'yes') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }

    # Parse XML to find devices and the target action UUIDs.
    try {
        [xml]$doc = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8
    } catch {
        Write-Host "  Could not parse profile XML: $_" -ForegroundColor Red
        return
    }

    $devices = @($doc.profile.devices.device)
    # Strip Logitech / vJoy entries -- only NXT-shaped devices are candidates.
    $deviceCandidates = @($devices | Where-Object {
        $_.'device-name' -and ($_.'device-name'.Trim() -notmatch '^(vJoy|Logitech|Keyboard|Mouse)')
    })

    if ($deviceCandidates.Count -lt 2) {
        Write-Host "  Profile lists fewer than 2 stick devices. Run Tools -> Swap Devices in JG first." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  Stick devices in the profile:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $deviceCandidates.Count; $i++) {
        $name = $deviceCandidates[$i].'device-name'.Trim()
        $id = $deviceCandidates[$i].'device-id'
        Write-Host ("    [{0}] {1}    ({2})" -f ($i + 1), $name, $id)
    }
    Write-Host ""

    $leftPick = (Read-Host "  Which device is your LEFT NXT? (number)").Trim()
    if (-not ($leftPick -match '^\d+$') -or [int]$leftPick -lt 1 -or [int]$leftPick -gt $deviceCandidates.Count) {
        Write-Host "  Unrecognized choice." -ForegroundColor Yellow; return
    }
    $leftId = $deviceCandidates[[int]$leftPick - 1].'device-id'

    $rightPick = (Read-Host "  Which device is your RIGHT NXT? (number)").Trim()
    if (-not ($rightPick -match '^\d+$') -or [int]$rightPick -lt 1 -or [int]$rightPick -gt $deviceCandidates.Count) {
        Write-Host "  Unrecognized choice." -ForegroundColor Yellow; return
    }
    $rightId = $deviceCandidates[[int]$rightPick - 1].'device-id'

    if ($leftId -eq $rightId) {
        Write-Host "  Left and right cannot be the same device. Cancelled." -ForegroundColor Red; return
    }

    # Build action lookup maps.
    $libActions = @{}
    foreach ($a in $doc.profile.library.action) { $libActions[$a.id] = $a }

    # The three target physical axes. Input IDs follow the VKB convention:
    # X = 1, Y = 2, Z = 3. (Z is the slider/throttle and is NOT inverted.)
    $targets = @(
        @{ DeviceId = $leftId;  InputId = '1'; Label = 'Left stick X axis'  }
        @{ DeviceId = $leftId;  InputId = '2'; Label = 'Left stick Y axis'  }
        @{ DeviceId = $rightId; InputId = '2'; Label = 'Right stick Y axis' }
    )

    # Collect the response-curve action UUIDs to flip.
    $rcUuids = @{}   # uuid -> array of labels that pointed to it (for the summary)
    foreach ($t in $targets) {
        $matches = @($doc.profile.inputs.input | Where-Object {
            $_.'device-id' -eq $t.DeviceId -and
            $_.'input-id'  -eq $t.InputId  -and
            $_.'input-type' -eq 'axis'
        })
        if ($matches.Count -eq 0) {
            Write-Host "  WARNING: no axis input found for $($t.Label)." -ForegroundColor Yellow
            continue
        }
        foreach ($inp in $matches) {
            foreach ($ac in @($inp.'action-configuration')) {
                if ($ac.behavior -ne 'axis') { continue }
                $rootAid = $ac.'root-action'
                $root = $libActions[$rootAid]
                if (-not $root) { continue }
                foreach ($aidNode in @($root.actions.'action-id')) {
                    $childId = if ($aidNode.'#text') { $aidNode.'#text' } else { [string]$aidNode }
                    $childId = $childId.Trim()
                    $child = $libActions[$childId]
                    if ($child -and $child.type -eq 'response-curve') {
                        if (-not $rcUuids.ContainsKey($childId)) { $rcUuids[$childId] = @() }
                        $rcUuids[$childId] += "$($t.Label) ($($inp.mode))"
                    }
                }
            }
        }
    }

    if ($rcUuids.Count -eq 0) {
        Write-Host ""
        Write-Host "  No response curves found on the target axes. Nothing to do." -ForegroundColor Yellow
        Write-Host "  (Did you load the wrong profile, or pick the wrong left/right device?)" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Found $($rcUuids.Count) response curve(s) to toggle:" -ForegroundColor Cyan
    foreach ($uuid in $rcUuids.Keys) {
        Write-Host "    $($uuid.Substring(0,8))..  ->  $($rcUuids[$uuid] -join '; ')"
    }
    Write-Host ""
    Write-Host "  Note: each run toggles. Run twice to undo." -ForegroundColor Gray
    Write-Host ""
    $go = (Read-Host "  Proceed with the flip? (y/N)").Trim().ToLower()
    if ($go -ne 'y' -and $go -ne 'yes') {
        Write-Host "  Cancelled." -ForegroundColor Yellow; return
    }

    # Backup.
    $backup = New-TimestampedBackup -Path $ProfilePath
    Write-Host "  Backed up profile to:" -ForegroundColor DarkGray
    Write-Host "    $backup" -ForegroundColor DarkGray

    # Read raw text (preserving BOM) so the regex edits keep JG's formatting intact.
    $file = Read-ActionmapsFile -Path $ProfilePath   # same UTF-8 + BOM handling
    $text = $file.Content

    $flippedActions = 0
    $flippedPoints = 0
    foreach ($uuid in $rcUuids.Keys) {
        # Locate the action block.
        $blockStart = $text.IndexOf("<action id=`"$uuid`" type=`"response-curve`">")
        if ($blockStart -lt 0) {
            Write-Host "    skip: $($uuid.Substring(0,8)) not found in raw text" -ForegroundColor Yellow
            continue
        }
        # Find matching </action> after blockStart.
        $blockEnd = $text.IndexOf("</action>", $blockStart)
        if ($blockEnd -lt 0) { continue }
        $blockEnd += "</action>".Length

        $block = $text.Substring($blockStart, $blockEnd - $blockStart)

        # Locate the <control-points>...</control-points> region within the block.
        $cpStart = $block.IndexOf("<control-points>")
        $cpEnd = $block.IndexOf("</control-points>")
        if ($cpStart -lt 0 -or $cpEnd -lt 0) { continue }
        $cpRegion = $block.Substring($cpStart, $cpEnd - $cpStart)

        # Within control-points, negate the Y of every <value>X,Y</value>.
        $newCpRegion = [regex]::Replace(
            $cpRegion,
            '<value>([-0-9.]+),([-0-9.]+)</value>',
            {
                param($m)
                $x = $m.Groups[1].Value
                $y = [double]$m.Groups[2].Value
                $negY = -$y
                $script:flippedPoints++
                # Format like '-1.0' / '1.0' (JG's style) -- one decimal place,
                # no scientific notation, '-0' collapsed to '0'.
                if ($negY -eq 0) { $negStr = '0.0' }
                else { $negStr = $negY.ToString('0.0##############', [System.Globalization.CultureInfo]::InvariantCulture) }
                "<value>$x,$negStr</value>"
            }
        )

        $newBlock = $block.Substring(0, $cpStart) + $newCpRegion + $block.Substring($cpEnd)
        $text = $text.Substring(0, $blockStart) + $newBlock + $text.Substring($blockEnd)
        $flippedActions++
    }

    Write-ActionmapsFile -Path $ProfilePath -Content $text -HasBom $file.HasBom

    # Sanity-parse the result.
    try {
        $null = [xml](Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8)
    } catch {
        Write-Host "  ERROR: result file failed XML parse. Restoring from backup." -ForegroundColor Red
        Copy-Item -LiteralPath $backup -Destination $ProfilePath -Force
        return
    }

    Write-Host ""
    Write-Host "  Flipped $flippedActions response curve(s), $flippedPoints control-point Y value(s) total." -ForegroundColor Green
    Write-Host "  Re-open the profile in JG R14 to see the change." -ForegroundColor Gray
    return [PSCustomObject]@{ Status = 'flipped'; Actions = $flippedActions; Points = $flippedPoints }
}

function Invoke-NonEvoAxisFlip-Selection {
    param([string]$ProfilePathArg)
    [void](Invoke-NonEvoAxisFlip-Profile -ProfilePath $ProfilePathArg)
}

# =====================================================================
#  MAIN
# =====================================================================

Write-Host ""
Write-Host "Bindings Toolkit -- $StickName" -ForegroundColor Cyan
Write-Host ("=" * 60)

# Refuse if SC / RSI Launcher running -- except for the read-only Diagnostic
# action, which doesn't touch any file SC has open and just reports state.
$running = Test-ScRunning
if ($running -and $Action -ne 'Diagnostic') {
    Write-Host ""
    Write-Host "Star Citizen / RSI Launcher is still running. Close it and re-run." -ForegroundColor Red
    Write-Host "Detected: $($running.ProcessName -join ', ')" -ForegroundColor Red
    Write-Host "(The Diagnostic action is read-only and can be run with SC open: -Action Diagnostic)" -ForegroundColor Gray
    exit 1
}

# Validate install root + detect channels in one loop. Either failure
# mode (path missing OR path exists but no LIVE/PTU/EPTU subfolders)
# drops back into the prompt rather than exiting. Earlier versions
# bailed in the second case without re-prompting -- users with a
# launcher-created shell folder on C: but the actual install on
# another drive got stuck.
$installed = $null
while (-not $installed) {
    $pathOk = Test-Path -LiteralPath $InstallRoot
    if ($pathOk) {
        $installed = Resolve-InstalledChannels -Root $InstallRoot
        if ($installed) { break }
    }

    Write-Host ""
    if (-not $pathOk) {
        Write-Host "Star Citizen install folder not found:" -ForegroundColor Yellow
    }
    else {
        Write-Host "No SC channel folders (LIVE/PTU/EPTU/...) found under:" -ForegroundColor Yellow
    }
    Write-Host "  $InstallRoot" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If your install is on a different drive, enter its path now."
    Write-Host "(The folder that contains LIVE / PTU / EPTU subfolders.)"
    Write-Host "Example: D:\Games\Roberts Space Industries\StarCitizen"
    Write-Host ""
    $entered = (Read-Host "  Install path (or blank to cancel)").Trim().Trim('"').Trim("'")
    if (-not $entered) {
        Write-Host "Cancelled." -ForegroundColor Red
        exit 1
    }
    $InstallRoot = $entered
}

Write-Host ""
Write-Host "Using install root: $InstallRoot" -ForegroundColor Green

# Non-interactive single-action mode.
if ($Action) {
    switch ($Action) {
        'MFD'        { Invoke-FixMfd-Selection           -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Invert'     { Invoke-ResetInversions-Selection  -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Clear'      { Invoke-ClearAllBinds-Selection    -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Restore'    { Invoke-RestoreBackup-Selection    -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Diagnostic' { Invoke-ShowDiagnostic-Selection   -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Prune'      { Invoke-PruneBackups-Selection     -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'NonEvoFlip' { Invoke-NonEvoAxisFlip-Selection   -ProfilePathArg $ProfilePath }
    }
    Write-Host ""
    exit 0
}

# Interactive menu loop.
$keepRunning = $true
while ($keepRunning) {
    Write-Host ""
    Write-Host "What do you want to do?" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Fix MFD binds            -- reinjects the MFD binds SC's import wipes"
    Write-Host "  [2] Reset axis inversions    -- strip custom invert overrides (engine defaults reassert)"
    Write-Host "  [3] Clear all binds          -- delete actionmaps.xml (destructive, single channel)"
    Write-Host "  [4] Restore from backup      -- pick a previous backup to restore (single channel)"
    Write-Host "  [5] Show diagnostic report   -- read-only summary of current binds + backups"
    Write-Host "  [6] Prune old backups        -- delete old actionmaps.xml.bak-* files"
    Write-Host "  [7] Non-EVO axis flip        -- flip the 3 axes the non-EVO NXT reports inverted"
    Write-Host "  [Q] Quit"
    Write-Host ""

    $pick = (Read-Host "Pick").Trim().ToUpper()
    switch ($pick) {
        '1' { Invoke-FixMfd-Selection          -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        '2' { Invoke-ResetInversions-Selection -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        '3' { Invoke-ClearAllBinds-Selection   -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        '4' { Invoke-RestoreBackup-Selection   -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        '5' { Invoke-ShowDiagnostic-Selection  -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        '6' { Invoke-PruneBackups-Selection    -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        '7' { Invoke-NonEvoAxisFlip-Selection  -ProfilePathArg $ProfilePath }
        'Q' { $keepRunning = $false }
        default { Write-Host "Unrecognized choice." -ForegroundColor Yellow }
    }

    if ($keepRunning) {
        Write-Host ""
        [void](Read-Host "Press Enter to return to the menu")
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""
