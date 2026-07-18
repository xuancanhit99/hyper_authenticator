param(
  [Parameter(Mandatory = $true)]
  [string]$EnvFile,

  [Parameter(Mandatory = $true)]
  [string]$Confirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$historicalCommit = '8e381debfe680ac906de391b4d9274e49acf9c06'
$historicalVersion = '1.0.0+9'
$canonicalProductName = 'hyper_authenticator'
$alternateProductName = 'Hyper Authenticator'

if ($Confirmation -ne '--allow-historical-vault-migration') {
  Write-Error 'Usage: windows_historical_upgrade.ps1 -EnvFile FILE -Confirmation --allow-historical-vault-migration'
  exit 64
}
if (-not $IsWindows -or
    $env:CI -ne 'true' -or
    $env:GITHUB_ACTIONS -ne 'true' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows') {
  Write-Error 'Từ chối chạy: historical vault gate chỉ dành cho GitHub-hosted Windows runner tạm.'
  exit 65
}
if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
  Write-Error "Không tìm thấy public runtime config: $EnvFile"
  exit 66
}

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$envFilePath = (Resolve-Path -LiteralPath $EnvFile).Path
$sandbox = Join-Path $env:RUNNER_TEMP "hyper-auth-historical-upgrade-$PID"
$archive = Join-Path $sandbox 'historical.zip'
$historicalRoot = Join-Path $sandbox 'source'
$roaming = [Environment]::GetFolderPath(
  [Environment+SpecialFolder]::ApplicationData
)
$companyDirectory = Join-Path $roaming 'app.hyperz.authenticator'
$canonicalDirectory = Join-Path $companyDirectory $canonicalProductName
$alternateDirectory = Join-Path $companyDirectory $alternateProductName

function Remove-TestStorageLayouts {
  foreach ($path in @($canonicalDirectory, $alternateDirectory)) {
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }
}

New-Item -ItemType Directory -Path $sandbox, $historicalRoot -Force |
  Out-Null

try {
  Push-Location $root
  try {
    git cat-file -e "$historicalCommit^{commit}"
    if ($LASTEXITCODE -ne 0) {
      throw "Không tìm thấy historical commit $historicalCommit."
    }
    git archive --format=zip --output=$archive $historicalCommit
    if ($LASTEXITCODE -ne 0) {
      throw "Không thể archive historical commit $historicalCommit."
    }
  } finally {
    Pop-Location
  }

  Expand-Archive -LiteralPath $archive -DestinationPath $historicalRoot
  $historicalPubspecPath = Join-Path $historicalRoot 'pubspec.yaml'
  $historicalPubspec = [IO.File]::ReadAllText($historicalPubspecPath)
  if ($historicalPubspec -notmatch [regex]::Escape("version: $historicalVersion")) {
    throw "Historical source không có version $historicalVersion."
  }
  $dependencyAnchor = "dev_dependencies:`n  flutter_test:"
  if (-not $historicalPubspec.Contains($dependencyAnchor)) {
    throw 'Không tìm thấy dev_dependencies anchor trong historical pubspec.'
  }
  $historicalPubspec = $historicalPubspec.Replace(
    $dependencyAnchor,
    "dev_dependencies:`n  integration_test:`n    sdk: flutter`n  flutter_test:"
  )
  [IO.File]::WriteAllText($historicalPubspecPath, $historicalPubspec)

  [IO.File]::WriteAllText(
    (Join-Path $historicalRoot '.env'),
    "SUPABASE_URL=https://example.invalid`nSUPABASE_ANON_KEY=TEST_ONLY_PUBLIC_KEY`n"
  )
  $historicalIntegrationDirectory = Join-Path $historicalRoot 'integration_test'
  New-Item -ItemType Directory -Path $historicalIntegrationDirectory -Force |
    Out-Null
  Copy-Item `
    -LiteralPath (Join-Path $root 'tool/fixtures/windows_historical_seed_test.dart') `
    -Destination (Join-Path $historicalIntegrationDirectory 'windows_historical_seed_test.dart')

  Remove-TestStorageLayouts

  Push-Location $historicalRoot
  try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
      throw "Historical flutter pub get thất bại: $LASTEXITCODE"
    }
    $historicalLock = [IO.File]::ReadAllText(
      (Join-Path $historicalRoot 'pubspec.lock')
    )
    if ($historicalLock -notmatch '(?ms)flutter_secure_storage_windows:\s+dependency: transitive.*?version: "3\.1\.2"') {
      throw 'Historical dependency drift: cần flutter_secure_storage_windows 3.1.2.'
    }

    flutter test integration_test/windows_historical_seed_test.dart `
      --device-id windows `
      --dart-define=ALLOW_WINDOWS_HISTORICAL_VAULT_MUTATION=true
    if ($LASTEXITCODE -ne 0) {
      throw "Historical Windows seed thất bại: $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $legacyFiles = @(
    Get-ChildItem -LiteralPath $canonicalDirectory -Filter '*.secure' -File
  )
  if ($legacyFiles.Count -lt 2) {
    throw 'Bản lịch sử không tạo đủ index/account .secure trong canonical AppData.'
  }

  Push-Location $root
  try {
    dart run tool/agent/check_release_config.dart $envFilePath
    if ($LASTEXITCODE -ne 0) {
      throw "Release config validator thất bại: $LASTEXITCODE"
    }
    flutter test integration_test/windows_historical_upgrade_test.dart `
      --device-id windows `
      "--dart-define-from-file=$envFilePath" `
      --dart-define=ALLOW_WINDOWS_HISTORICAL_VAULT_MUTATION=true
    if ($LASTEXITCODE -ne 0) {
      throw "Current Windows historical upgrade thất bại: $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }
} finally {
  Remove-TestStorageLayouts
  if (Test-Path -LiteralPath $sandbox) {
    [IO.Directory]::Delete($sandbox, $true)
  }
}

Write-Output 'Windows historical upgrade pass: 1.0.0+9 legacy storage -> current COW v2, field round-trip và cleanup.'
