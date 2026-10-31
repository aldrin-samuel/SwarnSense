$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot
$logPath = Join-Path $PSScriptRoot "orbit-backend.log"

function Write-Stage([string]$message) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
    Write-Host $line -ForegroundColor Cyan
    Add-Content -LiteralPath $logPath -Value $line
}

try {
    Set-Content -LiteralPath $logPath -Value "SwarmSense startup log" -Encoding UTF8

    Write-Stage "Checking Node.js and npm"
    $nodeCommand = Get-Command node -ErrorAction Stop
    $npmCommand = Get-Command npm.cmd -ErrorAction Stop
    Add-Content -LiteralPath $logPath -Value "Node: $($nodeCommand.Source)"
    Add-Content -LiteralPath $logPath -Value "npm: $($npmCommand.Source)"

    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "node_modules"))) {
        Write-Stage "Installing dependencies"
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $npmCommand.Source install 2>&1 | Tee-Object -FilePath $logPath -Append
        $installExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorAction
        if ($installExitCode -ne 0) { throw "npm install failed with exit code $installExitCode" }
    }

    Write-Stage "Building React frontend"
    # Vite writes non-fatal warnings (for example, chunk-size notices) to stderr.
    # Windows PowerShell wraps redirected native stderr as NativeCommandError when
    # ErrorActionPreference is Stop, so rely on npm's real process exit code here.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $npmCommand.Source run build 2>&1 | Tee-Object -FilePath $logPath -Append
    $buildExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($buildExitCode -ne 0) { throw "npm build failed with exit code $buildExitCode" }

    $env:NODE_ENV = "production"
    $env:OPEN_BROWSER = "1"
    $env:PORT = "4100"
    $env:HOST = "127.0.0.1"
    $env:HARDWARE_TOKEN = "orbit-demo-local"
    $env:ENABLE_SERIAL = "0"
    $env:ENABLE_UDP = "1"

    Write-Stage "Starting backend and wireless ESP32 UDP bridge at http://localhost:4100"
    Write-Host "Keep this window open. Press Ctrl+C to stop SwarmSense." -ForegroundColor Yellow
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $nodeCommand.Source "server/index.js" 2>&1 | Tee-Object -FilePath $logPath -Append
    $backendExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction

    if ($backendExitCode -ne 0) {
        throw "Backend stopped with exit code $backendExitCode"
    }
}
catch {
    $details = $_ | Out-String
    Add-Content -LiteralPath $logPath -Value $details
    Write-Host ""
    Write-Host "SwarmSense failed to start:" -ForegroundColor Red
    Write-Host $details -ForegroundColor Red
    Write-Host "Diagnostic log: $logPath" -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 1
}
