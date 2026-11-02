# --- CONFIGURATION VARIABLES ---
$ZipUrl = "https://github.com/Kachiiwox/printer-drivers/raw/main/hp4303fdw_driver.zip" 
$PrinterIP = "192.168.88.101" 
$PortName = "IP_$PrinterIP"
$PrinterName = "HP Color LaserJet Pro MFP 4303fdw"
$DriverName = "HP Color LaserJet Pro MFP 4301-4303 PCL-6 V4"

# --- DEPLOYMENT PROCESS ---
$TempDir = "C:\Windows\Temp\HP4303Driver"
$ZipFile = "$TempDir\driver.zip"

# 1. Create temporary staging directory
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# 2. Download the driver package silently
Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile

# 3. Extract the ZIP file
Expand-Archive -Path $ZipFile -DestinationPath $TempDir -Force

# 4. Install driver package into Windows Driver Store via PNPUtil
$InfFile = Get-ChildItem -Path $TempDir -Filter "*.inf" -Recurse | Select-Object -First 1

if ($InfFile) {
    pnputil.exe /add-driver $InfFile.FullName /install
} else {
    Write-Host "Error: Could not find driver .inf file." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# 5. Add driver to Windows Print Spooler
Add-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue

# 6. Create TCP/IP Port if missing
$portExists = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
if (-not $portExists) {
    Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
}

# 7. Map Printer if missing
$printerExists = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if (-not $printerExists) {
    Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName
}

# 8. Cleanup temporary files
Remove-Item -Path $TempDir -Recurse -Force

Write-Host "Printer installation complete!" -ForegroundColor Green
Start-Sleep -Seconds 5