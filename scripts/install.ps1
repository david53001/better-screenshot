# One-line installer AND updater for BetterScreenshot on Windows 10/11 (64-bit). Paste into PowerShell:
#
#   irm https://raw.githubusercontent.com/david53001/better-screenshot/main/scripts/install.ps1 | iex
#
# Downloads the newest Windows release from GitHub, puts it in %LOCALAPPDATA%\Programs\BetterScreenshot
# (replacing an older copy), adds Start menu and Desktop shortcuts and an Apps & features entry (no admin
# needed), and starts it in the system tray. Screen recording needs ffmpeg: when this PC doesn't have it,
# the script fetches it once from gyan.dev (the "essentials" build, about 115 MB) and keeps it next to
# the app.
#
# Running it again UPDATES the app: it says which version you had and which you got, and does nothing
# when you're already up to date (reinstall anyway with:  $env:BETTERSCREENSHOT_FORCE='1'; irm ... | iex).
# Settings and capture history (%APPDATA%\BetterScreenshot) and the screenshots and recordings you saved
# are never touched.
#
# The files are downloaded by PowerShell, not a browser, so Windows does not show the
# "Windows protected your PC" (SmartScreen) prompt.
#
# Test overrides (unset for real use): BETTERSCREENSHOT_INSTALL_DIR, BETTERSCREENSHOT_DESKTOP_DIR,
# BETTERSCREENSHOT_STARTMENU_DIR, BETTERSCREENSHOT_ARP_NAME, BETTERSCREENSHOT_NO_STOP,
# BETTERSCREENSHOT_SKIP_LAUNCH, BETTERSCREENSHOT_NO_FFMPEG.
#
# Everything runs inside a script block so an error never closes your PowerShell window.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # Windows PowerShell's progress bar makes downloads crawl
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $repo      = 'david53001/better-screenshot'
    $asset     = 'BetterScreenshot-win-x64.zip'
    $procName  = 'BetterScreenshot.App'
    $target    = if ($env:BETTERSCREENSHOT_INSTALL_DIR)   { $env:BETTERSCREENSHOT_INSTALL_DIR }   else { Join-Path $env:LOCALAPPDATA 'Programs\BetterScreenshot' }
    $desktop   = if ($env:BETTERSCREENSHOT_DESKTOP_DIR)   { $env:BETTERSCREENSHOT_DESKTOP_DIR }   else { [Environment]::GetFolderPath('Desktop') }
    $startmenu = if ($env:BETTERSCREENSHOT_STARTMENU_DIR) { $env:BETTERSCREENSHOT_STARTMENU_DIR } else { Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs' }
    $arpName   = if ($env:BETTERSCREENSHOT_ARP_NAME)      { $env:BETTERSCREENSHOT_ARP_NAME }      else { 'BetterScreenshot' }
    $exePath   = Join-Path $target 'BetterScreenshot.App.exe'
    $ffmpegDst = Join-Path $target 'tools\ffmpeg.exe'

    function Fail([string]$msg) { Write-Host "error: $msg" -ForegroundColor Red }
    function VersionOf([string]$s) { if ($s -match '(\d+\.\d+\.\d+)') { [version]$Matches[1] } else { $null } }
    function Download([string]$url, [string]$file) {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) { & $curl.Source -fL --progress-bar -o $file $url; if ($LASTEXITCODE -ne 0) { throw "download failed (curl exit $LASTEXITCODE)" } }
        else { Invoke-WebRequest $url -OutFile $file -UseBasicParsing }
    }
    function Launch {
        if ($env:BETTERSCREENSHOT_SKIP_LAUNCH) { return }
        if (-not (Get-Process $procName -ErrorAction SilentlyContinue)) { Start-Process $exePath -WorkingDirectory $target }
    }
    # Recording needs ffmpeg. Use one on PATH or already next to the app; otherwise fetch it once.
    function Ensure-Ffmpeg {
        if ($env:BETTERSCREENSHOT_NO_FFMPEG -or (Test-Path $ffmpegDst) -or (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { return }
        Write-Host '==> Downloading ffmpeg for screen recording (about 115 MB, once)...'
        $zip = Join-Path $env:TEMP ('bs-ffmpeg-' + [Guid]::NewGuid().ToString('N') + '.zip')
        try {
            Download 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $zip
            $archive = [IO.Compression.ZipFile]::OpenRead($zip)
            try {
                $entry = $archive.Entries | Where-Object { $_.FullName -match '[\\/]bin[\\/]ffmpeg\.exe$' } | Select-Object -First 1
                if (-not $entry) { throw 'ffmpeg.exe was not in the download' }
                New-Item -ItemType Directory -Path (Split-Path $ffmpegDst) -Force | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $ffmpegDst, $true)
            } finally { $archive.Dispose() }
        } catch {
            Write-Host "warning: could not set up ffmpeg ($($_.Exception.Message)). Screenshots work; for recording run:  winget install Gyan.FFmpeg" -ForegroundColor Yellow
        } finally { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
    }

    if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Build -lt 19041) {
        Fail 'BetterScreenshot needs 64-bit Windows 10 version 2004 (build 19041) or newer.'; return
    }

    # ---- Newest Windows release (the repo's "latest" release is a macOS one) ----
    Write-Host '==> Finding the newest Windows release...'
    $releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=30" -UseBasicParsing
    $release = $null; $a = $null
    foreach ($r in $releases) {
        if ($r.draft -or $r.prerelease) { continue }
        $a = $r.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1
        if ($a) { $release = $r; break }
    }
    if (-not $release) { Fail "no release with $asset found for $repo"; return }
    $new = VersionOf $release.tag_name
    $old = if (Test-Path $exePath) { VersionOf (Get-Item $exePath).VersionInfo.ProductVersion } else { $null }

    if ($old -and $new -and $old -ge $new -and $env:BETTERSCREENSHOT_FORCE -ne '1') {
        Write-Host "BetterScreenshot $old is already the latest version."
        Ensure-Ffmpeg; Launch
        return
    }

    # ---- Download and unpack to a temp folder first, so a failure never breaks the current install ----
    $zip   = Join-Path $env:TEMP ('bs-' + [Guid]::NewGuid().ToString('N') + '.zip')
    $unzip = Join-Path $env:TEMP ('bs-' + [Guid]::NewGuid().ToString('N'))
    try {
        Write-Host "==> Downloading BetterScreenshot $new ($([math]::Round($a.size / 1MB)) MB)..."
        Download $a.browser_download_url $zip
        if ((Get-Item $zip).Length -ne $a.size) { Fail 'the download is incomplete; please run the command again.'; return }
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                # Compress-Archive writes "\" separators; an entry with an empty Name is a directory.
                $dest = Join-Path $unzip $entry.FullName.Replace('/', '\')
                if ([string]::IsNullOrEmpty($entry.Name)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null; continue }
                New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
            }
        } finally { $archive.Dispose() }
        $appSrc = Join-Path $unzip 'BetterScreenshot'
        if (-not (Test-Path (Join-Path $appSrc 'BetterScreenshot.App.exe'))) { Fail 'the download did not contain BetterScreenshot.App.exe'; return }

        # ---- Quit the running copy (a recording in progress is recovered at the next launch) ----
        if (-not $env:BETTERSCREENSHOT_NO_STOP -and (Get-Process $procName -ErrorAction SilentlyContinue)) {
            Write-Host '==> Quitting the running copy...'
            Get-Process $procName -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
            for ($i = 0; $i -lt 50 -and (Get-Process $procName -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 100 }
        }

        # ---- Swap in the new version; ffmpeg fetched by an earlier install carries over ----
        Write-Host "==> Installing to $target..."
        if (Test-Path $ffmpegDst) {
            New-Item -ItemType Directory -Path (Join-Path $appSrc 'tools') -Force | Out-Null
            Copy-Item $ffmpegDst (Join-Path $appSrc 'tools\ffmpeg.exe') -Force
        }
        if (Test-Path $target) {
            try { Remove-Item $target -Recurse -Force }
            catch { Fail 'BetterScreenshot is still running. Right-click its tray icon, choose Quit, then paste the command again.'; return }
        }
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        Move-Item $appSrc $target
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $unzip -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---- Shortcuts, uninstaller and the Apps & features entry ----
    New-Item -ItemType Directory -Path $desktop, $startmenu -Force | Out-Null
    $ws = New-Object -ComObject WScript.Shell
    foreach ($dir in @($desktop, $startmenu)) {
        $lnk = $ws.CreateShortcut((Join-Path $dir 'BetterScreenshot.lnk'))
        $lnk.TargetPath = $exePath; $lnk.WorkingDirectory = $target; $lnk.IconLocation = "$exePath,0"
        $lnk.Description = 'BetterScreenshot - screenshots, recording and annotation'
        $lnk.Save()
    }
    $uninstaller = Join-Path $target 'uninstall.ps1'
    try { Invoke-WebRequest "https://raw.githubusercontent.com/$repo/main/scripts/uninstall.ps1" -OutFile $uninstaller -UseBasicParsing } catch {}
    $arpKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$arpName"
    New-Item -Path $arpKey -Force | Out-Null
    Set-ItemProperty $arpKey 'DisplayName'     'BetterScreenshot'
    Set-ItemProperty $arpKey 'DisplayVersion'  "$new"
    Set-ItemProperty $arpKey 'Publisher'       'BetterScreenshot'
    Set-ItemProperty $arpKey 'DisplayIcon'     $exePath
    Set-ItemProperty $arpKey 'InstallLocation' $target
    if (Test-Path $uninstaller) { Set-ItemProperty $arpKey 'UninstallString' "powershell -NoProfile -ExecutionPolicy Bypass -File `"$uninstaller`"" }
    Set-ItemProperty $arpKey 'NoModify' 1 -Type DWord
    Set-ItemProperty $arpKey 'NoRepair' 1 -Type DWord
    Set-ItemProperty $arpKey 'EstimatedSize' ([int]((Get-ChildItem $target -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)) -Type DWord

    Ensure-Ffmpeg
    Launch
    if ($old -and $old -eq $new) { Write-Host "Reinstalled BetterScreenshot $new. Your settings and history are kept." -ForegroundColor Green }
    elseif ($old) { Write-Host "Updated BetterScreenshot $old -> $new. Your settings and history are kept." -ForegroundColor Green }
    else { Write-Host "Installed BetterScreenshot $new. Look for the camera icon in the system tray; the first launch shows the hotkeys." -ForegroundColor Green }
}
