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

function Global:start-update {

    $Parent = Split-Path $(vars).dir
    log "User Specfied Updates: Searching For Previous Version" -ForegroundColor Yellow
    log "Checking $Parent For any Previous Versions"

    $PreviousVersions = @();
    $Folders = [IO.Directory]::GetDirectories($Parent) | Where-Object { $_ -like "*SWARM*" };

    if ([IO.File]::Exists("h-manifest.conf")) {
        [int]$version = [Convert]::ToInt32((Get-Content ".\h-manifest.conf" | `
                    ConvertFrom-StringData).CUSTOM_VERSION.replace(".", ""));
    }
    else {
        log "Warning: h-manifest.conf missing" -Foreground Red;
        return;
    }

    foreach ($Folder in $Folders) {
        $manifest = [IO.File]::Exists(([IO.Path]::Join($Folder, "h-manifest.conf")));
        $IsGit = [IO.Directory]::Exists(([IO.Path]::Join($Folder, ".git")));
        $IsCurrent = $Folder -eq $(vars).dir;

        if ($IsGit -and !$IsCurrent -and $manifest) {
            log "found previous version that was a git repository..Not updating it" -Foreground Yellow;
        }
        if (!$IsGit -and $Manifest -and !$IsCurrent) {
            $PreviousVersions += $Folder
        }
    }

    if ($PreviousVersions.Count -eq 0) {
        log "No valid SWARM versions to update" -Foreground Yellow;
        return;
    }

    $Global:amd = Get-Content ".\config\update\amd-linux.json" | ConvertFrom-Json
    $Global:nvidia = Get-Content ".\config\update\nvidia-linux.json" | ConvertFrom-Json
    $Global:cpu = Get-Content ".\config\update\cpu-linux.json" | ConvertFrom-Json

    if ($global:IsWindows) {
        $Global:amd = Get-Content ".\config\update\amd-win.json" | ConvertFrom-Json
        $Global:nvidia = Get-Content ".\config\update\nvidia-win.json" | ConvertFrom-Json
        $Global:cpu = Get-Content ".\config\update\cpu-win.json" | ConvertFrom-Json
    }

    $PreviousVersions | ForEach-Object {
        $Path = $_
        $Name = [IO.Path]::GetFileName($Path);
        log "Detected Another SWARM version: $Name" -Foreground Yellow
        $ThisVersion = (Get-Content ([IO.Path]::Join($Path,"h-manifest.conf")) | ConvertFrom-StringData).CUSTOM_VERSION;
        log "Previous Version is $ThisVersion" -Foreground Yellow
        $ThisVersion = [Convert]::ToInt32($ThisVersion.Replace(".",""));
        $Jsons = @("asic", "miners", "oc", "pools", "power", "wallets")
        if ($ThisVersion -gt $Version) { 
            $Jsons = @("asic", "oc", "power", "wallets")
            log "Version deteced is a new version than current" -ForeGroundColor Yellow
            log "Transferring old settings, but cannot transfer config\miners and config\pools folder data!" -ForeGroundColor Yellow
        }
        else {
            log "Gathering Old Version Config And HashRates- Then Deleting"
        }

        Start-Sleep -S 10  ## Gives User a chance to stop

        $ID = ".\build\pid\background_pid.txt"
        if ($global:IsWindows) {
            log "Stopping Previous Agent"
            if (Test-Path $ID) { $Agent = Get-Content $ID }
            if ($Agent) { $BackGroundID = Get-Process | Where-Object id -eq $Agent }
            if ($BackGroundID.name -eq "pwsh") { Stop-Process $BackGroundID | Out-Null }
        }

        $OldBackup = Join-Path $Path "backup";
        $OldBin = Join-Path $Path "bin";
        $OldStats = Join-Path $Path "stats";
        $OldTime = Join-Path $Path "build\data";
        $OldConfig = Join-Path $Path "config";
        $OldTimeout = Join-Path $Path "timeout";
        $OldAdmin = Join-Path $Path "admin";

        if (-not (Test-Path "backup")) { New-Item "backup" -ItemType "directory" | Out-Null }
        if (-not (Test-Path "stats")) { New-Item "stats" -ItemType "directory" | Out-Null }
        if (Test-Path $OldBin) { 
            try {
                Move-Item $OldBin -Destination "$($(vars).dir)" -Force | Out-Null 
            }
            catch {
                $Message = 
                "
SWARM attempted to move old bin folder but
there was a background process from a miner still active.
Access Denied Error prevented.
"                            
                log $Message -foreground Yellow
            }
        }
        if (test-path $OldStats) {
            Get-ChildItem -Path "$($OldStats)\*" -Include *.txt -Recurse | Copy-Item -Destination ".\stats"
        }
        if (test-path $OldBackup) {
            Get-ChildItem -Path "$($OldBackup)\*" -Include *.txt -Recurse | Copy-Item -Destination ".\backup"
        }
        if (Test-Path $OldAdmin) {
            if (-not (Test-Path ".\admin")) { New-Item ".\admin" -ItemType "directory" | Out-Null }
            Get-ChildItem -Path "$($OldAdmin)\*" -Include *.txt -Recurse | Copy-Item -Destination ".\admin"
        }
        #if (Test-Path $OldTime) { Get-ChildItem -Path "$($OldTime)\*" -Include *.txt -Recurse | Copy-Item -Destination ".\build\data" }
        if (Test-Path $OldTimeout) {
            if (-not (Test-Path ".\timeout")) { New-Item "timeout" -ItemType "directory" | Out-Null }
            if (-not (Test-Path ".\timeout\algo_block")) { New-Item ".\timeout\algo_block" -ItemType "directory" | Out-Null }
            if (-not (Test-Path ".\timeout\pool_block")) { New-Item ".\timeout\pool_block" -ItemType "directory" | Out-Null }
            if (Test-Path "$OldTimeout\algo_block") { Get-ChildItem -Path "$($OldTimeout)\algo_block" -Include *.txt, *.conf -Recurse | Copy-Item -Destination ".\timeout\algo_block" }
            if (Test-Path "$OldTimeout\algo_block") { Get-ChildItem -Path "$($OldTimeout)\pool_block" -Include *.txt, *.conf -Recurse | Copy-Item -Destination ".\timeout\pool_block" }
            Get-ChildItem -Path "$($OldTimeout)\*" -Include *.txt | Copy-Item -Destination ".\timeout"
        }

        $UpdateType = @("CPU", "AMD1", "NVIDIA1", "NVIDIA2", "NVIDIA3")

        $Jsons | ForEach-Object {
            $OldJson_Path = Join-Path $OldConfig "$($_)";
            $NewJson_Path = Join-Path ".\config" "$($_)";
            $GetOld_Json = (Get-ChildItem $OldJson_Path).Name | Where-Object { $_ -notlike "*md*" };
            $GetOld_Json | ForEach-Object {
                $ChangeFile = $_
                $OldJson = Join-Path $OldJson_Path "$ChangeFile";
                $NewJson = Join-Path $NewJson_Path "$ChangeFile";
                if ($ChangeFile -notin $Exclude) {
                    $JsonData = Get-Content $OldJson;
                    log "Pulled $OldJson"

                    try { $Data = $JsonData | ConvertFrom-Json -ErrorAction Stop } catch { }
 
                    $Data | ConvertTo-Json -Depth 10 | Set-Content $NewJson;
                    log "Wrote To $NewJson"
                }
            }
        }

        $NameJson_Path = Join-Path ".\config" "miners";
        $GetOld_Json = Get-ChildItem $NameJson_Path | Where-Object Extension -ne ".md"
        $GetOld_Json = $GetOld_Json.Name
        $GetOld_Json | ForEach-Object {
            $ChangeFile = $_
            $NewName = $ChangeFile -Replace ".json", "";
            $NameJson = Join-Path ".\config\miners" "$ChangeFile";
            $JsonData = Get-Content $NameJson;
            log "Pulled $NameJson"
            $Data = $JsonData | ConvertFrom-Json;
            $Data | Add-Member "name" "$NewName" -ErrorAction SilentlyContinue
            $Data | ConvertTo-Json -Depth 10 | Set-Content $NameJson;
            log "Wrote To $NameJson"
        }

        $Global:amd.PSobject.Properties.Name | ForEach-Object {
            if ($_ -ne "name") {
                if (-not (Test-Path ".\bin")) { New-Item -Name "bin" -ItemType Directory }
                $MinerPath1 = Join-Path $Path ( Split-Path $($Global:amd.$_.AMD1 -replace "\.", ""))
                $NewMinerPath1 = Join-Path $($(vars).dir) ( Split-Path $($Global:amd.$_.AMD1 -replace "\.", ""))
                if ( Test-Path $Minerpath1 ) {
                    $SwarmV = "$Minerpath1\swarm-version.txt"
                    if (Test-Path $SWARMV) {    
                        $GetVersion = Get-Content "$Minerpath1\swarm-version.txt"
                        if ($GetVersion -eq $Global:amd.$_.version) {
                            log "Moving $MinerPath1"
                            Move-Item $MinerPath1 $NewMinerPath1
                        }
                    }
                }
            }
        }

        $Global:cpu.PSobject.Properties.Name | ForEach-Object {
            if ($_ -ne "name") {
                if (-not (Test-Path ".\bin")) { New-Item -Name "bin" -ItemType Directory }
                $MinerPath1 = Join-Path $Path ( Split-Path $($Global:cpu.$_.CPU -replace "\.", ""))
                $NewMinerPath1 = Join-Path $($(vars).dir) ( Split-Path $($Global:cpu.$_.CPU -replace "\.", ""))
                if ( Test-Path $Minerpath1 ) {
                    $SwarmV = "$Minerpath1\swarm-version.txt"
                    if (Test-Path $SWARMV) {
                        $GetVersion = Get-Content $SwarmV
                        if ($GetVersion -eq $Global:cpu.$_.version) {
                            log "Moving $MinerPath1"
                            Move-Item $MinerPath1 $NewMinerPath1
                        }
                    }
                }
            }
        }

        $Global:nvidia.PSobject.Properties.Name | ForEach-Object {
            if ($_ -ne "name") {
                if (-not (Test-Path ".\bin")) { New-Item -Name "bin" -ItemType Directory }
                $MinerPath1 = Join-Path $Path ( Split-Path $($Global:nvidia.$_.NVIDIA1 -replace "\.", ""))
                $NewMinerPath1 = Join-Path $($(vars).dir) ( Split-Path $($Global:nvidia.$_.NVIDIA1 -replace "\.", ""))
                $MinerPath2 = Join-Path $Path ( Split-Path $($Global:nvidia.$_.NVIDIA2 -replace "\.", ""))
                $NewMinerPath2 = Join-Path $($(vars).dir) ( Split-Path $($Global:nvidia.$_.NVIDIA2 -replace "\.", ""))
                $MinerPath3 = Join-Path $Path ( Split-Path $($Global:nvidia.$_.NVIDIA3 -replace "\.", ""))
                $NewMinerPath3 = Join-Path $($(vars).dir) ( Split-Path $($Global:nvidia.$_.NVIDIA3 -replace "\.", ""))
                if ( Test-Path $Minerpath1 ) {
                    $SwarmV = "$Minerpath1\swarm-version.txt"
                    if (Test-Path $SWARMV) {
                        $GetVersion = Get-Content $SwarmV
                        if ($GetVersion -eq $Global:nvidia.$_.version) {
                            log "Moving $MinerPath1"
                            Move-Item $MinerPath1 $NewMinerPath1
                        }
                    }
                }
                if ( Test-Path $Minerpath2 ) {
                    $SwarmV = "$Minerpath2\swarm-version.txt"
                    if (Test-Path $SWARMV) {
                        $GetVersion = Get-Content $SwarmV
                        if ($GetVersion -eq $Global:nvidia.$_.version) {
                            log "Moving $MinerPath2"
                            Move-Item $MinerPath2 $NewMinerPath2
                        }
                    }
                }
                if ( Test-Path $Minerpath3 ) {
                    $SwarmV = "$Minerpath3\swarm-version.txt"
                    if (Test-Path $SWARMV) {
                        $GetVersion = Get-Content $SwarmV
                        $GetVersion = Get-Content "$Minerpath3\swarm-version.txt"
                        if ($GetVersion -eq $Global:nvidia.$_.version) {
                            log "Moving $MinerPath3"
                            Move-Item $MinerPath3 $NewMinerPath3
                        }
                    }
                }
            }
        }

        Remove-Item $Path -recurse -force
    }
}

function Global:Start-AgentCheck {
    log "Stopping Previous Agent"
    $ID = ".\build\pid\background_pid.txt"
    if (Test-Path $ID) { $Agent = Get-Content $ID }
    if ($Agent) { $BackGroundID = Get-Process | Where-Object id -eq $Agent }
    if ($BackGroundID.name -eq "pwsh") { Stop-Process $BackGroundID | Out-Null }
    $ID = ".\build\pid\pill_pid.txt"
    if (Test-Path $ID) { $Agent = Get-Content $ID }
    if ($Agent) { $BackGroundID = Get-Process | Where-Object id -eq $Agent }
    if ($BackGroundID.name -eq "pwsh") { Stop-Process $BackGroundID | Out-Null }    
}

