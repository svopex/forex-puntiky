# Nasazeni strategie Sved Channel Breakout do MetaTraderu 5.
#
# Skript zkopiruje zdrojove soubory z repozitare do datoveho adresare
# terminalu a nasledne je zkompiluje pres MetaEditor.
#
# Pouziti:
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Broker "IC Markets"

param(
    # Cast nazvu instalacniho adresare terminalu (rozlisuje brokera)
    [string]$Broker = "RoboForex",
    # Preskocit kompilaci a jen zkopirovat soubory
    [switch]$NoCompile
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot  = Join-Path $repoRoot "MQL5"

# Najde instalacni adresar terminalu podle nazvu brokera
$install = Get-ChildItem "C:\Program Files" -Directory |
           Where-Object { $_.Name -like "*$Broker*" } |
           Select-Object -First 1
if ($null -eq $install) {
    throw "Instalace terminalu pro brokera '$Broker' nebyla nalezena."
}
$installPath = $install.FullName

# Datovy adresar terminalu se pozna podle souboru origin.txt, ktery
# obsahuje cestu k instalaci (soubor je v UTF-16 s BOM)
$termRoot = $null
foreach ($dir in Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory) {
    $originFile = Join-Path $dir.FullName "origin.txt"
    if (-not (Test-Path $originFile)) { continue }
    $origin = (Get-Content $originFile -Raw -Encoding Unicode).Trim([char]0xFEFF, ' ', "`r", "`n", "`0")
    if ($origin -eq $installPath) { $termRoot = $dir.FullName; break }
}
if ($null -eq $termRoot) {
    throw "Datovy adresar terminalu pro '$installPath' nebyl nalezen."
}

Write-Output "Terminal:  $installPath"
Write-Output "Data:      $termRoot"

# Kopie zdrojovych souboru do datoveho adresare terminalu
$dstExperts = Join-Path $termRoot "MQL5\Experts\Sved"
$dstInclude = Join-Path $termRoot "MQL5\Include\Sved"
New-Item -ItemType Directory -Force -Path $dstExperts, $dstInclude | Out-Null

Copy-Item (Join-Path $srcRoot "Experts\Sved\*.mq5") $dstExperts -Force
Copy-Item (Join-Path $srcRoot "Include\Sved\*.mqh") $dstInclude -Force
Write-Output "Zkopirovano do $dstExperts a $dstInclude"

if ($NoCompile) { return }

# Kompilace pres MetaEditor - vysledek se cte z logu (log je v UTF-16)
$editor = Join-Path $installPath "MetaEditor64.exe"
if (-not (Test-Path $editor)) { throw "MetaEditor64.exe nenalezen v $installPath" }

$source = Join-Path $dstExperts "SvedChannelBreakout.mq5"
$log    = Join-Path $env:TEMP "sved_compile.log"
if (Test-Path $log) { Remove-Item $log -Force }

Start-Process -FilePath $editor `
              -ArgumentList "/compile:`"$source`"", "/log:`"$log`"" `
              -Wait -NoNewWindow

if (Test-Path $log) {
    $result = Get-Content $log -Encoding Unicode | Where-Object { $_ -match "error|warning|Result" }
    $result | ForEach-Object { Write-Output $_ }
} else {
    Write-Output "Log kompilace nebyl vytvoren."
}

$ex5 = Join-Path $dstExperts "SvedChannelBreakout.ex5"
if (Test-Path $ex5) {
    Write-Output "Hotovo: $ex5"
} else {
    throw "Kompilace selhala - .ex5 nebyl vytvoren."
}
