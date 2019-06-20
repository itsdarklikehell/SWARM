<#
SWARM is open-source software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
SWARM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
#>

Param (
    [Parameter(mandatory = $false)]
    [string]$WorkingDir
)

#$WorkingDir = "C:\Users\Mayna\Documents\GitHub\SWARM"
#$WorkingDir = "/root/hive/miners/custom/SWARM"
Set-Location $WorkingDir
$UtcTime = Get-Date -Date "1970-01-01 00:00:00Z"
$UTCTime = $UtcTime.ToUniversalTime()
$StartTime = [Math]::Round(((Get-Date) - $UtcTime).TotalSeconds)
$Global:config = [hashtable]::Synchronized(@{ })
$global:config.Add("vars", @{ })
. .\build\powershell\global\modules.ps1
$(vars).Add("dir", $WorkingDir)

try { if ((Get-MpPreference).ExclusionPath -notcontains (Convert-Path .)) { Start-Process "powershell" -Verb runAs -ArgumentList "Add-MpPreference -ExclusionPath `'$WorkingDir`'" -WindowStyle Minimized } }catch { }
try { $Net = Get-NetFireWallRule } catch { }
if ($Net) {
    try { if ( -not ( $Net | Where { $_.DisplayName -like "*background.ps1*" } ) ) { New-NetFirewallRule -DisplayName 'background.ps1' -Direction Inbound -Program "$workingdir\build\powershell\scripts\background.ps1" -Action Allow | Out-Null } } catch { }
}
$Net = $null

if ($IsWindows) { Start-Process "powershell" -ArgumentList "Set-Location `'$($(vars).dir)`'; .\build\powershell\scripts\icon.ps1 `'$($(vars).dir)\build\apps\comb.ico`'" -NoNewWindow }

$(vars).Add("global", "$($(vars).dir)\build\powershell\global")
$(vars).Add("background", "$($(vars).dir)\build\powershell\background")
$(vars).Add("miners", "$($(vars).dir)\build\api\miners")
$(vars).Add("tcp", "$($(vars).dir)\build\api\tcp")
$(vars).Add("html", "$($(vars).dir)\build\api\html")
$(vars).Add("web", "$($(vars).dir)\build\api\web")

if(Test-Path ".\build\txt\data.xml"){
    $(vars).Add("onboard",([xml](Get-Content ".\build\txt\data.xml")))
    $(vars).onboard = $(vars).onboard.gpuz_dump.card | Where vendor -ne "AMD/ATI" | Where vendor -ne "NVIDIA"
}

$p = [Environment]::GetEnvironmentVariable("PSModulePath")
if ($P -notlike "*$($(vars).dir)\build\powershell*") {
    $P += ";$($(vars).global)";
    $P += ";$($(vars).background)";
    $P += ";$($(vars).miners)";
    $P += ";$($(vars).tcp)";
    $P += ";$($(vars).html)";
    $P += ";$($(vars).web)";
    [Environment]::SetEnvironmentVariable("PSModulePath", $p)
    Write-Host "Modules Are Loaded" -ForegroundColor Green
}

$(vars).Add("Modules", @())
Import-Module "$($(vars).global)\include.psm1" -Scope Global
Global:Add-Module "$($(vars).background)\startup.psm1"

## Get Parameters
Global:Get-Params
[cultureinfo]::CurrentCulture = 'en-US'
$AllProtocols = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12' 
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
Global:Set-Window

$(vars).Add("NetModules", @())
$(vars).Add("WebSites", @())
if ($Config.Params.Hive_Hash -ne "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" -and -not (Test-Path "/hive/miners") ) { $(vars).NetModules += ".\build\api\hiveos"; $(vars).WebSites += "HiveOS" }
##if ($Config.Params.Swarm_Hash -ne "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") { $(vars).NetModules += ".\build\api\SWARM"; $(vars).WebSites += "SWARM" }

if( (Test-Path "/hive/miners") -or $(arg).Hive_Hash -ne "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" ) { $(arg).HiveOS = "Yes" }
Write-Host "Platform is $($(arg).Platform)"; 
Write-Host "HiveOS ID is $($global:Config.hive_params.Id)"; 
Write-Host "HiveOS = $($(arg).HiveOS)"

Global:Start-Servers

