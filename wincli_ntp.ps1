
# ============================================================
# NTP CLIENT & SERVER CONFIGURATION
# ============================================================

# NTP Servers
$PrimaryNTP = "10.0.1.10"
$SecondNTP  = "ntp.metas.ch"

Write-Host "Configuring Windows NTP Client and Server..." -ForegroundColor Cyan


# ------------------------------------------------------------
# 1. Configure Windows Time Zone (Zurich, Switzerland)
# ------------------------------------------------------------

Set-TimeZone -Id "W. Europe Standard Time"

Write-Host "Time zone set to Zurich (Switzerland)." -ForegroundColor Green


# ------------------------------------------------------------
# 2. Configure Windows Time Service
# ------------------------------------------------------------

Set-Service W32Time -StartupType Automatic

# Configure NTP peers
w32tm /config /manualpeerlist:"$PrimaryNTP,0x8 $SecondNTP,0xA" /syncfromflags:manual /update

# ------------------------------------------------------------
# 3. Enable NTP Server functionality
# ------------------------------------------------------------

Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
    -Name "Enabled" -Value 1

Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config" `
    -Name "AnnounceFlags" -Value 10

# ------------------------------------------------------------
# 4. Configure Windows Firewall
# ------------------------------------------------------------

# Allow incoming NTP requests (UDP 123)
if (-not (Get-NetFirewallRule -DisplayName "NTP Server - UDP 123 Inbound" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName "NTP Server - UDP 123 Inbound" `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 123 `
        -Action Allow `
        -Profile Any
}

# Allow outgoing NTP traffic to primary server
if (-not (Get-NetFirewallRule -DisplayName "NTP Client - UDP 123 Outbound" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -DisplayName "NTP Client - UDP 123 Outbound" `
        -Direction Outbound `
        -Protocol UDP `
        -RemotePort 123 `
        -RemoteAddress $PrimaryNTP `
        -Action Allow `
        -Profile Any
}

# --------------------------------------------------------------------
# 5. Configure NTP Poll Interval (16 seconds) and resolve time 1 min
# --------------------------------------------------------------------

$NtpConfig = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config"

Set-ItemProperty -Path $NtpConfig -Name MinPollInterval -Value 4
Set-ItemProperty -Path $NtpConfig -Name MaxPollInterval -Value 4

Write-Host "NTP polling interval set to 16 seconds." -ForegroundColor Green

# Retry failed peers every 1 minute
Set-ItemProperty -Path $NtpConfig -Name ResolvePeerBackoffMinutes -Value 1

# Disable exponential backoff
Set-ItemProperty -Path $NtpConfig -Name ResolvePeerBackoffMaxTimes -Value 0

Write-Host "Retry failed peers set to 1 and maxtimes to 0 " -ForegroundColor Green

w32tm /config /update

Restart-Service W32Time

# ------------------------------------------------------------
# 6. Restart Windows Time Service
# ------------------------------------------------------------

Restart-Service W32Time

Start-Sleep -Seconds 5

# ------------------------------------------------------------
# 7. Synchronize Time
# ------------------------------------------------------------

w32tm /resync /rediscover

# ------------------------------------------------------------
# 8. Display Configuration and Status
# ------------------------------------------------------------

Write-Host "`n========== NTP CONFIGURATION ==========" -ForegroundColor Cyan

w32tm /query /configuration

Write-Host "`n========== NTP PEERS ==========" -ForegroundColor Cyan

w32tm /query /peers

Write-Host "`n========== NTP SOURCE ==========" -ForegroundColor Cyan

w32tm /query /source

Write-Host "`n========== NTP STATUS ==========" -ForegroundColor Cyan

w32tm /query /status

Write-Host "`n========== FIREWALL RULES ==========" -ForegroundColor Cyan

Get-NetFirewallRule -DisplayName "*NTP*"

Write-Host "`nNTP configuration completed." -ForegroundColor Green

