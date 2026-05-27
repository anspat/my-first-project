Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Net.Sockets;
using System.Text;
using System.Runtime.InteropServices;
using System.Threading;

public class WinAPI {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public static void PasteClipboard() {
        Thread.Sleep(300);
        keybd_event(0x11, 0, 0, UIntPtr.Zero);
        keybd_event(0x56, 0, 0, UIntPtr.Zero);
        Thread.Sleep(60);
        keybd_event(0x56, 0, 2, UIntPtr.Zero);
        keybd_event(0x11, 0, 2, UIntPtr.Zero);
    }
}
"@

function Set-VSCodeFocus {
    $proc = Get-Process -Name "Code" -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
            Select-Object -First 1
    if ($proc) {
        [WinAPI]::ShowWindow($proc.MainWindowHandle, 9)
        [WinAPI]::SetForegroundWindow($proc.MainWindowHandle)
        Start-Sleep -Milliseconds 400
        return $true
    }
    return $false
}

$html = @'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<title>Voice -> Claude</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0f0f0f;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;font-family:'Segoe UI',sans-serif}
.ring{width:70px;height:70px;border-radius:50%;background:#1a1a1a;border:2px solid #2a2a2a;display:flex;align-items:center;justify-content:center;margin-bottom:14px;transition:all .3s}
.ring.listening{border-color:#818cf8;background:#1a1a2e;animation:pulse 1.4s ease-in-out infinite}
.ring.ok{border-color:#4ade80;background:#0f2a1a}
.ring.error{border-color:#f87171;background:#2a0f0f}
@keyframes pulse{0%,100%{box-shadow:0 0 0 0 rgba(129,140,248,.5)}50%{box-shadow:0 0 0 16px rgba(129,140,248,0)}}
.listening svg{fill:#818cf8}.ok svg{fill:#4ade80}.error svg{fill:#f87171}
#st{font-size:12px;color:#555;text-align:center;max-width:220px;min-height:18px}
#st.listening{color:#818cf8}#st.ok{color:#4ade80}#st.error{color:#f87171}
#interim{font-size:11px;color:#444;max-width:240px;text-align:center;margin-top:8px;font-style:italic;min-height:16px}
</style>
</head>
<body>
<div class="ring" id="ring">
<svg width="30" height="30" viewBox="0 0 24 24" fill="#333">
<path d="M12 1a4 4 0 0 1 4 4v6a4 4 0 0 1-8 0V5a4 4 0 0 1 4-4zm0 2a2 2 0 0 0-2 2v6a2 2 0 0 0 4 0V5a2 2 0 0 0-2-2zm7 8a1 1 0 0 1 1 1 8 8 0 0 1-7 7.938V21h2a1 1 0 0 1 0 2H9a1 1 0 0 1 0-2h2v-1.062A8 8 0 0 1 4 12a1 1 0 0 1 2 0 6 6 0 0 0 12 0 1 1 0 0 1 1-1z"/>
</svg>
</div>
<div id="st">Starting...</div>
<div id="interim"></div>
<script>
const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
const ring=document.getElementById('ring');
const st=document.getElementById('st');
const interim=document.getElementById('interim');
function setState(s,m){ring.className='ring '+s;st.className=s;st.textContent=m}
if(!SR){setState('error','Use Chrome')}
else{
let rec,restarting=false;
function start(){
if(restarting)return;
restarting=true;
rec=new SR();
rec.lang='ru-RU';
rec.interimResults=true;
rec.continuous=false;
rec.onstart=()=>{restarting=false;interim.textContent='';setState('listening','Говорите...')};
rec.onresult=e=>{
let fin='',tmp='';
for(let i=e.resultIndex;i<e.results.length;i++){
if(e.results[i].isFinal)fin+=e.results[i][0].transcript;
else tmp=e.results[i][0].transcript;
}
interim.textContent=tmp;
if(fin){
const text=fin.trim();
interim.textContent='';
setState('ok','Sending: '+text);
fetch('/voice?text='+encodeURIComponent(text))
.then(()=>{setTimeout(()=>setState('listening','Говорите...'),2000)})
.catch(()=>setState('error','Server error'));
}
};
rec.onend=()=>{setTimeout(()=>{restarting=false;start()},300)};
rec.onerror=e=>{
restarting=false;
if(e.error==='not-allowed'){setState('error','Allow microphone!');return}
setState('','Restarting...');
setTimeout(()=>start(),1500);
};
try{rec.start()}catch(e){restarting=false;setTimeout(()=>start(),1000)}
}
setState('','Starting...');
setTimeout(()=>start(),500);
}
</script>
</body>
</html>
'@

$port = 9876
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
$listener.Start()

Write-Host "[Voice->Claude] http://localhost:$port" -ForegroundColor Cyan
Write-Host "Opening Chrome..." -ForegroundColor Gray

# Open Chrome to the server URL
$chrome = @(
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($chrome) {
    Start-Process $chrome "--app=http://localhost:$port --window-size=300,200 --window-position=1600,850"
} else {
    Start-Process "http://localhost:$port"
}

Write-Host "Ready. Ctrl+C to stop." -ForegroundColor Green
Write-Host "----------------------------------------" -ForegroundColor DarkGray

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 500
            $bytes  = New-Object byte[] 4096
            $count  = $stream.Read($bytes, 0, $bytes.Length)
            $request = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $count)

            $firstLine = ($request -split "`r`n")[0]

            if ($firstLine -match "GET /voice\?text=(.+) HTTP") {
                $encoded = $matches[1] -replace '\+', ' '
                $text = [System.Uri]::UnescapeDataString($encoded)

                Write-Host "$([DateTime]::Now.ToString('HH:mm:ss')) >> $text" -ForegroundColor Green

                Set-VSCodeFocus | Out-Null
                [System.Windows.Forms.Clipboard]::SetText($text)
                [WinAPI]::PasteClipboard()

                $resp = "HTTP/1.1 200 OK`r`nContent-Length: 2`r`nConnection: close`r`n`r`nOK"
                $respBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                $stream.Write($respBytes, 0, $respBytes.Length)

            } elseif ($firstLine -match "GET / ") {
                # Serve HTML file as raw bytes (preserves UTF-8 encoding)
                $htmlPath = Join-Path $PSScriptRoot "voice-input.html"
                $htmlBytes = [System.IO.File]::ReadAllBytes($htmlPath)
                $header = "HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($htmlBytes.Length)`r`nConnection: close`r`n`r`n"
                $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($header)
                $stream.Write($headerBytes, 0, $headerBytes.Length)
                $stream.Write($htmlBytes, 0, $htmlBytes.Length)
            } else {
                $resp = "HTTP/1.1 200 OK`r`nContent-Length: 2`r`nConnection: close`r`n`r`nOK"
                $respBytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                $stream.Write($respBytes, 0, $respBytes.Length)
            }
        } catch {
            $errMsg = "$([DateTime]::Now.ToString('HH:mm:ss')) ERROR: $_"
            Write-Host $errMsg -ForegroundColor Red
            Add-Content "$PSScriptRoot\voice-error.log" $errMsg
        }
        finally { if ($client) { $client.Close() } }
    }
} catch {
    $errMsg = "$([DateTime]::Now.ToString('HH:mm:ss')) FATAL: $_"
    Write-Host $errMsg -ForegroundColor Red
    Add-Content "$PSScriptRoot\voice-error.log" $errMsg
} finally {
    $listener.Stop()
    Write-Host "Stopped." -ForegroundColor Yellow
}