##Starting Variables.
$global:GPUHashrates = $null       
$global:GPUFans = $null
$global:GPUTemps = $null
$global:GPUPower = $null
$global:GPUFanTable = $null
$global:GPUTempTable = $null
$global:GPUPowerTable = $null                
$global:GPUKHS = $null
$global:CPUHashrates = $null
$global:CPUHashTable = $null
$global:CPUKHS = $null
$global:ASICHashrates = $null
$global:ASICKHS = $null
$global:ramfree = $null
$global:diskSpace = $null
$global:ramtotal = $null
$Global:cpu = $null
$Global:LoadAverages = $null
$Global:StartTime = Get-Date
$CheckForSWARM = ".\build\pid\miner_pid.txt"
if (Test-Path $CheckForSWARM) { 
    $global:GETSWARMID = Get-Content $CheckForSWARM; 
    $Global:GETSWARM = Get-Process -ID $global:GETSWARMID -ErrorAction SilentlyContinue 
}
$(vars).ADD("GCount",(Get-Content ".\build\txt\devicelist.txt" | ConvertFrom-Json))
$(vars).ADD("BackgroundTimer",(New-Object -TypeName System.Diagnostics.Stopwatch))

Remove-Module -Name "startup"

if($IsWindows){ $(vars).Add("Cores",$(Get-CimInstance -ClassName "Win32_Processor" | Select-Object -Property "NumberOfCores").NumberOfCores)}

