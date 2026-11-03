<#
  逃离鸭科夫 · 联机 Mod「独立分图版」安装器

  用法（在 PowerShell 里执行）：
      powershell -ExecutionPolicy Bypass -File .\install.ps1                 安装（默认自动上锁）
      powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoLock         安装但不上锁
      powershell -ExecutionPolicy Bypass -File .\install.ps1 -Action Status  查看当前状态
      powershell -ExecutionPolicy Bypass -File .\install.ps1 -Action Unlock  解锁（让 Steam 能更新）
      powershell -ExecutionPolicy Bypass -File .\install.ps1 -Action Restore 还原安装前的文件

  它会做三件事：
    1) 把 files\ 里的 DLL 与语言文件覆盖到你已订阅的创意工坊 Mod 目录
    2) 把 EscapeFromDuckovModApi.dll 同步到 游戏\Duckov_Data\Managed（必须，否则联机 Mod 加载即报错）
    3) 给这些文件加「只读 + 拒绝写入/删除」，阻止 Steam 自动更新把它们换回作者版本
#>

param(
    [ValidateSet('Install', 'Lock', 'Unlock', 'Status', 'Restore')]
    [string]$Action = 'Install',
    [switch]$NoLock,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

$PackageRoot = $PSScriptRoot
$PayloadDir  = Join-Path $PackageRoot 'files'
$BackupRoot  = Join-Path $env:LOCALAPPDATA 'DuckovCoopModBackup'
$AppId       = '3167020'
$ItemId      = '3591341282'
$GameFolder  = 'Escape from Duckov'
$Me          = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

function Step($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "   [OK] $t" -ForegroundColor Green }
function Info($t) { Write-Host "   $t" }
function Warn($t) { Write-Host "   [注意] $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "   [错误] $t" -ForegroundColor Red }

function HashOf($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

function Get-SteamLibraries {
    $cands = New-Object System.Collections.ArrayList
    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch { }
    if (-not $steam) {
        try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch { }
    }
    if (-not $steam) { $steam = 'C:\Program Files (x86)\Steam' }
    $steam = ($steam -replace '/', '\').TrimEnd('\')
    [void]$cands.Add($steam)

    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $txt = Get-Content -LiteralPath $vdf -Raw
        foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
            $p = ($m.Groups[1].Value -replace '\\\\', '\').TrimEnd('\')
            if ($cands -notcontains $p) { [void]$cands.Add($p) }
        }
    }
    return $cands
}

function Resolve-Targets {
    $foundGame = $null
    foreach ($lib in Get-SteamLibraries) {
        $game    = Join-Path $lib ("steamapps\common\" + $GameFolder)
        $managed = Join-Path $game 'Duckov_Data\Managed'
        $shop    = Join-Path $lib ("steamapps\workshop\content\$AppId\$ItemId")
        if (-not (Test-Path -LiteralPath $managed)) { continue }
        $foundGame = $game
        if ((Test-Path -LiteralPath $shop) -and (Test-Path -LiteralPath (Join-Path $shop 'info.ini'))) {
            return @{ Game = $game; Managed = $managed; Workshop = $shop; Library = $lib }
        }
    }
    if (-not $foundGame) {
        Fail "没找到游戏安装目录（steamapps\common\$GameFolder）。请确认游戏已安装。"
        return $null
    }
    Fail "找到游戏了，但没找到创意工坊里的这个 Mod（$ItemId）。"
    Info "请先在 Steam 创意工坊订阅「逃离鸭科夫联机mod」（物品 3591341282），"
    Info "启动一次游戏让它下载完成，然后再运行本安装器。"
    return $null
}

function Get-ModFiles($workshop) {
    $list = @()
    foreach ($n in @('EscapeFromDuckovCoopMod.dll', 'EscapeFromDuckovModApi.dll')) {
        $p = Join-Path $workshop $n
        if (Test-Path -LiteralPath $p) { $list += $p }
    }
    $loc = Join-Path $workshop 'Localization'
    if (Test-Path -LiteralPath $loc) {
        Get-ChildItem -LiteralPath $loc -Filter '*.json' | ForEach-Object { $list += $_.FullName }
    }
    return $list
}

function Get-DenyRule($p) {
    $acl = Get-Acl -LiteralPath $p
    $acl.Access | Where-Object {
        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
        $_.IdentityReference.Value -eq $Me
    }
}

function Unlock-File($p) {
    $acl = Get-Acl -LiteralPath $p
    $changed = $false
    foreach ($r in @(Get-DenyRule $p)) { [void]$acl.RemoveAccessRule($r); $changed = $true }
    if ($changed) { Set-Acl -LiteralPath $p -AclObject $acl }
    $i = Get-Item -LiteralPath $p -Force
    if ($i.IsReadOnly) { $i.IsReadOnly = $false }
}

function Lock-File($p) {
    $i = Get-Item -LiteralPath $p -Force
    if (-not $i.IsReadOnly) { $i.IsReadOnly = $true }
    if (-not (Get-DenyRule $p)) {
        $acl  = Get-Acl -LiteralPath $p
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Me,
            [System.Security.AccessControl.FileSystemRights]'Write, Delete',
            [System.Security.AccessControl.AccessControlType]::Deny)
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $p -AclObject $acl
    }
}

# ------------------------------------------------------------------ main
if ($Action -eq 'Status' -or $Action -eq 'Install' -or $Action -eq 'Restore') {
    Step "定位安装位置"
}

$t = Resolve-Targets
if (-not $t) { exit 1 }

Info "游戏目录 : $($t.Game)"
Info "Mod 目录 : $($t.Workshop)"
Info "Managed  : $($t.Managed)"

switch ($Action) {

    'Status' {
        Step "文件比对（包内 vs 已安装）"
        $payload = Get-ChildItem -LiteralPath $PayloadDir -Recurse -File
        foreach ($f in $payload) {
            $rel = $f.FullName.Substring($PayloadDir.Length).TrimStart('\')
            $dst = Join-Path $t.Workshop $rel
            if (-not (Test-Path -LiteralPath $dst)) { Warn "$rel  缺失"; continue }
            if ((HashOf $f.FullName) -eq (HashOf $dst)) { Ok "$rel  一致" } else { Warn "$rel  不同（已被 Steam 换回作者版？）" }
        }
        $mApi = Join-Path $t.Managed 'EscapeFromDuckovModApi.dll'
        if (Test-Path -LiteralPath $mApi) {
            if ((HashOf $mApi) -eq (HashOf (Join-Path $PayloadDir 'EscapeFromDuckovModApi.dll'))) { Ok "Managed\EscapeFromDuckovModApi.dll  一致" }
            else { Warn "Managed\EscapeFromDuckovModApi.dll  不同" }
        } else { Warn "Managed\EscapeFromDuckovModApi.dll  缺失" }

        Step "锁定状态（Write/Delete 被拒绝 = 已锁）"
        foreach ($p in Get-ModFiles $t.Workshop) {
            $i = Get-Item -LiteralPath $p -Force
            $deny = @(Get-DenyRule $p)
            Info ("{0,-40} 只读={1,-6} 拒绝规则={2}" -f (Split-Path $p -Leaf), $i.IsReadOnly, $(if ($deny.Count -gt 0) { '是' } else { '否' }))
        }
    }

    'Lock' {
        Step "上锁"
        foreach ($p in Get-ModFiles $t.Workshop) {
            if ($WhatIfOnly) { Info "[预览] 将锁定 $(Split-Path $p -Leaf)" } else { Lock-File $p; Ok "已锁 $(Split-Path $p -Leaf)" }
        }
    }

    'Unlock' {
        Step "解锁"
        foreach ($p in Get-ModFiles $t.Workshop) {
            if ($WhatIfOnly) { Info "[预览] 将解锁 $(Split-Path $p -Leaf)" } else { Unlock-File $p; Ok "已解锁 $(Split-Path $p -Leaf)" }
        }
    }

    'Install' {
        $running = Get-Process -Name 'Duckov' -ErrorAction SilentlyContinue
        if ($running) { Fail "游戏正在运行（PID $($running.Id)），请先完全退出游戏。"; exit 1 }

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $bak   = Join-Path $BackupRoot $stamp

        Step "备份当前文件"
        if ($WhatIfOnly) {
            Info "[预览] 备份将写入 $bak"
        } else {
            New-Item -ItemType Directory -Force -Path $bak | Out-Null
            foreach ($p in Get-ModFiles $t.Workshop) {
                $rel = $p.Substring($t.Workshop.Length).TrimStart('\')
                $to  = Join-Path $bak $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
                Copy-Item -LiteralPath $p -Destination $to -Force
            }
            $mExisting = Join-Path $t.Managed 'EscapeFromDuckovModApi.dll'
            if (Test-Path -LiteralPath $mExisting) {
                Copy-Item -LiteralPath $mExisting -Destination (Join-Path $bak 'Managed_EscapeFromDuckovModApi.dll') -Force
            }
            Ok "已备份到 $bak"
        }

        Step "解锁目标文件"
        if ($WhatIfOnly) {
            Info "[预览] 将解锁 $(@(Get-ModFiles $t.Workshop).Count) 个文件"
        } else {
            foreach ($p in Get-ModFiles $t.Workshop) { Unlock-File $p }
            Ok "已完成"
        }

        Step "覆盖 Mod 文件"
        $payload = Get-ChildItem -LiteralPath $PayloadDir -Recurse -File
        foreach ($f in $payload) {
            $rel = $f.FullName.Substring($PayloadDir.Length).TrimStart('\')
            $dst = Join-Path $t.Workshop $rel
            if ($WhatIfOnly) { Info "[预览] $rel" | Out-Null; continue }
            New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
            if ((HashOf $dst) -ne (HashOf $f.FullName)) { Fail "复制后校验失败：$rel"; exit 1 }
            Ok $rel
        }

        Step "同步 Managed（关键：不复制这个，联机 Mod 会加载失败）"
        if ($WhatIfOnly) {
            Info "[预览] EscapeFromDuckovModApi.dll -> Managed"
        } else {
            Copy-Item -LiteralPath (Join-Path $PayloadDir 'EscapeFromDuckovModApi.dll') -Destination (Join-Path $t.Managed 'EscapeFromDuckovModApi.dll') -Force
            Ok "Managed\EscapeFromDuckovModApi.dll"
        }

        Step "上锁（阻止 Steam 自动更新覆盖）"
        if ($NoLock) {
            Warn "已按 -NoLock 跳过；Steam 下次更新会把 Mod 换回作者版本"
        } elseif ($WhatIfOnly) {
            Info "[预览] 将给 9 个文件加只读 + 拒绝写入/删除"
        } else {
            foreach ($p in Get-ModFiles $t.Workshop) { Lock-File $p }
            Ok "已锁定"
        }

        Write-Host ""
        Write-Host "安装完成，可以启动游戏了。" -ForegroundColor Green
        Warn "联机时请确保所有玩家使用的是同一个版本（都装这个包）。"
    }

    'Restore' {
        Step "查找备份"
        if (-not (Test-Path -LiteralPath $BackupRoot)) { Fail "没有找到任何备份目录：$BackupRoot"; exit 1 }
        $latest = Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if (-not $latest) { Fail "备份目录是空的：$BackupRoot"; exit 1 }
        Info "使用备份：$($latest.FullName)"

        Step "解锁并还原"
        foreach ($p in Get-ModFiles $t.Workshop) { Unlock-File $p }
        foreach ($f in Get-ChildItem -LiteralPath $latest.FullName -Recurse -File) {
            if ($f.Name -eq 'Managed_EscapeFromDuckovModApi.dll') {
                if ($WhatIfOnly) { Info "[预览] Managed\EscapeFromDuckovModApi.dll" }
                else { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $t.Managed 'EscapeFromDuckovModApi.dll') -Force; Ok "Managed\EscapeFromDuckovModApi.dll" }
                continue
            }
            $rel = $f.FullName.Substring($latest.FullName.Length).TrimStart('\')
            if ($WhatIfOnly) { Info "[预览] $rel" }
            else { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $t.Workshop $rel) -Force; Ok $rel }
        }
        Write-Host ""
        Warn "已还原为安装前的文件。若还原的是作者原版，请再用 Steam 更新一次，确保 ModApi 与它配套。"
    }
}