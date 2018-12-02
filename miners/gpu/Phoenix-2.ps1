if($nvidia.phoenix.path2){$Path = "$($nvidia.phoenix.path2)"}
else{$Path = "None"}
if($nvidia.phoenix.uri){$Uri = "$($nvidia.phoenix.uri)"}
else{$Uri = "None"}
if($nvidia.phoenix.minername){$MinerName = "$($nvidia.phoenix.minername)"}
else{$MinerName = "None"}
if($Platform -eq "linux"){$Build = "Tar"}
elseif($Platform -eq "windows"){$Build = "Zip"}

$ConfigType = "NVIDIA2"

##Parse -GPUDevices
if($NVIDIADevices2 -ne ''){
$ClayDevices2  = $NVIDIADevices2 -split ","
$ClayDevices2  = Switch($ClayDevices2){"10"{"a"};"11"{"b"};"12"{"c"};"13"{"d"};"14"{"e"};"15"{"f"};"16"{"g"};"17"{"h"};"18"{"i"};"19"{"j"};"20"{"k"};default{"$_"};}
$ClayDevices2  = $ClayDevices2 | foreach {$_ -replace ("$($_)",",$($_)")}
$ClayDevices2  = $ClayDevices2 -join ""
$ClayDevices2  = $ClayDevices2.TrimStart(" ",",")  
$ClayDevices2 = $ClayDevices2 -replace(",","")
$Devices = $ClayDevices2}

##Get Configuration File
$GetConfig = "$dir\config\miners\phoenix.json"
try{$Config = Get-Content $GetConfig | ConvertFrom-Json}
catch{Write-Warning "Warning: No config found at $GetConfig"}

##Export would be /path/to/[SWARMVERSION]/build/export##
$ExportDir = Join-Path $dir "build\export"

##Prestart actions before miner launch
$BE = "/usr/lib/x86_64-linux-gnu/libcurl-compat.so.3.0.0"
$Prestart = @()
$PreStart += "export LD_LIBRARY_PATH=$ExportDir"
$Config.$ConfigType.prestart | foreach {$Prestart += "$($_)"}

##Build Miner Settings
if($CoinAlgo -eq $null)
{
  $Config.$ConfigType.commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
  $MinerAlgo = $_
  $AlgoPools | Where Symbol -eq $MinerAlgo | foreach {
  if($Algorithm -eq "$($_.Algorithm)")
  {
  if($Config.$ConfigType.difficulty.$($_.Algorithm)){$Diff=",d=$($Config.$ConfigType.difficulty.$($_.Algorithm))"}
  [PSCustomObject]@{
    Delay = $Config.$ConfigType.delay
    Symbol = "$($_.Algorithm)"
  MinerName = $MinerName
  Prestart = $PreStart
  Type = $ConfigType
  Path = $Path
  Devices = $Devices
  DeviceCall = "claymore"
  Arguments = "-platform 2 -mport 3334 -mode 1 -allcoins 1 -allpools 1 -epool $($_.Protocol)://$($_.Host):$($_.Port) -ewal $($_.User2) -epsw $($_.Pass2)$($Diff) -wd 0 -dbg -1 -eres 1 $($Config.$ConfigType.commands.$($_.Algorithm))"
  HashRates = [PSCustomObject]@{$($_.Algorithm) = $($Stats."$($Name)_$($_.Algorithm)_hashrate".Day)}
  Quote = if($($Stats."$($Name)_$($_.Algorithm)_hashrate".Day)){$($Stats."$($Name)_$($_.Algorithm)_hashrate".Day)*($_.Price)}else{0}
  PowerX = [PSCustomObject]@{$($_.Algorithm) = if($Watts.$($_.Algorithm)."$($ConfigType)_Watts"){$Watts.$($_.Algorithm)."$($ConfigType)_Watts"}elseif($Watts.default."$($ConfigType)_Watts"){$Watts.default."$($ConfigType)_Watts"}else{0}}
  ocpower = if($Config.$ConfigType.oc.$($_.Algorithm).power){$Config.$ConfigType.oc.$($_.Algorithm).power}else{$OC."default_$($ConfigType)".Power}
  occore = if($Config.$ConfigType.oc.$($_.Algorithm).core){$Config.$ConfigType.oc.$($_.Algorithm).core}else{$OC."default_$($ConfigType)".core}
  ocmem = if($Config.$ConfigType.oc.$($_.Algorithm).memory){$Config.$ConfigType.oc.$($_.Algorithm).memory}else{$OC."default_$($ConfigType)".memory}
  ethpill = $Config.$ConfigType.oc.$($_.Algorithm).ethpill
  pilldelay = $Config.$ConfigType.oc.$($_.Algorithm).pilldelay
  FullName = "$($_.Mining)"
  API = "ethminer"
  Port = 3334
  MinerPool = "$($_.Name)"
  URI = $Uri
  BUILD = $Build
  Algo = "$($_.Algorithm)"
      }
    }
  }
 }
}