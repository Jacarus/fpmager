param(
    [string]$Server    = "149.248.209.141",
    [int]   $Port      = 24567,
    [int]   $TimeoutMs = 4000,
    [int]   $Rounds    = 5,       # packets per SNAT config window
    [int]   $IntervalMs = 3000    # ms between packets
)

$ErrorActionPreference = "Continue"

function Send-Udp([string]$msg) {
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = $TimeoutMs
    $ep  = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    try {
        $b    = [System.Text.Encoding]::UTF8.GetBytes($msg)
        $null = $udp.Send($b, $b.Length, $Server, $Port)
        $recv = $udp.Receive([ref]$ep)
        return [System.Text.Encoding]::UTF8.GetString($recv)
    } catch {
        return $null
    } finally {
        $udp.Close()
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " UDP echo test  ->  ${Server}:${Port}"    -ForegroundColor Cyan
Write-Host " $Rounds rounds, ${IntervalMs}ms interval"
Write-Host " Server rotates SNAT config every 15 s"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$results = @{}
$seq = 0

for ($i = 1; $i -le $Rounds; $i++) {
    $seq++
    $msg  = "PING-$seq"
    $ts   = Get-Date -Format "HH:mm:ss"
    $resp = Send-Udp $msg

    if ($resp) {
        Write-Host "[$ts] #$seq RECV: $resp" -ForegroundColor Green
        # extract src= label
        if ($resp -match 'src=(\S+)') {
            $label = $Matches[1]
            if ($results.ContainsKey($label)) { $results[$label]++ } else { $results[$label] = 1 }
        }
    } else {
        Write-Host "[$ts] #$seq TIMEOUT (no response in ${TimeoutMs}ms)" -ForegroundColor Yellow
    }

    if ($i -lt $Rounds) { Start-Sleep -Milliseconds $IntervalMs }
}

Write-Host ""
Write-Host "======== Summary ========" -ForegroundColor Cyan
if ($results.Count -gt 0) {
    Write-Host "Configs that GOT responses back:" -ForegroundColor Green
    foreach ($k in $results.Keys) {
        Write-Host "  src=$k  ->  $($results[$k]) packet(s) received" -ForegroundColor Green
    }
} else {
    Write-Host "No responses received for ANY config." -ForegroundColor Red
    Write-Host "The problem is upstream of the SNAT rule (fly.io not routing inbound, or all outbound paths blocked)."
}
Write-Host "=========================" -ForegroundColor Cyan
