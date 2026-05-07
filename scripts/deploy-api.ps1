#!/usr/bin/env pwsh
# Build + deploy the chosen backend (BACKEND_LANGUAGE) to the Function App
# provisioned by Bicep. Used as the `postprovision` hook so `azd up` does the
# right thing for all three runtimes — including .NET on Flex Consumption,
# which azd 1.24's built-in deploy can't handle.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$lang = if ($env:BACKEND_LANGUAGE) { $env:BACKEND_LANGUAGE } else { 'node' }

Write-Host "deploy-api: building backend ($lang)"
& (Join-Path $root 'scripts/build-api.ps1')
if ($LASTEXITCODE -ne 0) { throw "build-api.ps1 failed" }

$rg = (azd env get-value AZURE_RESOURCE_GROUP 2>$null)
if (-not $rg) {
  $envName = (azd env get-value AZURE_ENV_NAME)
  $rg = "rg-$envName"
}
$app = (azd env get-value SERVICE_API_NAME 2>$null)
if (-not $app) {
  $app = (az functionapp list -g $rg --query "[0].name" -o tsv)
}

Write-Host "deploy-api: target = $rg / $app"

$zip = Join-Path ([System.IO.Path]::GetTempPath()) "api-$(Get-Random).zip"
Compress-Archive -Path (Join-Path $root 'src/api/*') -DestinationPath $zip -Force

$size = (Get-Item $zip).Length
Write-Host "deploy-api: uploading $size bytes"
az functionapp deployment source config-zip `
  --resource-group $rg `
  --name $app `
  --src $zip `
  --build-remote false `
  --only-show-errors
if ($LASTEXITCODE -ne 0) { throw "az functionapp deployment failed" }

Remove-Item $zip -Force -ErrorAction SilentlyContinue
Write-Host "deploy-api: done"