While ($True) {

    ## Timer For When To Restart Loop
    $(vars).BackgroundTimer.Restart()

    if ($(arg).Platform -eq "linux" -and -not $(vars).WebSites) {
        if ($global:GETSWARM.HasExited -eq $true) {
            Write-Host "Closing down SWARM" -ForegroundColor Yellow
            Global:start-killscript
        }
    }

    $global:CPUOnly = $True ; $global:DoCPU = $false; $global:DoAMD = $false; 
    $global:DoNVIDIA = $false; $global:DoASIC = $false; $global:AllKHS = 0; 
    $global:AllACC = 0; $global:ALLREJ = 0;
    $global:HIVE_ALGO = @{ }; $Group1 = $null; $Default_Group = $null; 
    $Hive = $null; $global:UPTIME = 0; $global:Web_Stratum = @{ }; $global:Workers = @{ }

    Global:Add-Module "$($(vars).background)\run.psm1"
    Global:Add-Module "$($(vars).background)\initial.psm1"
    Global:Add-Module "$($(vars).global)\gpu.psm1"
    Global:Add-Module "$($(vars).global)\stats.psm1"
    Global:Add-Module "$($(vars).global)\hashrates.psm1"
    
    Global:Invoke-MinerCheck
    Global:New-StatTables
    Global:Get-Metrics
    Remove-Module "initial"
    if ($global:DoNVIDIA -eq $true) { $NVIDIAStats = Global:Set-NvidiaStats }
    if ($global:DoAMD -eq $true) { $AMDStats = Global:Set-AMDStats }

    ## Start API Calls For Each Miner
    if ($global:CurrentMiners -and $Global:GETSWARM.HasExited -eq $false) {

        $global:MinerTable = @{ }

        $global:CurrentMiners | ForEach-Object {

            ## Static Miner Information
            $global:MinerAlgo = "$($_.Algo)"; $global:MinerName = "$($_.MinerName)"; $global:Name = "$($_.Name)";
            $global:Port = $($_.Port); $global:MinerType = "$($_.Type)"; $global:MinerAPI = "$($_.API)";
            $global:Server = "$($_.Server)"; $HashPath = ".\logs\$($_.Type).log"; $global:TypeS = "none"
            $global:Devices = 0; $MinerDevices = $_.Devices; $MinerStratum = $_.Stratum; $Worker = $_.Worker

            ##Algorithm Parsing For Stats
            $HiveAlgo = $global:MinerAlgo -replace "`_", " "
            $HiveAlgo = $HiveAlgo -replace "veil", "x16rt"
            $NewName = $global:MinerAlgo -replace "`/", "`-"
            $NewName = $global:MinerAlgo -replace "`_", "`-"

            ## Determine API Type
            if ($global:MinerType -like "*NVIDIA*") { $global:TypeS = "NVIDIA" }
            elseif ($global:MinerType -like "*AMD*") { $global:TypeS = "AMD" }
            elseif ($global:MinerType -like "*CPU*") { $global:TypeS = "CPU" }
            elseif ($global:MinerType -like "*ASIC*") { $global:TypeS = "ASIC" }

            ##Build Algo Table
            switch ($global:MinerType) {
                "NVIDIA1" { 
                    $global:HIVE_ALGO.Add("Main", $HiveAlgo); 
                    $global:Web_Stratum.Add("Main", $MinerStratum); 
                    $global:Workers.Add("Main",$Worker)
                }
                "AMD1" { 
                    $global:HIVE_ALGO.Add("Main", $HiveAlgo); 
                    $global:Web_Stratum.Add("Main", $MinerStratum);
                    $global:Workers.Add("Main",$Worker)
                }
                default { 
                    $global:HIVE_ALGO.Add($global:MinerType, $HiveAlgo); 
                    $global:Web_Stratum.Add($global:MinerType, $MinerStratum); 
                }
            }         
            
            ## Determine Devices
            Switch ($global:TypeS) {
                "NVIDIA" {
                    if ($MinerDevices -eq "none") { $global:Devices = Global:Get-DeviceString -TypeCount $(vars).GCount.NVIDIA.PSObject.Properties.Value.Count }
                    else { $global:Devices = Global:Get-DeviceString -TypeDevices $MinerDevices }
                }
                "AMD" {
                    if ($MinerDevices -eq "none") { $global:Devices = Global:Get-DeviceString -TypeCount $(vars).GCount.AMD.PSObject.Properties.Value.Count }
                    else { $global:Devices = Global:Get-DeviceString -TypeDevices $MinerDevices }
                }
                "ASIC" { $global:Devices = $null }
                "CPU" { $global:Devices = Global:Get-DeviceString -TypeCount $(vars).GCount.CPU.PSObject.Properties.Value.Count }
            }

            ## Get Power Stats
            if ($global:TypeS -eq "NVIDIA") { $StatPower = $NVIDIAStats.Watts }
            if ($global:TypeS -eq "AMD") { $StatPower = $AMDStats.Watts }
            if ($global:TypeS -eq "NVIDIA" -or $global:TypeS -eq "AMD") {
                if ($StatPower -ne "" -or $StatPower -ne $null) {
                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                        $global:GPUPower.$(Global:Get-GPUs) = Global:Set-Array $StatPower $global:Devices[$global:i]
                    }
                }
            }


            ## Now Fans & Temps
            Switch ($global:TypeS) {
                "NVIDIA" {
                    switch ($(arg).Platform) {
                        "Windows" {
                            for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                try { $global:GPUFans.$(Global:Get-GPUs) = Global:Set-Array $NVIDIAStats.Fans $global:Devices[$global:i] }
                                catch { Write-Host "Failed To Parse GPU Fan Array" -foregroundcolor red; break }
                            }
                            for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                try { $global:GPUTemps.$(Global:Get-GPUs) = Global:Set-Array $NVIDIAStats.Temps $global:Devices[$global:i] }
                                catch { Write-Host "Failed To Parse GPU Temp Array" -foregroundcolor red; break }
                            }
                        }
                        "linux" {
                            switch ($(arg).HiveOS) {
                                "Yes" {
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUFans.$(Global:Get-GPUs) = Global:Set-Array $NVIDIAStats.Fans (Global:Get-GPUs) }
                                        catch { Write-Host "Failed To Parse GPU Fan Array" -foregroundcolor red; break }
                                    }
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUTemps.$(Global:Get-GPUs) = Global:Set-Array $NVIDIAStats.Temps (Global:Get-GPUs) }
                                        catch { Write-Host "Failed To Parse GPU Temp Array" -foregroundcolor red; break }
                                    }            
                                }
                                "No" {
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUFans.$(Global:Get-GPUs) = Global:Set-Array $NVIDIAStats.Fans $global:Devices[$global:i] }
                                        catch { Write-Host "Failed To Parse GPU Fan Array" -foregroundcolor red; break }
                                    }
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUTemps.$(Global:Get-GPUs) = Global:Set-Array $NVIDIAStats.Temps $global:Devices[$global:i] }
                                        catch { Write-Host "Failed To Parse GPU Temp Array" -foregroundcolor red; break }
                                    }                    
                                }
                            }
                        }
                    }
                }
                "AMD" {
                    Switch ($(arg).Platform) {
                        "windows" {
                            for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                try { $global:GPUFans.$(Global:Get-GPUs) = Global:Set-Array $AMDStats.Fans $global:Devices[$global:i] }
                                catch { Write-Host "Failed To Parse GPU Fan Array" -foregroundcolor red; break }
                            }
                            for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                try { $global:GPUTemps.$(Global:Get-GPUs) = Global:Set-Array $AMDStats.Temps $global:Devices[$global:i] }
                                catch { Write-Host "Failed To Parse GPU Fan Array" -foregroundcolor red; break }
                            }
                        }
                        "linux" {
                            switch ($(arg).HiveOS) {
                                "Yes" {
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUFans.$(Global:Get-GPUs) = Global:Set-Array $AMDStats.Fans (Global:Get-GPUs) }
                                        catch { Write-Host "Failed To Parse GPU Fan Array" -foregroundcolor red; break }
                                    }
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUTemps.$(Global:Get-GPUs) = Global:Set-Array $AMDStats.Temps (Global:Get-GPUs) }
                                        catch { Write-Host "Failed To Parse GPU Temp Array" -foregroundcolor red; break }
                                    }
                                }
                                "No" {
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUFans.$(Global:Get-GPUs) = Global:Set-Array $AMDStats.Fans $global:Devices[$global:i] }
                                        catch { Write-Host "Failed To Parse GPU Fan Array" -foregroundcolor red; break }
                                    }
                                    for ($global:i = 0; $global:i -lt $global:Devices.Count; $global:i++) {
                                        try { $global:GPUTemps.$(Global:Get-GPUs) = Global:Set-Array $AMDStats.Temps $global:Devices[$global:i] }
                                        catch { Write-Host "Failed To Parse GPU Temp Array" -foregroundcolor red; break }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ## Set Global Miner-Specific Variables.
            $global:RAW = 0; $global:MinerREJ = 0;
            $global:MinerACC = 0;

            ##Write Miner Information
            Global:Write-MinerData1

            ## Start Calling Miner API
            switch ($global:MinerAPI) {
                'energiminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\energiminer.psm1"; 
                        Global:Get-StatsEnergiminer;
                        Remove-Module -name "energiminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'claymore' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\ethminer.psm1"; 
                        Global:Get-StatsEthminer;
                        Remove-Module -name "ethminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'excavator' {
                    try { 
                        Global:Add-Module "$($(vars).miners)\excavator.psm1"; 
                        Global:Get-StatsExcavator;
                        Remove-Module -name "excavator"
                    }
                    catch { Global:Get-OhNo } 
                }
                'miniz' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\miniz.psm1"; 
                        Global:Get-Statsminiz;
                        Remove-Module -name "miniz"
                    }
                    catch { Global:Get-OhNo } 
                }
                'gminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\gminer.psm1"; 
                        Global:Get-StatsGminer;
                        Remove-Module -name "gminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'grin-miner' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\grinminer.psm1"; 
                        Global:Get-StatsGrinMiner;
                        Remove-Module -name "grinminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'ewbf' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\ewbf.psm1"; 
                        Global:Get-Statsewbf;
                        Remove-Module -name "ewbf"
                    }
                    catch { Global:Get-OhNo } 
                }
                'ccminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\ccminer.psm1"; 
                        Global:Get-StatsCcminer;
                        Remove-Module -name "ccminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'bminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\bminer.psm1"; 
                        Global:Get-StatsBminer;
                        Remove-Module -name "bminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'trex' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\trex.psm1"; 
                        Global:Get-StatsTrex;
                        Remove-Module -name "trex"
                    }
                    catch { Global:Get-OhNo } 
                }
                'dstm' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\dstm.psm1"; 
                        Global:Get-Statsdstm;
                        Remove-Module -name "dstm"
                    }
                    catch { Global:Get-OhNo } 
                }
                'lolminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\lolminer.psm1"; 
                        Global:Get-Statslolminer;
                        Remove-Module -name "lolminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'sgminer-gm' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\sgminer.psm1"; 
                        Global:Get-StatsSgminer;
                        Remove-Module -name "sgminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'cpuminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\cpuminer.psm1"; 
                        Global:Get-Statscpuminer;
                        Remove-Module -name "cpuminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'xmrstak' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\xmrstak.psm1"; 
                        Global:Get-Statsxmrstak;
                        Remove-Module -name "xmrstak"
                    }
                    catch { Global:Get-OhNo } 
                }
                'xmrig-opt' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\xmrigopt.psm1"; 
                        Global:Get-Statsxmrigopt;
                        Remove-Module -name "xmrigopt"
                    }
                    catch { Global:Get-OhNo } 
                }
                'wildrig' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\wildrig.psm1"; 
                        Global:Get-Statswildrig
                        Remove-Module -name "wildrig"
                    }
                    catch { Global:Get-OhNo } 
                }
                'cgminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\cgminer.psm1"; 
                        Global:Get-Statscgminer
                        Remove-Module -name "cgminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'nebutech' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\nbminer.psm1"; 
                        Global:Get-StatsNebutech
                        Remove-Module -name "nbminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'srbminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\srbminer.psm1"; 
                        Global:Get-Statssrbminer
                        Remove-Module -name "srbminer"
                    }
                    catch { Global:Get-OhNo } 
                }
                'multiminer' { 
                    try { 
                        Global:Add-Module "$($(vars).miners)\multiminer.psm1"; 
                        Global:Get-Statsmultiminer
                        Remove-Module -name "multiminer"
                    }
                    catch { Global:Get-OhNo } 
                }
            }

            ##Check To See if High Rejections
            if ($BackgroundTimer.Elapsed.TotalSeconds -gt 60) {
                $Shares = [Double]$global:MinerACC + [double]$global:MinerREJ
                $RJPercent = $global:MinerREJ / $Shares * 100
                if ($RJPercent -gt $(arg).Rejections -and $Shares -gt 0) {
                    Write-Host "Warning: Miner is reaching Rejection Limit- $($RJPercent.ToString("N2")) Percent Out of $Shares Shares" -foreground yellow
                    if (-not (Test-Path ".\timeout")) { New-Item "timeout" -ItemType Directory | Out-Null }
                    if (-not (Test-Path ".\timeout\warnings")) { New-Item ".\timeout\warnings" -ItemType Directory | Out-Null }
                    "Bad Shares" | Out-File ".\timeout\warnings\$($_.Name)_$($NewName)_rejection.txt"
                }
                else { if (Test-Path ".\timeout\warnings\$($_.Name)_$($NewName)_rejection.txt") { Remove-Item ".\timeout\warnings\$($_.Name)_$($NewName)_rejection.txt" -Force } }
            }
        }
    }


    ##Select Algo For Online Stats
    if ($global:HIVE_ALGO.Main) { $Global:StatAlgo = $global:HIVE_ALGO.Main }
    else { $FirstMiner = $global:HIVE_ALGO.keys | Select-Object -First 1; if ($FirstMiner) { $Global:StatAlgo = $global:HIVE_ALGO.$FirstMiner } }

    if ($global:Web_Stratum.Main) { $Global:StatStratum = $global:Web_Stratum.Main }
    else { $FirstStrat = $global:Web_Stratum.keys | Select-Object -First 1; if ($FirstStrat) { $Global:StatStratum = $global:HIVE_ALGO.$FirstStrat } }

    if ($global:Workers.Main) { $Global:StatWorker = $global:Workers.Main }
    else { $FirstWorker = $global:Workers.keys | Select-Object -First 1; if ($FirstWorker) { $Global:StatWorker = $global:Workers.$FirstWorker } }

    ##Now To Format All Stats For Online Table And Screen
    if ($global:DoNVIDIA) {
        for ($global:i = 0; $global:i -lt $(vars).GCount.NVIDIA.PSObject.Properties.Value.Count; $global:i++) {
            $global:GPUHashTable += 0; $global:GPUFanTable += 0; $global:GPUTempTable += 0; $global:GPUPowerTable += 0;
        }
    }
    if ($global:DoAMD) {
        for ($global:i = 0; $global:i -lt $(vars).GCount.AMD.PSObject.Properties.Value.Count; $global:i++) {
            $global:GPUHashTable += 0; $global:GPUFanTable += 0; $global:GPUTempTable += 0; $global:GPUPowerTable += 0;
        }
    }
    if ($global:DoCPU) {
        for ($global:i = 0; $global:i -lt $(vars).GCount.CPU.PSObject.Properties.Value.Count; $global:i++) {
            $global:CPUHashTable += 0;
        }
    }
    if ($global:DoASIC) {
        $global:ASICHashTable += 0;
    }

    if ($global:DoNVIDIA) {
        for ($global:i = 0; $global:i -lt $(vars).GCount.NVIDIA.PSObject.Properties.Value.Count; $global:i++) {
            $global:GPUHashTable[$($(vars).GCount.NVIDIA.$global:i)] = "{0:f4}" -f $($global:GPUHashrates.$($(vars).GCount.NVIDIA.$global:i))
            $global:GPUFanTable[$($(vars).GCount.NVIDIA.$global:i)] = "$($global:GPUFans.$($(vars).GCount.NVIDIA.$global:i))"
            $global:GPUTempTable[$($(vars).GCount.NVIDIA.$global:i)] = "$($global:GPUTemps.$($(vars).GCount.NVIDIA.$global:i))"
            $global:GPUPowerTable[$($(vars).GCount.NVIDIA.$global:i)] = "$($global:GPUPower.$($(vars).GCount.NVIDIA.$global:i))"
        }
    }
    if ($global:DoAMD) {
        for ($global:i = 0; $global:i -lt $(vars).GCount.AMD.PSObject.Properties.Value.Count; $global:i++) {
            $global:GPUHashTable[$($(vars).GCount.AMD.$global:i)] = "{0:f4}" -f $($global:GPUHashrates.$($(vars).GCount.AMD.$global:i))
            $global:GPUFanTable[$($(vars).GCount.AMD.$global:i)] = "$($global:GPUFans.$($(vars).GCount.AMD.$global:i))"
            $global:GPUTempTable[$($(vars).GCount.AMD.$global:i)] = "$($global:GPUTemps.$($(vars).GCount.AMD.$global:i))"
            $global:GPUPowerTable[$($(vars).GCount.AMD.$global:i)] = "$($global:GPUPower.$($(vars).GCount.AMD.$global:i))"
        }
    }

    ##Select Only For Each Device Group
    $DeviceTable = @()
    if ([string]$(arg).GPUDevices1) { $DeviceTable += $(arg).GPUDevices1 }
    if ([string]$(arg).GPUDevices2) { $DeviceTable += $(arg).GPUDevices2 }
    if ([string]$(arg).GPUDevices3) { $DeviceTable += $(arg).GPUDevices3 }

    if ($DeviceTable) {
        $DeviceTable = $DeviceTable | Sort-Object
        $TempGPU = @()
        $TempFan = @()
        $TempTemp = @()
        $TempPower = @()
        for ($global:i = 0; $global:i -lt $DeviceTable.Count; $global:i++) {
            $G = $DeviceTable[$i]
            $TempGPU += $global:GPUHashTable[$G]
            $TempFan += $global:GPUFanTable[$G]
            $TempTemp += $global:GPUTempTable[$G]
            $TempPower += $global:GPUPowerTable[$G]
        }
        $global:GPUHashTable = $TempGPU
        $global:GPUFanTable = $TempFan
        $global:GPUTempTable = $TempTemp
        $global:GPUPowerTable = $TempPower
        Remove-Variable TempGPU
        Remove-Variable TempFan
        Remove-Variable TempTemp
        Remove-Variable TempPower
    }

    Remove-Variable DeviceTable

    if ($global:DoCPU) {
        for ($global:i = 0; $global:i -lt $(vars).GCount.CPU.PSObject.Properties.Value.Count; $global:i++) {
            $global:CPUHashTable[$($(vars).GCount.CPU.$global:i)] = "{0:f4}" -f $($global:CPUHashrates.$($(vars).GCount.CPU.$global:i))
        }
    }

    if ($global:DoASIC) { $global:ASICHashTable[0] = "{0:f4}" -f $($global:ASICHashrates."0") }

    if ($global:DoAMD -or $global:DoNVIDIA) { $global:GPUKHS = [Math]::Round($global:GPUKHS, 4) }
    if ($global:DoCPU) { $global:CPUKHS = [Math]::Round($global:CPUKHS, 4) }
    if ($global:DoASIC) { $global:ASICKHS = [Math]::Round($global:ASICKHS, 4) }
    $global:UPTIME = [math]::Round(((Get-Date) - $Global:StartTime).TotalSeconds)

    ##Modify Stats to show something For Online
    if($global:DoNVIDIA -or $global:AMD){
        for($global:i=0; $global:i -lt $global:GPUHashTable.Count; $global:i++) { $global:GPUHashTable[$global:i] = $global:GPUHashTable[$global:i] -replace "0.0000","0" }
        if($global:GPUKHS -eq 0){$global:GPUKHS = "0"}
    }

    $Global:config.summary = @{
        summary = $global:MinerTable;
    }
    $global:Config.stats = @{
        gpus       = $global:GPUHashTable;
        cpus       = $global:CPUHashTable;
        asics      = $global:ASICHashTable;
        cpu_total  = $global:CPUKHS;
        asic_total = $global:ASICKHS;
        gpu_total  = $global:GPUKHS;
        algo       = $Global:StatAlgo;
        uptime     = $global:UPTIME;
        hsu        = "khs";
        fans       = $global:GPUFanTable;
        temps      = $global:GPUTempTable;
        power      = $global:GPUPowerTable;
        accepted   = $global:AllACC;
        rejected   = $global:AllREJ;
        stratum    = $Global:StatStratum
        start_time = $StartTime
        workername = $Global:StatWorker
    }
    $global:Config.params = $(arg)

    if ($global:GetMiners -and $global:GETSWARM.HasExited -eq $false) {
        Write-Host " "
        if ($global:DoAMD -or $global:DoNVIDIA) { Write-Host "GPU_Hashrates: $global:GPUHashTable" -ForegroundColor Green }
        if ($global:DoCPU) { Write-Host "CPU_Hashrates: $global:CPUHashTable" -ForegroundColor Green }
        if ($global:DoASIC) { Write-Host "ASIC_Hashrates: $global:ASICHashTable" -ForegroundColor Green }
        if ($global:DoAMD -or $global:DoNVIDIA) { Write-Host "GPU_Fans: $global:GPUFanTable" -ForegroundColor Yellow }
        if ($global:DoAMD -or $global:DoNVIDIA) { Write-Host "GPU_Temps: $global:GPUTempTable" -ForegroundColor Cyan }
        if ($global:DoAMD -or $global:DoNVIDIA) { Write-Host "GPU_Power: $global:GPUPowerTable"  -ForegroundColor Magenta }
        if ($global:DoAMD -or $global:DoNVIDIA) { Write-Host "GPU_TOTAL_KHS: $global:GPUKHS" -ForegroundColor Yellow }
        if ($global:DoCPU) { Write-Host "CPU_TOTAL_KHS: $global:CPUKHS" -ForegroundColor Yellow }
        if ($global:DoASIC) { Write-Host "ASIC_TOTAL_KHS: $global:ASICKHS" -ForegroundColor Yellow }
        Write-Host "ACC: $global:ALLACC" -ForegroundColor DarkGreen -NoNewline; Write-Host " `|" -NoNewline
        Write-Host " REJ: $global:ALLREJ" -ForegroundColor DarkRed -NoNewline; Write-Host " `|" -NoNewline
        Write-Host " ALGO: $Global:StatAlgo" -ForegroundColor White -NoNewline; Write-Host " `|" -NoNewline
        Write-Host " UPTIME: $global:UPTIME" -ForegroundColor Yellow
        Write-Host "STRATUM: $global:StatStratum" -ForegroundColor Cyan
        Write-Host "START_TIME: $StartTime" -ForegroundColor Magenta -NoNewline; Write-Host " `|" -NoNewline
        Write-Host " WORKER: $global:StatWorker
" -ForegroundColor Yellow
    }

    Remove-Module -Name "gpu"
    Remove-Module -Name "run"
    
    if ($(vars).WebSites) {
        Global:Add-Module "$($(vars).web)\methods.psm1"
        Global:Add-Module "$($(vars).background)\webstats.psm1"
        Global:Send-WebStats
    }

    if ($(vars).BackgroundTimer.Elapsed.TotalSeconds -le 5) {
        $GoToSleep = [math]::Round(5 - $(vars).BackgroundTimer.Elapsed.TotalSeconds)
        if ($GoToSleep -gt 0) { Start-Sleep -S $GoToSleep }
    }
    
    Get-Job -State Completed | Remove-Job
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    [GC]::Collect()
    Clear-History
}