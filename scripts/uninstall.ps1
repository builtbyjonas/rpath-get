param(
  [string]$InstallDir = $env:RPATH_INSTALL_DIR,
  [switch]$Yes,
  [string]$InstallWrappers = $env:RPATH_INSTALL_WRAPPERS,
  [switch]$Purge,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InstallWrappers)) {
  $InstallWrappers = "ask"
}
$InstallWrappers = $InstallWrappers.ToLowerInvariant()
if (@("ask", "yes", "no", "all") -notcontains $InstallWrappers) {
  throw "-InstallWrappers must be one of: ask, yes, no, all"
}

$defaultRoot = Join-Path (Join-Path $env:LOCALAPPDATA "Programs") "rpath"
$defaultInstallDir = Join-Path $defaultRoot "bin"
$defaultMetadataPath = Join-Path $defaultRoot "install.json"

function Get-InstallRoot {
  param([string]$Directory)
  if ((Split-Path -Leaf $Directory) -ieq "bin") {
    return Split-Path -Parent $Directory
  }
  $Directory
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
  if (Test-Path -LiteralPath $defaultMetadataPath) {
    try {
      $metadata = Get-Content -Raw -LiteralPath $defaultMetadataPath | ConvertFrom-Json
      $InstallDir = [string]$metadata.installDir
    } catch {
      $InstallDir = $defaultInstallDir
    }
  } else {
    $InstallDir = $defaultInstallDir
  }
}

$installRoot = Get-InstallRoot -Directory $InstallDir
$metadataPath = Join-Path $installRoot "install.json"
$binaryPath = Join-Path $InstallDir "rpath.exe"

function Test-PathEntry {
  param([string]$PathValue, [string]$Entry)
  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return $false
  }
  foreach ($part in ($PathValue -split ";")) {
    if ($part.Trim().Equals($Entry, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }
  $false
}

function Remove-UserPathEntry {
  param([string]$Entry)
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not (Test-PathEntry -PathValue $userPath -Entry $Entry)) {
    return $false
  }
  $parts = @()
  foreach ($part in ($userPath -split ";")) {
    $trimmed = $part.Trim()
    if ($trimmed.Length -gt 0 -and -not $trimmed.Equals($Entry, [System.StringComparison]::OrdinalIgnoreCase)) {
      $parts += $trimmed
    }
  }
  $newPath = $parts -join ";"
  if ($DryRun) {
    Write-Host "dry run: would remove $Entry from the user PATH"
  } else {
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $processParts = @()
    foreach ($part in ($env:Path -split ";")) {
      $trimmed = $part.Trim()
      if ($trimmed.Length -gt 0 -and -not $trimmed.Equals($Entry, [System.StringComparison]::OrdinalIgnoreCase)) {
        $processParts += $trimmed
      }
    }
    $env:Path = $processParts -join ";"
    Write-Host "removed $Entry from the user PATH"
  }
  $true
}

function Test-InteractiveHost {
  try {
    $null = $Host.UI.RawUI.KeyAvailable
    return $true
  } catch {
    return $Host.Name -ne "Default Host"
  }
}

function Read-YesNo {
  param([string]$Prompt)
  if (-not (Test-InteractiveHost)) {
    return $false
  }
  try {
    $answer = Read-Host "$Prompt [y/N]"
  } catch {
    return $false
  }
  $answer -match "^(y|yes)$"
}

function Get-DetectedShell {
  if ($PSVersionTable.PSEdition -eq "Core") {
    return "pwsh"
  }
  "powershell"
}

function Get-RpathCommand {
  if (Test-Path -LiteralPath $binaryPath) {
    return $binaryPath
  }
  $command = Get-Command rpath.exe -CommandType Application -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }
  $null
}

function Invoke-WrapperUninstall {
  param([string]$Mode, [string]$RpathCommand)
  if ([string]::IsNullOrWhiteSpace($RpathCommand)) {
    Write-Host "rpath binary not found; skipping shell wrapper removal"
    return
  }

  if ($Mode -eq "all") {
    if ($DryRun) {
      Write-Host "dry run: would run $RpathCommand uninstall --all"
    } else {
      & $RpathCommand uninstall --all
    }
    return
  }

  $shell = Get-DetectedShell
  if ($DryRun) {
    Write-Host "dry run: would run $RpathCommand uninstall --shell $shell"
  } else {
    & $RpathCommand uninstall --shell $shell
  }
}

function Maybe-UninstallWrappers {
  param([string]$RpathCommand)
  switch ($InstallWrappers) {
    "no" {
      Write-Host "skipping shell wrapper removal"
    }
    "yes" {
      Invoke-WrapperUninstall -Mode "yes" -RpathCommand $RpathCommand
    }
    "all" {
      Invoke-WrapperUninstall -Mode "all" -RpathCommand $RpathCommand
    }
    "ask" {
      if ($Yes) {
        Invoke-WrapperUninstall -Mode "yes" -RpathCommand $RpathCommand
      } elseif (Read-YesNo "Remove the rpath shell wrapper for this PowerShell now?") {
        Invoke-WrapperUninstall -Mode "yes" -RpathCommand $RpathCommand
      } else {
        Write-Host "skipping shell wrapper removal"
      }
    }
  }
}

Write-Host "rpath uninstaller"
Write-Host "install directory: $InstallDir"

$rpathCommand = Get-RpathCommand
Maybe-UninstallWrappers -RpathCommand $rpathCommand

Remove-UserPathEntry -Entry $InstallDir | Out-Null

if (Test-Path -LiteralPath $binaryPath) {
  if ($DryRun) {
    Write-Host "dry run: would remove $binaryPath"
  } else {
    Remove-Item -LiteralPath $binaryPath -Force
    Write-Host "removed $binaryPath"
  }
} else {
  Write-Host "binary not found at $binaryPath"
}

if (Test-Path -LiteralPath $metadataPath) {
  if ($DryRun) {
    Write-Host "dry run: would remove install metadata $metadataPath"
  } else {
    Remove-Item -LiteralPath $metadataPath -Force
    Write-Host "removed install metadata"
  }
}

if (-not $DryRun) {
  if (Test-Path -LiteralPath $InstallDir) {
    $remaining = @(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -eq 0) {
      Remove-Item -LiteralPath $InstallDir -Force
    }
  }
  if (Test-Path -LiteralPath $installRoot) {
    $remainingRoot = @(Get-ChildItem -LiteralPath $installRoot -Force -ErrorAction SilentlyContinue)
    if ($remainingRoot.Count -eq 0) {
      Remove-Item -LiteralPath $installRoot -Force
    }
  }
}

if ($Purge) {
  $stateDirs = @(
    (Join-Path $env:APPDATA "rpath"),
    (Join-Path $env:LOCALAPPDATA "rpath")
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

  foreach ($stateDir in $stateDirs) {
    if ($DryRun) {
      Write-Host "dry run: would remove state directory $stateDir"
    } elseif (Test-Path -LiteralPath $stateDir) {
      Remove-Item -LiteralPath $stateDir -Recurse -Force
      Write-Host "removed state directory $stateDir"
    }
  }
}

Write-Host "rpath uninstall complete"
