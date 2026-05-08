# Install-WingetBase.ps1 — Merged: PSGallery First + Sideload Fallback

$ErrorActionPreference = "Stop"

if ($Env:ProgramW6432) { $Path_local = "$Env:ProgramW6432\_MEM" } else { $Path_local = "$Env:ProgramFiles\_MEM" }
$LogPath = "$Path_local\Log"
$StagingPath = "$Path_local\WingetStaging"

if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Force -Path $LogPath | Out-Null }
Start-Transcript -Path "$LogPath\WingetBase-Install.log" -Force -Append

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Helper Function: Test if WinGet is functional, returns version or $null ---
function Get-WingetStatus {
    try {
        $exe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
            Sort-Object Path | Select-Object -Last 1
        if (-not $exe) { return $null }
        $out = & $exe.Path --version 2>&1
        if (-not [string]::IsNullOrWhiteSpace($out)) { return $out.Trim() }
        return $null
    } catch { return $null }
}

# --- Pre-check: Already functional? ---
$currentVersion = Get-WingetStatus
if ($currentVersion) {
    Write-Output "PRE-CHECK: WinGet already functional. Version: $currentVersion"
    Stop-Transcript
    Exit 0
}

$exePath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
    Sort-Object Path | Select-Object -Last 1
if ($exePath) {
    Write-Output "PRE-CHECK: WinGet binary found at $($exePath.Path) but not functional (Silent Failure)."
} else {
    Write-Output "PRE-CHECK: WinGet binary not found."
}

Write-Output "Starting install..."

# =====================================================
# METHOD 1: PSGallery / Repair-WinGetPackageManager
# =====================================================
$method1Success = $false
try {
    Write-Output "=== METHOD 1: PSGallery / Repair-WinGetPackageManager ==="

    if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Output "Installing NuGet Provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
    }

    Write-Output "Setting PSGallery to Trusted..."
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction SilentlyContinue

    Write-Output "Installing Microsoft.WinGet.Client Module..."
    Install-Module -Name Microsoft.WinGet.Client -Scope AllUsers -Force -AllowClobber

    Import-Module Microsoft.WinGet.Client -Force

    Write-Output "Running Repair-WinGetPackageManager..."
    Repair-WinGetPackageManager -Latest -Verbose

    for ($i = 1; $i -le 6; $i++) {
        Write-Output "PSGallery verification attempt $i of 6..."
        Start-Sleep -Seconds 10
        $version = Get-WingetStatus
        if ($version) {
            Write-Output "METHOD 1 SUCCESS: WinGet is functional. Version: $version"
            $method1Success = $true
            break
        }
        Write-Output "Not ready yet..."
    }

    if (-not $method1Success) {
        Write-Output "METHOD 1: Repair completed but WinGet not yet functional. Will try fallback."
    }
}
catch {
    Write-Output "METHOD 1 FAILED: $($_.Exception.Message)"
}

# =====================================================
# METHOD 2: Direct Sideload Fallback (ESP-safe)
# =====================================================
if (-not $method1Success) {
    try {
        Write-Output "=== METHOD 2: Direct Sideload Fallback ==="

        if (!(Test-Path $StagingPath)) { New-Item -ItemType Directory -Force -Path $StagingPath | Out-Null }

        $VCLibsURL  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $XamlURL    = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
        $WingetURL  = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $LicenseURL = "https://github.com/microsoft/winget-cli/releases/latest/download/License1.xml"

        $VCLibsFile  = "$StagingPath\VCLibs.appx"
        $XamlFile    = "$StagingPath\UIXaml.appx"
        $WingetFile  = "$StagingPath\DesktopAppInstaller.msixbundle"
        $LicenseFile = "$StagingPath\License1.xml"

        Write-Output "Downloading VCLibs..."
        Invoke-WebRequest -Uri $VCLibsURL -OutFile $VCLibsFile -UseBasicParsing -TimeoutSec 120

        Write-Output "Downloading UI.Xaml..."
        Invoke-WebRequest -Uri $XamlURL -OutFile $XamlFile -UseBasicParsing -TimeoutSec 120

        Write-Output "Downloading WinGet MSIX bundle..."
        Invoke-WebRequest -Uri $WingetURL -OutFile $WingetFile -UseBasicParsing -TimeoutSec 300

        Write-Output "Downloading License..."
        Invoke-WebRequest -Uri $LicenseURL -OutFile $LicenseFile -UseBasicParsing -TimeoutSec 60

        Write-Output "Installing via Add-AppxProvisionedPackage..."
        Add-AppxProvisionedPackage -Online `
            -PackagePath $WingetFile `
            -DependencyPackagePath @($VCLibsFile, $XamlFile) `
            -LicensePath $LicenseFile

        for ($i = 1; $i -le 6; $i++) {
            Write-Output "Sideload verification attempt $i of 6..."
            Start-Sleep -Seconds 10
            $version = Get-WingetStatus
            if ($version) {
                Write-Output "METHOD 2 SUCCESS: WinGet is functional. Version: $version"
                Remove-Item -Path $StagingPath -Recurse -Force -ErrorAction SilentlyContinue
                Stop-Transcript
                Exit 0
            }
            Write-Output "Not ready yet..."
        }

        Throw "METHOD 2: Sideload completed but WinGet still not functional after 60 seconds."
    }
    catch {
        Write-Error "METHOD 2 FAILED: $($_.Exception.Message)"
        Remove-Item -Path $StagingPath -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Transcript
        Exit 1
    }
}

Write-Output "Install Complete."
Stop-Transcript
Exit 0
