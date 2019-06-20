Function Global:Get-PCISlot($X) { 

    switch ($X) {
        "0:2:2" { $busId = "00:02.0" }
        "1:0:0" { $busID = "01:00.0" }
        "2:0:0" { $busID = "02:00.0" }
        "3:0:0" { $busID = "03:00.0" }
        "4:0:0" { $busID = "04:00.0" }
        "5:0:0" { $busID = "05:00.0" }
        "6:0:0" { $busID = "06:00.0" }
        "7:0:0" { $busID = "07:00.0" }
        "8:0:0" { $busID = "08:00.0" }
        "9:0:0" { $busID = "09:00.0" }
        "10:0:0" { $busID = "0a:00.0" }
        "11:0:0" { $busID = "0b:00.0" }
        "12:0:0" { $busID = "0c:00.0" }
        "13:0:0" { $busID = "0d:00.0" }
        "14:0:0" { $busID = "0e:00.0" }
        "15:0:0" { $busID = "0f:00.0" }
        "16:0:0" { $busID = "0g:00.0" }
        "17:0:0" { $busID = "0h:00.0" }
        "18:0:0" { $busID = "0i:00.0" }
        "19:0:0" { $busID = "0j:00.0" }
        "20:0:0" { $busID = "0k:00.0" }
        "21:0:0" { $busID = "0l:00.0" }
        "22:0:0" { $busID = "0m:00.0" }
        "23:0:0" { $busID = "0n:00.0" }
        "24:0:0" { $busID = "0o:00.0" }
        "25:0:0" { $busID = "0p:00.0" }
        "26:0:0" { $busID = "0q:00.0" }
        "27:0:0" { $busID = "0r:00.0" }
        "28:0:0" { $busID = "0s:00.0" }
        "29:0:0" { $busID = "0t:00.0" }
        "30:0:0" { $busID = "0u:00.0" }
    }

    $busID
}


Function Global:Get-Bus {

    $GPUS = @()
    
    $OldCount = if (Test-Path ".\build\txt\gpu-count.txt") { $(Get-Content ".\build\txt\gpu-count.txt") }
    if ($OldCount) {
        Write-Log "Previously Detected GPU Count is:" -ForegroundColor Yellow
        $OldCount | Out-Host
        Start-Sleep -S .5
    }
   Invoke-Expression ".\build\apps\pci\lspci.exe" | Select-String "VGA compatible controller" | Tee-Object -FilePath ".\build\txt\gpu-count.txt" | Out-Null
   $NewCount = if (Test-Path ".\build\txt\gpu-count.txt") { $(Get-Content ".\build\txt\gpu-count.txt") }

    if ([string]$NewCount -ne [string]$OldCount) {
        Write-Log "GPU count is different - Gathering GPU information" -ForegroundColor Yellow

        ## Add key to bypass install question:
        Set-Location HKCU:
        if (-not (test-Path .\Software\techPowerUp)) {
            New-Item -Path .\Software -Name techPowerUp | Out-Null
            New-Item -path ".\Software\techPowerUp" -Name "GPU-Z" | Out-Null
            New-ItemProperty -Path ".\Software\techPowerUp\GPU-Z" -Name "Install_Dir" -Value "no" | Out-Null
        }
        Set-Location $(vars).dir

        Start-Process ".\build\apps\gpu-z.exe" -ArgumentList "-dump $($(vars).dir)\build\txt\data.xml" -Wait
        if (test-Path ".\build\txt\data.xml") {
            $Data = $([xml](Get-Content ".\build\txt\data.xml")).gpuz_dump.card
        }
        else {
            Write-Log "WARNING: Failed to gather GPU data" -ForegroundColor Yellow
        }
    }
    elseif (test-path ".\build\txt\data.xml") {
        $Data = $([xml](Get-Content ".\build\txt\data.xml")).gpuz_dump.card
    }
    else { write-Lost "WARNING: No GPU Data file found!" -ForegroundColor Yellow }

    if ("NVIDIA" -in $Data.vendor) {
        invoke-expression ".\build\apps\nvidia-smi.exe --query-gpu=gpu_bus_id,gpu_name,memory.total,power.min_limit,power.default_limit,power.max_limit,vbios_version --format=csv" | Tee-Object -Variable NVSMI | Out-Null
        $NVSMI = $NVSMI | ConvertFrom-Csv
        $NVSMI | % { $_."pci.bus_id" = $_."pci.bus_id".split("00000000:") | Select -Last 1 }
    }

    $Data | % {
        if ($_.vendorid -eq "1002") {
            $busid = $(Global:Get-PCISlot $_.location)
            $GPUS += [PSCustomObject]@{
                "busid"     = $busid
                "name"      = $_.cardname
                "brand"     = "amd"
                "subvendor" = $_.subvendor
                "mem"       = "$($_.memsize)MB"
                "vbios"     = $_.biosversion
                "mem_type"  = $_.memvendor
            }
        }
        elseif ($_.vendorid -eq "10DE") {
            $busid = $(Global:Get-PCISlot $_.location)
            $SMI = $NVSMI | Where "pci.bus_id" -eq $busid
            $GPUS += [PSCustomObject]@{
                busid     = $busid
                name      = $_.cardname
                brand     = "nvidia"
                subvendor = $_.subvendor
                mem       = $SMI."memory.total [MiB]"
                vbios     = $SMI.vbios_version
                plim_min  = $SMI."power.min_limit [W]"
                plim_def  = $SMI."power.default_limit [W]"
                plim_max  = $SMI."power.max_limit [W]"
            }
        }
        else {
            $busid = $(Global:Get-PCISlot $_.location)
            $GPUS += [PSCustomObject]@{
                busid = $busid
                name  = $_.cardname
                brand = "cpu"
            }
        }
    }

    $NewCount | Set-Content ".\build\txt\gpu-count.txt"
    $GPUS
}

