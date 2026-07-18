param(
  [Parameter(Mandatory = $true)]
  [string]$DestinationDirectory,

  [string]$GitHubEnvPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
  Write-Error 'NSIS tool bootstrap chỉ hỗ trợ Windows.'
  exit 65
}

$nsisVersion = '3.12'
$archiveSha256 = '56581f90db321581c5381193d796fffcf2d24b2f8fed2160a6c6a3baa67f2c4f'
$archiveUrl = 'https://downloads.sourceforge.net/project/nsis/NSIS%203/3.12/nsis-3.12.zip'
$destination = [IO.Path]::GetFullPath($DestinationDirectory)

if (Test-Path -LiteralPath $destination) {
  $existing = @(Get-ChildItem -LiteralPath $destination -Force)
  if ($existing.Count -gt 0) {
    throw "NSIS destination phải rỗng: $destination"
  }
} else {
  New-Item -ItemType Directory -Path $destination -Force | Out-Null
}

$archive = Join-Path $destination "nsis-$nsisVersion.zip"
Invoke-WebRequest -Uri $archiveUrl -OutFile $archive
$actualSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $archiveSha256) {
  throw "NSIS archive checksum không khớp: $actualSha256"
}

Expand-Archive -LiteralPath $archive -DestinationPath $destination
$makensis = Join-Path $destination "nsis-$nsisVersion/Bin/makensis.exe"
if (-not (Test-Path -LiteralPath $makensis -PathType Leaf)) {
  throw "Không tìm thấy makensis.exe sau extract: $makensis"
}

$reportedVersion = (& $makensis /VERSION | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $reportedVersion -ne "v$nsisVersion") {
  throw "NSIS version không đúng: $reportedVersion"
}

if ($GitHubEnvPath) {
  $line = "NSIS_MAKENSIS_PATH=$makensis$([Environment]::NewLine)"
  [IO.File]::AppendAllText(
    $GitHubEnvPath,
    $line,
    [Text.UTF8Encoding]::new($false)
  )
}

Write-Output "NSIS_BOOTSTRAP_VERSION=$reportedVersion"
Write-Output "NSIS_BOOTSTRAP_SHA256=$actualSha256"
