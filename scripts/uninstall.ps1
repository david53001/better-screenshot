# One-line uninstaller for BetterScreenshot on Windows. Paste into PowerShell:
#
#   irm https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/uninstall.ps1 | iex
#
# Quits BetterScreenshot and removes everything it put on this PC: the app
# (%LOCALAPPDATA%\Programs\BetterScreenshot, including the ffmpeg the installer fetched), its shortcuts,
# its Apps & features entry, launch at login, its settings and capture history (%APPDATA%\BetterScreenshot)
# and its temp files. Screenshots and recordings you saved are not touched. Reinstall any time with
# scripts/install.ps1.
#
# Test overrides (unset for real use): BETTERSCREENSHOT_INSTALL_DIR, BETTERSCREENSHOT_DESKTOP_DIR,
# BETTERSCREENSHOT_STARTMENU_DIR, BETTERSCREENSHOT_ARP_NAME, BETTERSCREENSHOT_APPDATA_DIR, and
# BETTERSCREENSHOT_NO_STOP (leaves the running app, its Run entry and temp files alone).
& {
    $ErrorActionPreference = 'Stop'
    $procName  = 'BetterScreenshot.App'
    $target    = if ($env:BETTERSCREENSHOT_INSTALL_DIR)   { $env:BETTERSCREENSHOT_INSTALL_DIR }   else { Join-Path $env:LOCALAPPDATA 'Programs\BetterScreenshot' }
    $desktop   = if ($env:BETTERSCREENSHOT_DESKTOP_DIR)   { $env:BETTERSCREENSHOT_DESKTOP_DIR }   else { [Environment]::GetFolderPath('Desktop') }
    $startmenu = if ($env:BETTERSCREENSHOT_STARTMENU_DIR) { $env:BETTERSCREENSHOT_STARTMENU_DIR } else { Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs' }
    $arpName   = if ($env:BETTERSCREENSHOT_ARP_NAME)      { $env:BETTERSCREENSHOT_ARP_NAME }      else { 'BetterScreenshot' }
    $appData   = if ($env:BETTERSCREENSHOT_APPDATA_DIR)   { $env:BETTERSCREENSHOT_APPDATA_DIR }   else { Join-Path $env:APPDATA 'BetterScreenshot' }
    $problems  = @()

    if (-not $env:BETTERSCREENSHOT_NO_STOP) {
        if (Get-Process $procName -ErrorAction SilentlyContinue) {
            Write-Host '==> Quitting BetterScreenshot...'
            Get-Process $procName -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
            for ($i = 0; $i -lt 50 -and (Get-Process $procName -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 100 }
            if (Get-Process $procName -ErrorAction SilentlyContinue) {
                Write-Host 'error: BetterScreenshot could not be closed. Right-click its tray icon, choose Quit, then paste the command again.' -ForegroundColor Red
                return
            }
        }
        Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BetterScreenshot' -ErrorAction SilentlyContinue
        Get-ChildItem $env:TEMP -Directory -Filter 'BetterScreenshot-*' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "==> Removing $target..."
    Remove-Item (Join-Path $desktop 'BetterScreenshot.lnk'), (Join-Path $startmenu 'BetterScreenshot.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$arpName" -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($dir in @($target, $appData)) {
        if (-not (Test-Path $dir)) { continue }
        if ($dir -ne $target) { Write-Host "==> Removing $dir..." }
        try { Remove-Item $dir -Recurse -Force -ErrorAction Stop }
        catch { $problems += "Could not fully remove $dir ($($_.Exception.Message))" }
    }

    if ($problems.Count) {
        Write-Host 'BetterScreenshot is uninstalled, except:' -ForegroundColor Yellow
        $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    } else {
        Write-Host 'BetterScreenshot is uninstalled. Screenshots and recordings you saved are kept.' -ForegroundColor Green
    }
}
