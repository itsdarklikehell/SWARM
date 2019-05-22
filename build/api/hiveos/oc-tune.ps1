
function Start-HiveTune {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Algo
    )

    Write-Log "Checking Hive OC Tuning" -ForegroundColor Cyan
    $Algo = $Algo -replace "`_", " "
    $Url = "https://api2.hiveos.farm/api/v2/farms/$($Global:Config.hive_params.FarmID)/workers/$($Global:Config.hive_params.HiveID)"
    $CheckOC = $false
    $CheckDate = Get-Date

    ## Generate New Auth Token:
    #$Auth = @{ login = "User"; password = "pass"; twofa_code = ""; remember = $true; } | ConvertTo-Json -Compress
    #$Url = "https://api2.hiveos.farm/api/v2/auth/login"
    #$A = Invoke-RestMethod $Url -Method Post -Body $Auth -ContentType 'application/json' -TimeoutSec 10
    #Token = $A.access_token

    ## Get Current Worker:
    $T = @{Authorization = "Bearer $($global:Config.Params.API_Key)" }
    $Splat = @{ Method = "GET"; Uri = $Url; Headers = $T; ContentType = 'application/json'; }
    try { $A = Invoke-RestMethod @Splat -TimeoutSec 10 -ErrorAction Stop } catch { Write-log "WARNING: Failed to Contact HiveOS for OC" -ForegroundColor Yellow; return }

    ## Patch Worker:
    if ($Algo -in $A.oc_config.by_algo.algo) { $Choice = $Algo; $Message = $Choice} else { $choice = $null; $Message = "Default" }
        Write-Log "Setting Hive OC to $Message Settings" -ForegroundColor Cyan
    if ($A.oc_algo -ne $Choice) {
        Write-Log "Contacting HiveOS To Set $Message as current OC setting" -ForegroundColor Cyan
        $T = @{Authorization = "Bearer $($global:Config.Params.API_Key)" }
        $Command = @{oc_algo = $Choice } | ConvertTo-Json
        $Splat = @{ Method = "Patch"; Uri = $Url; Headers = $T; ContentType = 'application/json'; }
        try { $A = Invoke-RestMethod @Splat -Body $Command -TimeoutSec 10 -ErrorAction Stop }catch { Write-Log "WARNING: Failed To Send OC to HiveOS" -ForegroundColor Yellow; return }
        if ($A.commands.id) { Write-Log "Sent OC to HiveOS" -ForegroundColor Green; $CheckOC = $true; }
    } else {
        Write-Log "HiveOS Settings Already Set to $Message" -ForegroundColor Cyan
    }

    if ($CheckOC) {
        $Global:Config.params.Type | ForEach-Object {
            if ($_ -like "*NVIDIA*") { $CheckNVIDIA = $true }
            if ($_ -like "*AMD*") { $CheckAMD = $True }
        }
        switch ($Global:Config.params.Platform) {
            "windows" {
                if ($CheckNVIDIA) {
                    Write-Log "Verifying OC was Set...." -ForegroundColor Cyan
                    $OCT = New-Object -TypeName System.Diagnostics.Stopwatch
                    $OCT.Restart()
                    do {
                        $CheckFile = ".\build\txt\ocnvidia.txt"
                        $LastWrite = Get-Item $CheckFile | Foreach { $_.LastWriteTime }
                        Start-Sleep -Milliseconds 50
                    } While ( ($LastWrite - $CheckDate).TotalSeconds -lt 0 -or $OCT.Elapsed.TotalSeconds -lt 15 )
                    $OCT.Stop()
                    if($OCT.Elapsed.TotalSeconds -gt 15){Write-Log "WARNING: HiveOS did not set OC." -ForegroundColor Yellow}
                }
                if ($CheckAMD) {
                    Write-Log "Verifying OC was Set...." -ForegroundColor Cyan
                    $OCT = New-Object -TypeName System.Diagnostics.Stopwatch
                    $OCT.Restart()
                    do {
                        $CheckFile = ".\build\txt\ocamd.txt"
                        $LastWrite = Get-Item $CheckFile | Foreach { $_.LastWriteTime }
                        Start-Sleep -Milliseconds 50
                    } While ( ($LastWrite - $CheckDate).TotalSeconds -lt 0 -or $OCT.Elapsed.TotalSeconds -lt 15 )
                    $OCT.Stop()
                    if($OCT.Elapsed.TotalSeconds -gt 15){Write-Log "WARNING: HiveOS did not set OC." -ForegroundColor Yellow}
                }
            }
            "linux" {
                if ($CheckNVIDIA) {
                    Write-Log "Verifying OC was Set...." -ForegroundColor Cyan
                    $OCT = New-Object -TypeName System.Diagnostics.Stopwatch
                    $OCT.Restart()
                    do {
                        $Checkfile = "/var/log/nvidia-oc.log"
                        $LastWrite = Get-Item $CheckFile | Foreach { $_.LastWriteTime }
                        Start-Sleep -Milliseconds 50
                    } While (($LastWrite - $CheckDate).TotalSeconds -lt 0)
                    $OCT.Stop()
                    if($OCT.Elapsed.TotalSeconds -gt 15 -or $OCT.Elapsed.TotalSeconds -lt 15 ){Write-Log "WARNING: HiveOS did not set OC." -ForegroundColor Yellow}
                }
                if ($CheckAMD) {
                    Write-Log "Verifying OC was Set...." -ForegroundColor Cyan
                    $OCT = New-Object -TypeName System.Diagnostics.Stopwatch
                    $OCT.Restart()
                    do {
                        $Checkfile = "/var/log/amd-oc.log"
                        $LastWrite = Get-Item $CheckFile | Foreach { $_.LastWriteTime }
                        Start-Sleep -Milliseconds 50
                    } While (($LastWrite - $CheckDate).TotalSeconds -lt 0)
                    $OCT.Stop()
                    if($OCT.Elapsed.TotalSeconds -gt 15 -or $OCT.Elapsed.TotalSeconds -lt 15){Write-Log "WARNING: HiveOS did not set OC." -ForegroundColor Yellow}
                }
            }
        }
    }
}