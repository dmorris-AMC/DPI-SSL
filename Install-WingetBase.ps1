# Install-WingetBase.ps1

$ErrorActionPreference = "Stop"

# Use 64-bit Program Files variable for Intune compatibility
if ($Env:ProgramW6432) { $Path_local = "$Env:ProgramW6432\_MEM" } else { $Path_local = "$Env:ProgramFiles\_MEM" }
$LogPath = "$Path_local\Log"

if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Force -Path $LogPath | Out-Null }
Start-Transcript -Path "$LogPath\WingetBase-Install.log" -Force -Append

try {
    Write-Output "Starting Winget Bootstrap via PSGallery Module..."

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
    
    $Result = Repair-WinGetPackageManager -Latest -Verbose
    
    Write-Output "Repair Command Completed. Result Object: $($Result | Out-String)"

    $WingetExe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Sort-Object Path | Select-Object -Last 1
    
    if ($WingetExe) {
        $VersionCheck = & $WingetExe.Path --version 2>&1
        if (-not [string]::IsNullOrWhiteSpace($VersionCheck)) {
            Write-Output "SUCCESS: Winget is active. Output: $VersionCheck"
        } else {
            Throw "Winget installed but returned no output (Silent Failure)."
        }
    } else {
        Throw "Installation finished but executable not found."
    }

    Write-Output "Install Complete."
}
catch {
    Write-Error "FATAL ERROR: $_"
    Stop-Transcript
    Exit 1
}
Stop-Transcript