function Global:Get-GPUCount {

    $Bus = $(vars).BusData | Sort-Object busid
    $DeviceList = @{ AMD = @{ }; NVIDIA = @{ }; CPU = @{ } }
    $OCList = @{ AMD = @{ }; Onboard = @{ }; NVIDIA = @{ }; }
    $GN = $false
    $GA = $false
    $NoType = $true

    $DeviceCounter = 0
    $OCCounter = 0
    $NvidiaCounter = 0
    $AmdCounter = 0 
    $OnboardCounter = 0

    $Bus | Foreach {
        $Sel = $_
        if ($Sel.Brand -eq "nvidia") {
            $GN = $true
            $DeviceList.NVIDIA.Add("$NvidiaCounter", "$DeviceCounter")
            $OCList.NVIDIA.Add("$NvidiaCounter", "$DeviceCounter")
            $NvidiaCounter++
            $DeviceCounter++
            $OCCounter++
        }
        elseif ($Sel.Brand -eq "amd") {
            $GA = $true
            $DeviceList.AMD.Add("$AmdCounter", "$DeviceCounter")
            $OCList.AMD.Add("$AmdCounter", "$OCCounter")
            $AmdCounter++
            $DeviceCounter++
            $OCCounter++
        }
        else {
            $OCList.Onboard.Add("$OnboardCounter", "$OCCounter")
            $OnboardCounter++
            $OCCounter++
        }
    }

    if ($GA -or $GN) {
        $TypeArray = @("NVIDIA1", "NVIDIA2", "NVIDIA3", "AMD1")
        $TypeArray | ForEach-Object { if ($_ -in $(arg).Type) { $NoType = $false } }
        if ($NoType -eq $true) {
            Global:Write-Log "Searching GPU Types" -ForegroundColor Yellow
            if ($GA) { 
                Global:Write-Log "AMD Detected: Adding AMD" -ForegroundColor Magenta
                $(arg).Type += "AMD1" 
            }
            if ($GN -and $GA) {
                Global:Write-Log "NVIDIA Also Detected" -ForegroundColor Magenta
                $(arg).Type += "NVIDIA2" 
            }
            elseif ($GN) { 
                Global:Write-Log "NVIDIA Detected: Adding NVIDIA" -ForegroundColor Magenta
                $(arg).Type += "NVIDIA1" 
            }
        }
    }

    
    if ($(arg).Type -like "*CPU*") { for ($i = 0; $i -lt $(arg).CPUThreads; $i++) { $DeviceList.CPU.Add("$($i)", $i) } }
    $DeviceList | ConvertTo-Json | Set-Content ".\build\txt\devicelist.txt"
    $OCList | ConvertTo-Json | Set-Content ".\build\txt\oclist.txt"
    $GPUCount = 0
    $GPUCount += $DeviceList.Nvidia.Count
    $GPUCount += $DeviceList.AMD.Count
    $GPUCount
}
function Global:Start-WindowsConfig {

    ## Add Swarm to Startup
    if ($(arg).Startup) {
        $CurrentUser = $env:UserName
        $Startup_Path = "C:\Users\$CurrentUser\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
        $Bat_Startup = Join-Path $Startup_Path "SWARM.bat"
        switch ($(arg).Startup) {
            "Yes" {
                Global:Write-Log "Attempting to add current SWARM.bat to startup" -ForegroundColor Magenta
                Global:Write-Log "If you do not wish SWARM to start on startup, use -Startup No argument"
                Global:Write-Log "Startup FilePath: $Startup_Path"
                $bat = "CMD /r pwsh -ExecutionPolicy Bypass -command `"Set-Location $($(vars).dir); Start-Process `"SWARM.bat`"`""
                $Bat_Startup = Join-Path $Startup_Path "SWARM.bat"
                $bat | Set-Content $Bat_Startup
            }
            "No" {
                Global:Write-Log "Startup No Was Specified. Removing From Startup" -ForegroundColor Magenta
                if (Test-Path $Bat_Startup) { Remove-Item $Bat_Startup -Force }
            }    
        }
    }
    
    ##Create a CMD.exe shortcut for SWARM on desktop
    $CurrentUser = $env:UserName
    $Desk_Term = "C:\Users\$CurrentUser\desktop\SWARM-TERMINAL.bat"
    if (-Not (Test-Path $Desk_Term)) {
        Global:Write-Log "
            
    Making a terminal on desktop. This can be used for commands.
    
    " -ForegroundColor Yellow
        $Term_Script = @()
        $Term_Script += "`@`Echo Off"
        $Term_Script += "ECHO You can run terminal commands here."
        $Term_Script += "ECHO Commands such as:"
        $Term_Script += "echo.       "
        $Term_Script += "echo.       "
        $Term_Script += "ECHO       get stats"
        $Term_Script += "ECHO       get active"
        $Term_Script += "ECHO       get help"
        $Term_Script += "ECHO       benchmark timeout"
        $Term_Script += "ECHO       version query"
        $Term_Script += "echo.       "
        $Term_Script += "echo.       "
        $Term_Script += "echo.       "
        $Term_Script += "ECHO For full command list, see: https://github.com/MaynardMiner/SWARM/wiki"
        $Term_Script += "echo.       "
        $Term_Script += "echo.       "
        $Term_Script += "echo.       "
        $Term_Script += "ECHO Starting CMD.exe"
        $Term_Script += "echo.       "
        $Term_Script += "echo.       "
        $Term_Script += "echo.       "
        $Term_Script += "cmd.exe"
        $Term_Script | Set-Content $Desk_Term
    }
    
    ## Windows Bug- Set Cudas to match PCI Bus Order
    if ($(arg).Type -like "*NVIDIA*") { [Environment]::SetEnvironmentVariable("CUDA_DEVICE_ORDER", "PCI_BUS_ID", "User") }
    
    ##Set Cuda For Commands
    if ($(arg).Type -like "*NVIDIA*") { $(arg).Cuda = "10"; $(arg).Cuda | Set-Content ".\build\txt\cuda.txt" }
    
    ##Detect if drivers are installed, not generic- Close if not. Print message on screen
    if ($(arg).Type -like "*NVIDIA*" -and -not (Test-Path "C:\Program Files\NVIDIA Corporation\NVSMI\nvml.dll")) {
        Global:Write-Log "nvml.dll is missing" -ForegroundColor Red
        Start-Sleep -S 3
        Global:Write-Log "To Fix:" -ForegroundColor Blue
        Global:Write-Log "Update Windows, Purge Old NVIDIA Drivers, And Install Latest Drivers" -ForegroundColor Blue
        Start-Sleep -S 3
        Global:Write-Log "Closing Miner"
        Start-Sleep -S 1
        exit
    }
    
    ## Fetch Ram Size, Write It To File (For Commands)
    $TotalMemory = [math]::Round((Get-CimInstance -ClassName CIM_ComputerSystem).TotalPhysicalMemory / 1mb, 2) 
    $TotalMemory | Set-Content ".\build\txt\ram.txt"
    
    ## GPU Bus Hash Table
    $(vars).BusData = Global:Get-Bus
    
    ## Get Total GPU HashTable
    $(vars).GPU_Count = Global:Get-GPUCount
    
    ## Websites
    if ($(vars).WebSites) {
        Global:Add-Module "$($(vars).web)\methods.psm1"
        $rigdata = Global:Get-RigData

        $(vars).WebSites | ForEach-Object {
            switch ($_) {
                "HiveOS" {
                    Global:Get-WebModules "HiveOS"
                    $response = $rigdata | Global:Invoke-WebCommand -Site "HiveOS" -Action "Hello"
                    Global:Start-WebStartup $response "HiveOS"
                }
                "SWARM" {
                    Global:Get-WebModules "SWARM"
                    $response = $rigdata | Global:Invoke-WebCommand -Site "SWARM" -Action "Hello"
                    Global:Start-WebStartup $response "SWARM"
                }
            }
        }
        Remove-Module -Name "methods"
    }

    ## Aaaaannnnd...Que that sexy logo. Go Time.

    Global:Get-SexyWinLogo

}