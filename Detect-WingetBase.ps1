# Detect-WingetBase.ps1

try {
    # 1. Resolve Path to the latest winget.exe
    # We look for the executable in the standard location
    $winget_path = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Sort-Object Path | Select-Object -Last 1

    if (-not $winget_path) {
        Write-Output "Winget executable not found."
        Exit 1
    }

    # 2. FUNCTIONAL TEST
    # We run the command. If it prints anything (version string, etc), it works.
    # If it returns $null, it is suffering from the "OOBE Silent Failure" and needs reinstall.
    $TestRun = & $winget_path.Path --version 2>&1

    if (-not [string]::IsNullOrWhiteSpace($TestRun)) {
        Write-Output "Detected and Functional. Output: $TestRun"
        Exit 0
    }
    else {
        Write-Output "Detected binary but it failed to produce output (Silent Failure)."
        Exit 1
    }
}
catch {
    Write-Output "Error during detection: $_"
    Exit 1
}