# Prida adresu do seznamu povolenych URL pro WebRequest v MetaTraderu 5.
#
# MT5 drzi toto nastaveni v config\common.ini (UTF-16) a cely soubor
# prepisuje pri ukonceni terminalu - proto musi byt pri uprave zavreny,
# jinak zmenu pri vypnuti prepise zpatky.
#
# Pouziti:
#   powershell -ExecutionPolicy Bypass -File scripts\allow-webrequest.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\allow-webrequest.ps1 -Url "http://192.168.0.157:8082" -Broker "IC Markets"

param(
    # Adresa serveru (schema, host a port - bez cesty za lomitkem)
    [string]$Url = "http://192.168.0.157:8082",
    # Cast nazvu instalacniho adresare terminalu (rozlisuje brokera)
    [string]$Broker = "RoboForex"
)

$ErrorActionPreference = "Stop"

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

# Bezici terminal by zmenu pri ukonceni prepsal, proto se uprava odmitne
$running = Get-Process -Name "terminal64" -ErrorAction SilentlyContinue |
           Where-Object { $_.Path -eq (Join-Path $installPath "terminal64.exe") }
if ($null -ne $running) {
    throw "Terminal bezi (PID $($running.Id -join ', ')). Zavri ho a spust skript znovu."
}

$ini = Join-Path $termRoot "config\common.ini"
if (-not (Test-Path $ini)) { throw "Soubor $ini nenalezen." }

# Zaloha pro pripad, ze by se format souboru lisil
Copy-Item $ini "$ini.bak" -Force

$lines = @(Get-Content $ini -Encoding Unicode)

# Posbira uz povolene adresy, aby se stejna nepridala dvakrat
$existing = @($lines | Where-Object { $_ -match '^\s*WebRequestUrl\s*=\s*(.+)$' } |
                       ForEach-Object { $matches[1].Trim() } |
                       Where-Object { $_ -ne "" })

if ($existing -contains $Url) {
    Write-Output "Adresa $Url uz je v seznamu povolenych."
} else {
    $existing += $Url
}

# Nove telo souboru: zahodi se stare radky WebRequestUrl a WebRequest,
# misto nich se do sekce [Experts] zapise aktualni seznam
$out = New-Object System.Collections.Generic.List[string]
$inExperts = $false
$written = $false

foreach ($line in $lines) {
    # Pri prechodu do dalsi sekce se dopisou radky, pokud se tak jeste nestalo
    if ($line -match '^\s*\[' ) {
        if ($inExperts -and -not $written) {
            $out.Add("WebRequest=1")
            foreach ($u in $existing) { $out.Add("WebRequestUrl=$u") }
            $written = $true
        }
        $inExperts = ($line.Trim() -eq "[Experts]")
    }

    # Puvodni radky nastaveni WebRequestu se nahrazuji, proto se preskoci
    if ($inExperts -and $line -match '^\s*WebRequest(Url)?\s*=') { continue }

    $out.Add($line)
}

# Sekce [Experts] byla posledni v souboru
if ($inExperts -and -not $written) {
    $out.Add("WebRequest=1")
    foreach ($u in $existing) { $out.Add("WebRequestUrl=$u") }
    $written = $true
}

if (-not $written) { throw "Sekce [Experts] nebyla v $ini nalezena." }

Set-Content -Path $ini -Value $out -Encoding Unicode

Write-Output "Povolene adresy pro WebRequest:"
$existing | ForEach-Object { Write-Output "  $_" }
Write-Output "Zapsano do $ini (zaloha $ini.bak)."
Write-Output "Spust terminal a zkontroluj Nastroje > Nastaveni > Expert Advisors."
