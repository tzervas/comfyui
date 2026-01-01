param(
  [string]$CaPem = "ssl\\ca.pem"
)

if (-not (Test-Path $CaPem)) {
  Write-Error "CA cert not found: $CaPem"
  exit 2
}

# Extract thumbprint and remove from Local Machine Root store
$tmpCer = Join-Path $env:TEMP "comfyui-stack-ca.cer"

$pem = Get-Content -Raw $CaPem
$base64 = ($pem -split "-----BEGIN CERTIFICATE-----")[1] -split "-----END CERTIFICATE-----" | Select-Object -First 1
$base64 = $base64 -replace "\s",""

[IO.File]::WriteAllBytes($tmpCer, [Convert]::FromBase64String($base64))

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($tmpCer)
$thumb = $cert.Thumbprint
Remove-Item $tmpCer -Force

# Requires admin
certutil -delstore Root $thumb | Out-Host
Write-Host "Removed CA from LocalMachine\\Root (if present)."
