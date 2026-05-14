<#
.SYNOPSIS
    Bindings Toolkit for [Enhanced] Dual VKB Gladiator NXT. Menu-driven utility
    that handles the common Star Citizen binding maintenance tasks.

.DESCRIPTION
    Replaces the single-purpose "Fix MFD Binds" script. Same safety pattern
    (refuse to run while SC is alive, timestamped backups before every change,
    idempotent, preserves CRLF/BOM encoding) but exposes four operations
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

    The menu loops after each operation so you can chain (e.g. clear then fix
    MFD) in one session. Quit returns to the wrapper.

    WORKFLOW (typical case -- right after loading the NXT layout):
      1. Fully close Star Citizen and the RSI Launcher.
      2. Double-click "Bindings Toolkit [ENH][NXT][4.8.0][PTU].bat".
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
    Restore, Diagnostic, Prune. Useful for scripted / non-interactive runs.
    Clear, Restore, and Prune still prompt for the confirm step.

.EXAMPLE
    .\Bindings Toolkit [ENH][NXT][4.8.0][PTU].ps1
    Show the menu, prompt for channel as needed.

.EXAMPLE
    .\Bindings Toolkit [ENH][NXT][4.8.0][PTU].ps1 -Action MFD -Channel LIVE

.EXAMPLE
    .\Bindings Toolkit [ENH][NXT][4.8.0][PTU].ps1 -Action Invert -Channel PTU
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\Roberts Space Industries\StarCitizen',
    [ValidateSet('LIVE', 'PTU', 'EPTU', 'HOTFIX', 'TECH-PREVIEW')]
    [string]$Channel,
    [ValidateSet('MFD', 'Invert', 'Clear', 'Restore', 'Diagnostic', 'Prune')]
    [string]$Action
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

        $vjoyCount = ([regex]::Matches($content, '<deviceoptions\s+name="vJoy Device')).Count
        Write-Host "  vJoy device entries: $vjoyCount"

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

    $targets = Select-Channels -Installed $Installed -DefaultChannel $ChannelArg -AllowAll $true -Verb 'Show diagnostic report'
    if (-not $targets) { return }

    foreach ($ch in $targets) {
        $path = Get-ActionmapsPath -Root $Root -Ch $ch
        Write-Host ""
        Write-Host "=== $ch ===" -ForegroundColor Cyan
        Write-Host "  File: $path" -ForegroundColor Gray
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
#  MAIN
# =====================================================================

Write-Host ""
Write-Host "Bindings Toolkit -- $StickName" -ForegroundColor Cyan
Write-Host ("=" * 60)

# Refuse if SC / RSI Launcher running.
$running = Test-ScRunning
if ($running) {
    Write-Host ""
    Write-Host "Star Citizen / RSI Launcher is still running. Close it and re-run." -ForegroundColor Red
    Write-Host "Detected: $($running.ProcessName -join ', ')" -ForegroundColor Red
    exit 1
}

# Validate install root.
if (-not (Test-Path -LiteralPath $InstallRoot)) {
    Write-Host ""
    Write-Host "Star Citizen install not found at the default location:" -ForegroundColor Yellow
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
    if (-not (Test-Path -LiteralPath $entered)) {
        Write-Host ""
        Write-Host "Path not found: $entered" -ForegroundColor Red
        Write-Host "Re-run the script and try again, or pass it explicitly with:" -ForegroundColor Yellow
        Write-Host "  .\Bindings Toolkit [ENH][NXT][4.8.0][PTU].ps1 -InstallRoot 'X:\path\to\StarCitizen'" -ForegroundColor Yellow
        exit 1
    }
    $InstallRoot = $entered
    Write-Host ""
    Write-Host "Using install root: $InstallRoot" -ForegroundColor Green
}

# Detect installed channels.
$installed = Resolve-InstalledChannels -Root $InstallRoot
if (-not $installed) {
    Write-Host ""
    Write-Host "No SC channel folders (LIVE/PTU/EPTU/...) found under:" -ForegroundColor Red
    Write-Host "  $InstallRoot" -ForegroundColor Red
    exit 1
}

# Non-interactive single-action mode.
if ($Action) {
    switch ($Action) {
        'MFD'        { Invoke-FixMfd-Selection           -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Invert'     { Invoke-ResetInversions-Selection  -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Clear'      { Invoke-ClearAllBinds-Selection    -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Restore'    { Invoke-RestoreBackup-Selection    -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Diagnostic' { Invoke-ShowDiagnostic-Selection   -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
        'Prune'      { Invoke-PruneBackups-Selection     -Installed $installed -Root $InstallRoot -ChannelArg $Channel }
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
