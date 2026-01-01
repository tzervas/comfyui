param(
  [string]$CaPem = "ssl\\ca.pem"
)

if (-not (Test-Path $CaPem)) {
  Write-Error "CA cert not found: $CaPem"
  exit 2
}

# Convert PEM -> CER for certutil
$tmpCer = Join-Path $env:TEMP "comfyui-stack-ca.cer"

$pem = Get-Content -Raw $CaPem
$base64 = ($pem -split "-----BEGIN CERTIFICATE-----")[1] -split "-----END CERTIFICATE-----" | Select-Object -First 1
$base64 = $base64 -replace "\s",""

[IO.File]::WriteAllBytes($tmpCer, [Convert]::FromBase64String($base64))

# Install into Local Machine Root store (requires admin PowerShell)
certutil -addstore -f Root $tmpCer | Out-Host

Remove-Item $tmpCer -Force
Write-Host "Installed CA into LocalMachine\\Root."
