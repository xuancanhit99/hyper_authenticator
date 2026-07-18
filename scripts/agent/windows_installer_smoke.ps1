param(
  [Parameter(Mandatory = $true)]
  [string]$BaselineInstaller,

  [Parameter(Mandatory = $true)]
  [string]$CurrentInstaller,

  [Parameter(Mandatory = $true)]
  [string]$Confirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Confirmation -ne '--allow-ephemeral-install') {
  Write-Error 'Usage: windows_installer_smoke.ps1 -BaselineInstaller FILE -CurrentInstaller FILE -Confirmation --allow-ephemeral-install'
  exit 64
}
if (-not $IsWindows -or
    $env:CI -ne 'true' -or
    $env:GITHUB_ACTIONS -ne 'true' -or
    $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows') {
  Write-Error 'Từ chối chạy: installer smoke chỉ dành cho GitHub-hosted Windows runner tạm.'
  exit 65
}

$baseline = (Resolve-Path -LiteralPath $BaselineInstaller).Path
$current = (Resolve-Path -LiteralPath $CurrentInstaller).Path

function Assert-Checksum([string]$InstallerPath) {
  $checksumPath = "$InstallerPath.sha256"
  if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
    throw "Thiếu checksum: $checksumPath"
  }
  $expected = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
  $actual = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($expected -ne $actual) {
    throw "Installer checksum không khớp: $InstallerPath"
  }
  $signature = Get-AuthenticodeSignature -LiteralPath $InstallerPath
  if ($signature.Status -ne 'NotSigned') {
    throw "Candidate phải unsigned trước release signing gate: $($signature.Status)"
  }
}

function Invoke-SilentInstaller([string]$InstallerPath, [string]$InstallPath) {
  $process = Start-Process -FilePath $InstallerPath `
    -ArgumentList @('/S', "/D=$InstallPath") `
    -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Installer thất bại với exit code $($process.ExitCode)."
  }
}

function Assert-ReleaseLaunch([string]$ExecutablePath) {
  $process = Start-Process -FilePath $ExecutablePath -PassThru
  try {
    Start-Sleep -Seconds 8
    if ($process.HasExited) {
      throw "Installed release thoát sớm với exit code $($process.ExitCode)."
    }
  } finally {
    if (-not $process.HasExited) {
      $null = $process.CloseMainWindow()
      if (-not $process.WaitForExit(5000)) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
      }
    }
  }
}

Assert-Checksum $baseline
Assert-Checksum $current

$sandbox = Join-Path $env:RUNNER_TEMP "hyper-auth-windows-installer-$PID"
$installPath = Join-Path $sandbox 'program'
$roamingPath = Join-Path $sandbox 'Roaming'
$localPath = Join-Path $sandbox 'Local'
$appDataPath = Join-Path $roamingPath 'app.hyperz.authenticator/Hyper Authenticator'
$sentinelPath = Join-Path $appDataPath 'installer-retention-sentinel.txt'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HyperAuthenticator'
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA

New-Item -ItemType Directory -Path $roamingPath, $localPath -Force | Out-Null
$env:APPDATA = $roamingPath
$env:LOCALAPPDATA = $localPath

try {
  Invoke-SilentInstaller $baseline $installPath
  $installedExecutable = Join-Path $installPath 'hyper_authenticator.exe'
  if (-not (Test-Path -LiteralPath $installedExecutable -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $installPath 'flutter_windows.dll') -PathType Leaf) -or
      -not (Test-Path -LiteralPath $registryPath)) {
    throw 'Baseline installer thiếu executable, runtime DLL hoặc uninstall metadata.'
  }
  Assert-ReleaseLaunch $installedExecutable

  New-Item -ItemType Directory -Path $appDataPath -Force | Out-Null
  [IO.File]::WriteAllText($sentinelPath, 'TEST_ONLY_WINDOWS_INSTALLER_RETENTION')

  Invoke-SilentInstaller $current $installPath
  if (-not (Test-Path -LiteralPath $sentinelPath -PathType Leaf)) {
    throw 'Windows user-data sentinel mất sau installer upgrade.'
  }
  $currentDisplayVersion = (Get-ItemProperty -LiteralPath $registryPath).DisplayVersion
  $expectedDisplayVersion = (Get-Item -LiteralPath $current).VersionInfo.ProductVersion
  if ($currentDisplayVersion -ne $expectedDisplayVersion) {
    throw "Installer upgrade metadata không khớp: $currentDisplayVersion"
  }
  Assert-ReleaseLaunch $installedExecutable

  $uninstaller = Join-Path $installPath 'Uninstall.exe'
  if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
    throw 'Không tìm thấy Windows uninstaller.'
  }
  $uninstallProcess = Start-Process -FilePath $uninstaller `
    -ArgumentList '/S' -Wait -PassThru
  if ($uninstallProcess.ExitCode -ne 0) {
    throw "Uninstaller thất bại với exit code $($uninstallProcess.ExitCode)."
  }

  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while ((Test-Path -LiteralPath $installPath) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
  }
  if (Test-Path -LiteralPath $installPath) {
    throw 'Program directory còn tồn tại sau uninstall.'
  }
  if (Test-Path -LiteralPath $registryPath) {
    throw 'Uninstall metadata còn tồn tại sau uninstall.'
  }
  if (-not (Test-Path -LiteralPath $sentinelPath -PathType Leaf)) {
    throw 'Windows user data bị xóa trong uninstall.'
  }
} finally {
  $env:APPDATA = $originalAppData
  $env:LOCALAPPDATA = $originalLocalAppData
  if (Test-Path -LiteralPath $registryPath) {
    Remove-Item -LiteralPath $registryPath -Recurse -Force
  }
  if (Test-Path -LiteralPath $sandbox) {
    [IO.Directory]::Delete($sandbox, $true)
  }
}

Write-Output 'Windows NSIS smoke pass: install, release launch, upgrade, uninstall và data retention.'
