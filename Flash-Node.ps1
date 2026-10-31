param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 5)]
    [int]$NodeId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^COM\d+$')]
    [string]$Port
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$firmwareRoot = Join-Path $projectRoot "firmware"
$knownPio = "C:\Users\aldri\AppData\Roaming\Python\Python314\Scripts\pio.exe"
$pioCommand = Get-Command pio.exe -ErrorAction SilentlyContinue
$pioPath = if ($pioCommand) { $pioCommand.Source } elseif (Test-Path -LiteralPath $knownPio) { $knownPio } else { throw "PlatformIO was not found." }

Write-Host "Building and flashing SwarmSense node $NodeId on $Port..." -ForegroundColor Cyan
& $pioPath run -d $firmwareRoot -t upload --upload-port $Port
if ($LASTEXITCODE -ne 0) { throw "Firmware upload failed with exit code $LASTEXITCODE." }

Start-Sleep -Seconds 2
$serial = [System.IO.Ports.SerialPort]::new($Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.NewLine = "`n"
$serial.DtrEnable = $false
$serial.RtsEnable = $false
try {
    $serial.Open()
    Start-Sleep -Seconds 2
    $serial.WriteLine("ID $NodeId")
    Start-Sleep -Seconds 1
}
finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}

Write-Host "Node $NodeId is flashed and its ID is stored. Disconnect it and repeat for the next board." -ForegroundColor Green
