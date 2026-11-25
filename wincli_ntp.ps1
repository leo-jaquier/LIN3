
# ============================================================
# NTP CLIENT & SERVER CONFIGURATION
# ============================================================

# NTP Servers
$PrimaryNTP = "10.0.1.10"
$SecondaryNTP = @(
    "0.ie.pool.ntp.org"
    "1.ie.pool.ntp.org"
    "2.ie.pool.ntp.org"
    "3.ie.pool.ntp.org"
)

# Local server and authorized subnet
$LocalNTPIP  = "10.0.1.11"
$AllowedSubnet = "10.0.1.0/28"

# Log paths
$NtpLog = "C:\Windows\Temp\w32time.log"
$FirewallLog = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"

$NtpConfig = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config"

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

$PeerList = "$PrimaryNTP,0x8 " + (($SecondaryNTP | ForEach-Object { "$_,0xA" }) -join " ")

w32tm /config /manualpeerlist:"$PeerList" /syncfromflags:manual /update

# ------------------------------------------------------------
# 3. Enable NTP Server functionality
# ------------------------------------------------------------

Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer" `
    -Name "Enabled" -Value 1

Set-ItemProperty `
    -Path $NtpConfig `
    -Name "AnnounceFlags" -Value 10

Write-Host "NTP Server functionality enabled." -ForegroundColor Green


# ------------------------------------------------------------
# 4. Configure Windows Firewall
# ------------------------------------------------------------

# Allow incoming NTP requests ONLY from authorized subnet
$InboundRule = Get-NetFirewallRule `
    -DisplayName "NTP Server - UDP 123 Inbound" `
    -ErrorAction SilentlyContinue

if ($InboundRule) {

    Set-NetFirewallRule `
        -DisplayName "NTP Server - UDP 123 Inbound" `
        -RemoteAddress $AllowedSubnet

}
else {

    New-NetFirewallRule `
        -DisplayName "NTP Server - UDP 123 Inbound" `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 123 `
        -RemoteAddress $AllowedSubnet `
        -Action Allow `
        -Profile Any

}

Write-Host "Inbound NTP restricted to $AllowedSubnet." -ForegroundColor Green


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

Write-Host "NTP firewall rules configured." -ForegroundColor Green


# ------------------------------------------------------------
# 5. Configure NTP Poll Interval and Peer Retry
# ------------------------------------------------------------

Set-ItemProperty -Path $NtpConfig -Name MinPollInterval -Value 4
Set-ItemProperty -Path $NtpConfig -Name MaxPollInterval -Value 4

Write-Host "NTP polling interval set to 16 seconds." -ForegroundColor Green

# Retry failed peers every 1 minute
Set-ItemProperty -Path $NtpConfig -Name ResolvePeerBackoffMinutes -Value 1

# Disable exponential backoff
Set-ItemProperty -Path $NtpConfig -Name ResolvePeerBackoffMaxTimes -Value 0

Write-Host "Retry failed peers configured." -ForegroundColor Green

w32tm /config /update


# ------------------------------------------------------------
# 6. Enable Windows Time Service Debug Logging
# ------------------------------------------------------------

if (-not (Test-Path "C:\Windows\Temp")) {
    New-Item -ItemType Directory -Path "C:\Windows\Temp" -Force | Out-Null
}

# Enable W32Time debug logging (10 MB circular log)
w32tm /debug /enable /file:$NtpLog /size:10000000 /entries:0-116

Write-Host "W32Time debug logging enabled: $NtpLog" -ForegroundColor Green


# ------------------------------------------------------------
# 7. Enable Windows Firewall Successful Connection Logging
# ------------------------------------------------------------

# Log successful connections for all firewall profiles.
# This allows us to identify incoming NTP client IP addresses.

Set-NetFirewallProfile `
    -Profile Domain,Private,Public `
    -LogAllowed True `
    -LogMaxSizeKilobytes 32767 `
    -LogFileName $FirewallLog

Write-Host "Firewall successful connection logging enabled." -ForegroundColor Green

Write-Host "Firewall log location: $FirewallLog" -ForegroundColor Cyan


# ------------------------------------------------------------
# 8. Restart Windows Time Service
# ------------------------------------------------------------

Restart-Service W32Time

Start-Sleep -Seconds 5


# ------------------------------------------------------------
# 9. Synchronize Time
# ------------------------------------------------------------

w32tm /resync /rediscover


# ------------------------------------------------------------
# 10. Display Configuration and Status
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

Get-NetFirewallRule -DisplayName "*NTP*" |
    Format-Table DisplayName, Enabled, Direction, Action

Write-Host "`n========== W32TIME DEBUG LOG ==========" -ForegroundColor Cyan

if (Test-Path $NtpLog) {
    Get-Item $NtpLog | Select-Object FullName, Length, LastWriteTime
    Get-Content $NtpLog -Tail 10
}
else {
    Write-Host "W32Time log not yet created." -ForegroundColor Yellow
}

Write-Host "`n========== FIREWALL LOG ==========" -ForegroundColor Cyan

if (Test-Path $FirewallLog) {
    Get-Item $FirewallLog | Select-Object FullName, Length, LastWriteTime
}
else {
    Write-Host "Firewall log not yet created." -ForegroundColor Yellow
}

Write-Host "`nNTP configuration completed." -ForegroundColor Green

