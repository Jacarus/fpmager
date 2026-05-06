param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $ServerCommandParts
)

$App = "fp-mager"
$CommandFile = "/tmp/fp-mager-commands.txt"

function Show-Usage {
    Write-Host "Usage: Scripts\server_command.bat <server command>"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  status"
    Write-Host "  bots on"
    Write-Host "  bots off"
    Write-Host "  bots <0-12>"
    Write-Host "  bot_count <0-12>"
    Write-Host "  bot_difficulty <Easy|Medium|Hard>"
    Write-Host "  boss status"
    Write-Host "  boss spawn health=2400 name=Aether_Colossus scale=1.2 cooldown=0.85 speed=1.1 respawn=off"
    Write-Host "  boss spawn health=2400 replace=on"
    Write-Host "  boss replace health=4000 respawn=on"
    Write-Host "  boss despawn 0"
}

if ($ServerCommandParts.Count -eq 0) {
    Show-Usage
    exit 1
}

$ServerCommand = ($ServerCommandParts -join " ").Trim()
if ($ServerCommand -eq "") {
	Show-Usage
	exit 1
}
if ($ServerCommand -notmatch '^[A-Za-z0-9_ .:=+-]+$') {
    Write-Host "ERROR: command contains unsupported shell characters."
    exit 1
}

Write-Host "Finding running Fly machine for $App..."
$machineJson = & fly machine list --app $App --json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: failed to list Fly machines."
    Write-Host $machineJson
    exit 1
}

$machines = $machineJson | ConvertFrom-Json
$machine = $machines | Where-Object { $_.state -eq "started" } | Select-Object -First 1
if ($null -eq $machine) {
    Write-Host "ERROR: no started Fly machine found for $App."
    exit 1
}

$machineId = $machine.id
Write-Host "Sending to $App/$machineId`: $ServerCommand"

$remoteCommand = "sh -lc 'echo $ServerCommand >> $CommandFile'"
& fly machine exec $machineId $remoteCommand --app $App --timeout 10
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: failed to send command. Check fly auth and app status."
    exit 1
}

Write-Host "Command queued. Run  fly logs --app $App --no-tail  to see the server response."
