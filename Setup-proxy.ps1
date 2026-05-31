$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root "proxy-config.json"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function ConvertTo-ProxyUrl([string]$Value) {
    $value = $Value.Trim()
    if (-not $value) {
        throw "Proxy value is empty."
    }

    if ($value -notmatch "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        $parts = $value.Split(":")
        if ($parts.Count -eq 4 -and $parts[0] -match "^[^@/]+$") {
            $hostPart = [uri]::EscapeDataString($parts[2])
            $passwordPart = [uri]::EscapeDataString($parts[3])
            return "http://$hostPart`:$passwordPart@$($parts[0]):$($parts[1])"
        }

        $value = "http://$value"
    }

    $uri = [uri]$value
    if ($uri.Scheme -ne "http") {
        throw "Only HTTP proxies are supported. Use http://..."
    }
    if (-not $uri.Host -or $uri.Port -le 0) {
        throw "Proxy must include host and port."
    }

    return $uri.AbsoluteUri
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Dorion proxy setup"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(520, 150)

$label = New-Object System.Windows.Forms.Label
$label.Text = "Proxy:"
$label.Location = New-Object System.Drawing.Point(12, 18)
$label.Size = New-Object System.Drawing.Size(70, 24)
$form.Controls.Add($label)

$input = New-Object System.Windows.Forms.TextBox
$input.Location = New-Object System.Drawing.Point(84, 15)
$input.Size = New-Object System.Drawing.Size(420, 24)
$input.Anchor = "Top,Left,Right"
$form.Controls.Add($input)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "Examples: http://login:password@host:port  or  host:port:login:password"
$hint.Location = New-Object System.Drawing.Point(84, 45)
$hint.Size = New-Object System.Drawing.Size(420, 35)
$form.Controls.Add($hint)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "Save"
$saveButton.Location = New-Object System.Drawing.Point(328, 105)
$saveButton.Size = New-Object System.Drawing.Size(84, 28)
$saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $saveButton
$form.Controls.Add($saveButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"
$cancelButton.Location = New-Object System.Drawing.Point(420, 105)
$cancelButton.Size = New-Object System.Drawing.Size(84, 28)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

if (Test-Path $ConfigPath) {
    try {
        $existing = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        $input.Text = $existing.proxy_url
    } catch {
    }
}

if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    exit 0
}

try {
    $proxyUrl = ConvertTo-ProxyUrl $input.Text
    [pscustomobject]@{
        proxy_url = $proxyUrl
    } | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8

    [System.Windows.Forms.MessageBox]::Show(
        "Proxy settings saved.",
        "Dorion proxy setup",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        $_.Exception.Message,
        "Dorion proxy setup error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
