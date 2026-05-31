param(
    [string]$Listen = "127.0.0.1:18080",
    [string]$ProxyHost = "",
    [int]$ProxyPort = 0,
    [string]$ProxyUser = "",
    [string]$ProxyPassword = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root "proxy-config.json"

function ConvertTo-PlainText([securestring]$SecureText) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureText)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Escape-UrlPart([string]$Value) {
    [uri]::EscapeDataString($Value)
}

if ($env:DORION_UPSTREAM_PROXY) {
    $upstream = $env:DORION_UPSTREAM_PROXY
} elseif (Test-Path $ConfigPath) {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $upstream = $config.proxy_url
} else {
    if (-not $ProxyHost) {
        $ProxyHost = Read-Host "Proxy host"
    }
    if (-not $ProxyPort) {
        $ProxyPort = [int](Read-Host "Proxy port")
    }
    if (-not $ProxyUser) {
        $ProxyUser = Read-Host "Proxy username"
    }
    if (-not $ProxyPassword) {
        $ProxyPassword = ConvertTo-PlainText (Read-Host "Proxy password" -AsSecureString)
    }

    $escapedUser = Escape-UrlPart $ProxyUser
    $escapedPassword = Escape-UrlPart $ProxyPassword
    $upstream = "http://${escapedUser}:${escapedPassword}@${ProxyHost}:${ProxyPort}"
}

$env:DORION_UPSTREAM_PROXY = $upstream

$bridgePath = Join-Path $Root "proxy_bridge.py"
$bridgeArgs = @(
    $bridgePath,
    "--listen",
    $Listen
)

$bridgeProcess = $null
$dorionProcess = $null

try {
    $bridgeProcess = Start-Process -WindowStyle Hidden -FilePath "python" -ArgumentList $bridgeArgs -WorkingDirectory $Root -PassThru
    Start-Sleep -Milliseconds 500

    if ($bridgeProcess.HasExited) {
        throw "Proxy bridge failed to start. Port $Listen may already be in use."
    }

    $dorionProcess = Start-Process -FilePath (Join-Path $Root "Dorion.exe") -ArgumentList @("--proxy", "http://$Listen") -WorkingDirectory $Root -PassThru
    $dorionProcess.WaitForExit()
} finally {
    if ($bridgeProcess -and -not $bridgeProcess.HasExited) {
        Stop-Process -Id $bridgeProcess.Id -Force -ErrorAction SilentlyContinue
        try {
            $bridgeProcess.WaitForExit(3000) | Out-Null
        } catch {
        }
    }
}
