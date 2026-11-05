#requires -Version 5.1
<#
HSCL: HP Color LaserJet Pro MFP 4303fdw one-click printer setup.
Run with Administrator privileges on Windows 10/11 x64.
Requires the vetted HP x64 driver ZIP uploaded to the configured URL.

IMPORTANT: $DriverName must be the EXACT name exposed by the HP driver INF.
The name inherited from the previous deployment has NOT yet been verified.
A mismatch will now fail visibly instead of falsely reporting success.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- CONFIGURATION ---
$ZipUrl       = 'https://raw.githubusercontent.com/Kachiiwox/printer-drivers/main/hp4303fdw_driver.zip'
$PrinterIP    = '192.168.88.101'
$PortName     = "IP_$PrinterIP"
$PrinterName  = 'HP Color LaserJet Pro MFP 4303fdw'
$DriverName   = 'HP Color LaserJet Pro MFP 4301-4303 PCL-6 V4' # Verify against HP INF
$InfFileName  = 'HPOneDriver_V4_x64.inf'

# Optional: set to the verified SHA-256 of the ZIP for integrity protection.
# Leave blank for initial testing ONLY; pin it before company-wide rollout.
$ExpectedZipSHA256 = ''

# --- PRE-FLIGHT ---
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: Run this script as Administrator.' -ForegroundColor Red
    exit 1
}
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host 'ERROR: This HP x64 driver package requires 64-bit Windows.' -ForegroundColor Red
    exit 1
}

$TempDir = Join-Path $env:TEMP ('HSCL_HP4303_' + [guid]::NewGuid().ToString('N'))
$ZipFile = Join-Path $TempDir 'driver.zip'
$success = $false

try {
    Import-Module PrintManagement -ErrorAction Stop
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    Write-Host '[1/6] Downloading HP driver ZIP...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile -UseBasicParsing -ErrorAction Stop
    if ((Get-Item -LiteralPath $ZipFile).Length -lt 1024) {
        throw 'Downloaded file is unexpectedly small; check ZIP URL and GitHub upload.'
    }

    if ($ExpectedZipSHA256) {
        $actualHash = (Get-FileHash -LiteralPath $ZipFile -Algorithm SHA256).Hash
        if ($actualHash -ne $ExpectedZipSHA256) {
            throw "Driver ZIP SHA-256 mismatch. Got $actualHash"
        }
    }

    Write-Host '[2/6] Extracting driver ZIP...' -ForegroundColor Cyan
    $ExtractDir = Join-Path $TempDir 'extracted'
    Expand-Archive -LiteralPath $ZipFile -DestinationPath $ExtractDir -Force -ErrorAction Stop

    # HP's ZIP includes several INF files (IPP, USB, etc.). Never select the first arbitrary INF.
    $matches = @(Get-ChildItem -LiteralPath $ExtractDir -Filter $InfFileName -Recurse -File -ErrorAction Stop)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one $InfFileName in driver ZIP; found $($matches.Count)."
    }
    $InfFile = $matches[0]
    Write-Host "Using correct INF: $($InfFile.FullName)" -ForegroundColor Gray

    Write-Host '[3/6] Staging HP printer driver in Windows...' -ForegroundColor Cyan
    & "$env:SystemRoot\System32\pnputil.exe" /add-driver $InfFile.FullName /install
    if ($LASTEXITCODE -ne 0) {
        throw "PnPUtil failed with exit code $LASTEXITCODE."
    }

    Write-Host '[4/6] Registering the HP print driver...' -ForegroundColor Cyan
    $driver = Get-PrinterDriver -ErrorAction Stop | Where-Object { $_.Name -eq $DriverName } | Select-Object -First 1
    if (-not $driver) {
        try {
            Add-PrinterDriver -Name $DriverName -ErrorAction Stop
        }
        catch {
            throw "Windows could not register driver name '$DriverName'. Verify its exact model name in $InfFileName. Original error: $($_.Exception.Message)"
        }
    }
    $driver = Get-PrinterDriver -ErrorAction Stop | Where-Object { $_.Name -eq $DriverName } | Select-Object -First 1
    if (-not $driver) {
        throw "Driver '$DriverName' was not registered in the Windows print subsystem."
    }

    Write-Host '[5/6] Configuring TCP/IP port...' -ForegroundColor Cyan
    $port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if (-not $port) {
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP -ErrorAction Stop
    }
    elseif ($port.PrinterHostAddress -ne $PrinterIP) {
        throw "Port '$PortName' already exists but points to '$($port.PrinterHostAddress)', not '$PrinterIP'."
    }

    Write-Host '[6/6] Creating/verifying printer...' -ForegroundColor Cyan
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if (-not $printer) {
        Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName -ErrorAction Stop
    }
    else {
        if ($printer.DriverName -ne $DriverName -or $printer.PortName -ne $PortName) {
            throw "Printer '$PrinterName' exists but uses driver '$($printer.DriverName)' and port '$($printer.PortName)'. No changes made to the existing printer."
        }
        Write-Host 'Printer already installed with the expected driver and port.' -ForegroundColor Yellow
    }

    $printer = Get-Printer -Name $PrinterName -ErrorAction Stop
    if ($printer.DriverName -ne $DriverName -or $printer.PortName -ne $PortName) {
        throw 'Post-install verification failed: printer driver or port does not match.'
    }

    $success = $true
}
catch {
    Write-Host "INSTALLATION FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'No success message will be issued. Review the error above before retrying.' -ForegroundColor Yellow
}
finally {
    if (Test-Path -LiteralPath $TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($success) {
    Write-Host "INSTALLATION SUCCESSFUL: $PrinterName via $PrinterIP ($DriverName)" -ForegroundColor Green
    Write-Host 'Print a Windows test page to confirm network connectivity and printer operation.' -ForegroundColor Cyan
    exit 0
}
exit 1
