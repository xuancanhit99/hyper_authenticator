param(
  [Parameter(Mandatory = $true)]
  [string]$EnvFile,

  [Parameter(Mandatory = $true)]
  [string]$Confirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Confirmation -ne '--allow-test-vault-reset') {
  Write-Error 'Usage: windows_integration.ps1 -EnvFile FILE -Confirmation --allow-test-vault-reset'
  exit 64
}

if (-not $IsWindows) {
  Write-Error 'Từ chối chạy: harness này chỉ hỗ trợ Windows.'
  exit 65
}

if ($env:CI -ne 'true' -or
    $env:GITHUB_ACTIONS -ne 'true' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows') {
  Write-Error 'Từ chối chạy: chỉ được reset vault trên GitHub-hosted Windows runner tạm.'
  exit 65
}

if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
  Write-Error "Không tìm thấy public runtime config: $EnvFile"
  exit 66
}

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$envFilePath = (Resolve-Path -LiteralPath $EnvFile).Path
$sandbox = Join-Path $env:RUNNER_TEMP "hyper-auth-windows-integration-$PID"
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA

New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
$env:APPDATA = Join-Path $sandbox 'Roaming'
$env:LOCALAPPDATA = Join-Path $sandbox 'Local'
New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force |
  Out-Null

try {
  Push-Location $root
  try {
    & dart run tool/agent/check_release_config.dart $envFilePath
    if ($LASTEXITCODE -ne 0) {
      throw "Release config validator thất bại: $LASTEXITCODE"
    }

    & flutter test integration_test/local_vault_smoke_test.dart `
      --device-id windows `
      "--dart-define-from-file=$envFilePath" `
      --dart-define=ALLOW_DEVICE_TEST_VAULT_RESET=true
    if ($LASTEXITCODE -ne 0) {
      throw "Windows local-vault integration thất bại: $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
} finally {
  $env:APPDATA = $originalAppData
  $env:LOCALAPPDATA = $originalLocalAppData
  if (Test-Path -LiteralPath $sandbox) {
    [IO.Directory]::Delete($sandbox, $true)
  }
}

Write-Output 'Windows local-vault integration pass: UI, secure storage, lifecycle và cleanup.'
