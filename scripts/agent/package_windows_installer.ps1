param(
  [Parameter(Mandatory = $true)]
  [string]$BundlePath,

  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,

  [Parameter(Mandatory = $true)]
  [string]$MakensisPath,

  [string]$PackageVersionOverride = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
  Write-Error 'Windows installer builder chỉ hỗ trợ Windows.'
  exit 65
}

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$bundle = [IO.Path]::GetFullPath($BundlePath)
$output = [IO.Path]::GetFullPath($OutputDirectory)
$makensis = [IO.Path]::GetFullPath($MakensisPath)

foreach ($path in @($bundle, $makensis)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Không tìm thấy package input: $path"
  }
}
if (-not (Test-Path -LiteralPath $bundle -PathType Container)) {
  throw "Windows bundle không phải directory: $bundle"
}

$requiredFiles = @(
  'hyper_authenticator.exe',
  'flutter_windows.dll',
  'data/flutter_assets/AssetManifest.bin'
)
foreach ($relativePath in $requiredFiles) {
  $requiredPath = Join-Path $bundle $relativePath
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Windows release bundle thiếu: $relativePath"
  }
}

$forbidden = @(Get-ChildItem -LiteralPath $bundle -Recurse -File | Where-Object {
  $_.Name -match '(^|\.)env($|\.)' -or
  $_.Extension -in @('.map', '.pdb', '.ilk', '.exp', '.lib')
})
if ($forbidden.Count -gt 0) {
  $relative = @($forbidden | ForEach-Object {
    [IO.Path]::GetRelativePath($bundle, $_.FullName)
  }) -join ', '
  throw "Windows release bundle chứa debug/config artifact: $relative"
}

$pubspec = Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml')
$versionLine = $pubspec | Where-Object { $_ -match '^version:\s*(\S+)\s*$' } |
  Select-Object -First 1
if (-not $versionLine) {
  throw 'Không đọc được version từ pubspec.yaml.'
}
$packageVersion = if ($PackageVersionOverride) {
  $PackageVersionOverride
} else {
  [regex]::Match($versionLine, '^version:\s*(\S+)\s*$').Groups[1].Value
}

$versionMatch = [regex]::Match(
  $packageVersion,
  '^(\d+)\.(\d+)\.(\d+)\+(\d+)(?:~ci)?$'
)
if (-not $versionMatch.Success) {
  throw "Windows package version không hợp lệ: $packageVersion"
}
$windowsVersion = @(
  $versionMatch.Groups[1].Value,
  $versionMatch.Groups[2].Value,
  $versionMatch.Groups[3].Value,
  $versionMatch.Groups[4].Value
) -join '.'

New-Item -ItemType Directory -Path $output -Force | Out-Null
$installerName = "hyper-authenticator-$packageVersion-windows-x64-setup.exe"
$installerPath = Join-Path $output $installerName
$scriptPath = Join-Path $root 'packaging/windows/installer.nsi'
$iconPath = Join-Path $root 'windows/runner/resources/app_icon.ico'
$licensePath = Join-Path $root 'LICENSE'
$noticePath = Join-Path $root 'packaging/windows/THIRD_PARTY_NOTICES.txt'

foreach ($path in @($scriptPath, $iconPath, $licensePath, $noticePath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Thiếu Windows packaging source: $path"
  }
}

$compilerArguments = @(
  '/V4',
  "/DAPP_SOURCE=$bundle",
  "/DOUTPUT_FILE=$installerPath",
  "/DAPP_VERSION=$packageVersion",
  "/DWINDOWS_VERSION=$windowsVersion",
  "/DAPP_ICON=$iconPath",
  "/DLICENSE_FILE=$licensePath",
  "/DNOTICE_FILE=$noticePath",
  $scriptPath
)
& $makensis @compilerArguments
if ($LASTEXITCODE -ne 0) {
  throw "makensis thất bại: $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
  throw "NSIS không tạo installer: $installerPath"
}

$signature = Get-AuthenticodeSignature -LiteralPath $installerPath
if ($signature.Status -ne 'NotSigned') {
  throw "Unsigned candidate có trạng thái chữ ký ngoài dự kiến: $($signature.Status)"
}

$versionInfo = (Get-Item -LiteralPath $installerPath).VersionInfo
if ($versionInfo.FileVersion -ne $windowsVersion -or
    $versionInfo.ProductVersion -ne $packageVersion) {
  throw "Installer version metadata không khớp: $($versionInfo.FileVersion) / $($versionInfo.ProductVersion)"
}

$hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = "$installerPath.sha256"
[IO.File]::WriteAllText(
  $checksumPath,
  "$hash  $installerName$([Environment]::NewLine)",
  [Text.Encoding]::ASCII
)

Write-Output "WINDOWS_INSTALLER_PATH=$installerPath"
Write-Output "WINDOWS_INSTALLER_VERSION=$packageVersion"
Write-Output "WINDOWS_INSTALLER_SHA256=$hash"
