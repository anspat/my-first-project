$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

$chrome = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

# Watchdog loop — restarts server if it crashes
while ($true) {
    $proc = Start-Process powershell -ArgumentList @(
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$dir\voice-to-claude.ps1`""
    ) -WindowStyle Hidden -PassThru

    # Open Chrome only on first start (port not yet open after restart)
    Start-Sleep -Milliseconds 2000
    $listening = netstat -ano | Select-String ":9876.*LISTENING"
    if ($listening -and $chrome) {
        $chromeRunning = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*Voice*" }
        if (-not $chromeRunning) {
            Start-Process $chrome "--app=http://localhost:9876 --window-size=300,220 --window-position=1600,830"
        }
    }

    $proc.WaitForExit()
    Start-Sleep -Seconds 2
}
