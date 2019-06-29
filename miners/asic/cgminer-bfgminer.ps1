$(vars).ASICTypes | ForEach-Object {

    $ConfigType = $_; $Num = $ConfigType -replace "ASIC", ""

    ## Miner Path Information
    $URI = "Not Needed"
    $MinerName = "cgminer"
    $Path = "no path"

    $User = "User1"; $Name = "asicminer-$Num"

    $Devices = $null

    if ($(vars).Coins -eq $true) { $Pools = $(vars).CoinPools } else { $Pools = $(vars).AlgoPools }

    if ($(vars).Bancount -lt 1) { $(vars).Bancount = 5 }


    $(arg).ASIC_ALGO | ForEach-Object {

        $MinerAlgo = $_
        $StatAlgo = $MinerAlgo -replace "`_", "`-"
        $Stat = Global:Get-Stat -Name "$($Name)_$($MinerAlgo)_hashrate"

        if ($MinerAlgo -in $(vars).Algorithm -and $Name -notin $global:Config.Pool_Algos.$MinerAlgo.exclusions -and $ConfigType -notin $global:Config.Pool_Algos.$MinerAlgo.exclusions -and $Name -notin $(vars).BanHammer) {
            $Pools | Where-Object Algorithm -eq $MinerAlgo | ForEach-Object {
                $Pass = $_.Pass1 -replace ",", "`\,"
                if ($(vars).ASICS.$ConfigType.NickName) {
                    $Pass = $Pass -replace "$($(arg).Rigname1)", "$($(vars).ASICS.$ConfigType.NickName)"
                }
                [PSCustomObject]@{
                    MName      = $Name
                    Coin       = $(vars).Coins
                    Delay      = $MinerConfig.$ConfigType.delay
                    Fees       = $MinerConfig.$ConfigType.fee.$($_.Algorithm)
                    Symbol     = "$($_.Symbol)"
                    MinerName  = $MinerName
                    Type       = $ConfigType
                    Path       = $Path
                    Devices    = $Devices
                    Stratum    = "$($_.Stratum)://$($_.Host):$($_.Port)" 
                    DeviceCall = "cgminer"
                    Wallet     = "$($_.$User)"
                    Arguments  = "stratum+tcp://$($_.Host):$($_.Port),$($_.$User),$Pass"
                    HashRates  = $Stat.Hour
                    Quote      = if ($Stat.Hour) { $Stat.Hour * ($_.Price) }else { 0 }
                    Power      = if ($(vars).Watts.$($_.Algorithm)."$($ConfigType)_Watts") { $(vars).Watts.$($_.Algorithm)."$($ConfigType)_Watts" }elseif ($(vars).Watts.default."$($ConfigType)_Watts") { $(vars).Watts.default."$($ConfigType)_Watts" }else { 0 }
                    MinerPool  = "$($_.Name)"
                    Port       = 4028
                    Worker     = $($(vars).ASICS.$ConfigType.NickName)
                    API        = "cgminer"
                    URI        = $Uri
                    Server     = $(vars).ASICS.$ConfigType.IP
                    BUILD      = $Build
                    Algo       = "$($_.Algorithm)"
                    Log        = "miner_generated"
                }
            }
        }
    }
}
