param(
  [string]$Version = $env:RPATH_VERSION,
  [string]$InstallDir = $env:RPATH_INSTALL_DIR,
  [switch]$Yes,
  [switch]$NoPath,
  [string]$InstallWrappers = $env:RPATH_INSTALL_WRAPPERS,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Repo = "builtbyjonas/rpath"

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = "latest"
}
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
  $InstallDir = Join-Path (Join-Path $env:LOCALAPPDATA "Programs") "rpath\bin"
}
if ([string]::IsNullOrWhiteSpace($InstallWrappers)) {
  $InstallWrappers = "ask"
}
$InstallWrappers = $InstallWrappers.ToLowerInvariant()
if (@("ask", "yes", "no", "all") -notcontains $InstallWrappers) {
  throw "-InstallWrappers must be one of: ask, yes, no, all"
}

function Resolve-RpathArtifact {
  if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "install.ps1 only supports Windows"
  }

  $arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
  switch ($arch) {
    "x64" { $name = "rpath-windows-x86_64" }
    "arm64" { $name = "rpath-windows-aarch64" }
    default { throw "unsupported Windows architecture: $arch" }
  }

  [pscustomobject]@{
    Artifact = $name
    Archive = "$name.zip"
    Checksum = "$name.zip.sha256"
    Binary = "rpath.exe"
  }
}

function Get-ReleaseBaseUrl {
  if ($Version -eq "latest") {
    return "https://github.com/$Repo/releases/latest/download"
  }
  if ($Version.StartsWith("v")) {
    $tag = $Version
  } else {
    $tag = "v$Version"
  }
  "https://github.com/$Repo/releases/download/$tag"
}

function Get-InstallRoot {
  param([string]$Directory)
  if ((Split-Path -Leaf $Directory) -ieq "bin") {
    return Split-Path -Parent $Directory
  }
  $Directory
}

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

function Add-UserPathEntry {
  param([string]$Entry)
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (Test-PathEntry -PathValue $userPath -Entry $Entry) {
    return $false
  }

  if ($DryRun) {
    Write-Host "dry run: would add $Entry to the user PATH"
    return $true
  }

  if ([string]::IsNullOrWhiteSpace($userPath)) {
    $newPath = $Entry
  } else {
    $newPath = "$userPath;$Entry"
  }
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  if (-not (Test-PathEntry -PathValue $env:Path -Entry $Entry)) {
    $env:Path = "$Entry;$env:Path"
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

function Invoke-WrapperInstall {
  param([string]$Mode, [string]$BinaryPath)
  if ($Mode -eq "all") {
    if ($DryRun) {
      Write-Host "dry run: would run $BinaryPath install --all"
    } else {
      & $BinaryPath install --all
    }
    return
  }

  $shell = Get-DetectedShell
  if ($DryRun) {
    Write-Host "dry run: would run $BinaryPath install --shell $shell"
  } else {
    & $BinaryPath install --shell $shell
  }
}

function Maybe-InstallWrappers {
  param([string]$BinaryPath)
  switch ($InstallWrappers) {
    "no" {
      Write-Host "skipping shell wrapper installation"
    }
    "yes" {
      Invoke-WrapperInstall -Mode "yes" -BinaryPath $BinaryPath
    }
    "all" {
      Invoke-WrapperInstall -Mode "all" -BinaryPath $BinaryPath
    }
    "ask" {
      if ($Yes) {
        Invoke-WrapperInstall -Mode "yes" -BinaryPath $BinaryPath
      } elseif (Read-YesNo "Install the rpath shell wrapper for this PowerShell now?") {
        Invoke-WrapperInstall -Mode "yes" -BinaryPath $BinaryPath
      } else {
        Write-Host "skipping shell wrapper installation; run rpath install later if you want live PATH refresh"
      }
    }
  }
}

$artifact = Resolve-RpathArtifact
$baseUrl = Get-ReleaseBaseUrl
$archiveUrl = "$baseUrl/$($artifact.Archive)"
$checksumUrl = "$baseUrl/$($artifact.Checksum)"
$binaryPath = Join-Path $InstallDir $artifact.Binary
$installRoot = Get-InstallRoot -Directory $InstallDir
$metadataPath = Join-Path $installRoot "install.json"

Write-Host "rpath installer"
Write-Host "artifact: $($artifact.Archive)"
Write-Host "install directory: $InstallDir"

if ($DryRun) {
  Write-Host "dry run: would download $archiveUrl"
  Write-Host "dry run: would verify $checksumUrl"
  Write-Host "dry run: would install $binaryPath"
  if (-not $NoPath) {
    Write-Host "dry run: would add $InstallDir to the user PATH if missing"
  }
  Maybe-InstallWrappers -BinaryPath $binaryPath
  return
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "rpath-install-$PID"
Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
  $archivePath = Join-Path $tempRoot $artifact.Archive
  $checksumPath = Join-Path $tempRoot $artifact.Checksum
  $extractDir = Join-Path $tempRoot "extract"
  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

  Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing
  Invoke-WebRequest -Uri $checksumUrl -OutFile $checksumPath -UseBasicParsing

  $checksumText = Get-Content -Raw -LiteralPath $checksumPath
  $expected = [regex]::Match($checksumText, "(?i)\b[0-9a-f]{64}\b").Value.ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($expected)) {
    throw "sha256 file did not contain a valid checksum"
  }
  $actual = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $expected) {
    throw "checksum mismatch for $($artifact.Archive): expected $expected, got $actual"
  }

  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDir -Force
  $foundBinary = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter $artifact.Binary | Select-Object -First 1
  if (-not $foundBinary) {
    throw "archive did not contain $($artifact.Binary)"
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item -LiteralPath $foundBinary.FullName -Destination $binaryPath -Force

  $pathAdded = $false
  if (-not $NoPath) {
    $pathAdded = Add-UserPathEntry -Entry $InstallDir
    if ($pathAdded -and -not $DryRun) {
      Write-Host "added $InstallDir to the user PATH"
    }
  }

  New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
  [pscustomobject]@{
    installDir = $InstallDir
    binary = $binaryPath
    pathAdded = $pathAdded
  } | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding UTF8

  Write-Host "installed rpath to $binaryPath"
  Maybe-InstallWrappers -BinaryPath $binaryPath
  Write-Host "open a new terminal, then run: rpath --version"
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
