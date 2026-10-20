param(
  [Parameter(Mandatory=$true)][string]$OperatorFile,
  [Parameter(Mandatory=$true)][string]$RecipientFile,
  [Parameter(Mandatory=$true)][string]$IdentityFile,
  [Parameter(Mandatory=$true)][string]$Destination,
  [Parameter(Mandatory=$true)][string]$AgeDirectory,
  [string]$BashPath = 'C:\Program Files\Git\bin\bash.exe'
)
$ErrorActionPreference = 'Stop'
$env:PATH = "$AgeDirectory;$env:PATH"
$env:OPERATOR_ENV = $OperatorFile.Replace('\', '/')
$env:AGE_RECIPIENT_FILE = $RecipientFile.Replace('\', '/')
$env:AGE_IDENTITY_FILE = $IdentityFile.Replace('\', '/')
$env:DESTINATION_ROOT = $Destination.Replace('\', '/')
$scriptFile = Join-Path $PSScriptRoot 'pull_encrypted_backup.sh'
# Git Bash accepts absolute Windows paths; all archive bytes stay in its native
# pipe from SSH to age. Never route binary stdout through Windows PowerShell.
& $BashPath $scriptFile.Replace('\', '/')
exit $LASTEXITCODE
