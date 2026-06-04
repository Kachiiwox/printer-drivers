# --- CONFIGURATION VARIABLES ---
$ZipUrl = "https://github.com/Kachiiwox/printer-drivers/raw/main/hpdriversunversal479fdw.zip" 
$PrinterIP = "192.168.88.123" 
$PortName = "IP_$PrinterIP"
$PrinterName = "Finance Pool Printer"
$DriverName = "HP Color LaserJet Pro M478f-9f PCL 6 (V3)"
$InfFileName = "hpclC62A_x64.inf"

# --- DEPLOYMENT PROCESS ---
$TempDir = "C:\Windows\Temp\HPDriver"
$ZipFile = "$TempDir\driver.zip"

# 1. Create a temporary staging directory
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# 2. Download the drivers silently from GitHub
Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile

# 3. Extract the ZIP file
Expand-Archive -Path $ZipFile -DestinationPath $TempDir -Force

# 4. Smart-Install the driver (Automatically finds the .inf file)
$InfFile = Get-ChildItem -Path $TempDir -Filter $InfFileName -Recurse | Select-Object -First 1

if ($InfFile) {
    pnputil.exe /add-driver $InfFile.FullName /install
} else {
    Write-Host "Error: Could not find the $InfFileName driver file." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# 5. Add the driver to the Windows Print Spooler
Add-PrinterDriver -Name $DriverName

# 6. Create the TCP/IP Printer Port (Only if it doesn't already exist)
$portExists = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
if (-not $portExists) {
    Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
}

# 7. Map the Printer for the Staff (Only if it doesn't already exist)
$printerExists = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if (-not $printerExists) {
    Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName
}

# 8. Clean up the temporary files
Remove-Item -Path $TempDir -Recurse -Force

Write-Host "Printer installation complete!" -ForegroundColor Green

# 9. Keep the window open for 5 seconds so the user can read the success message
Start-Sleep -Seconds 5