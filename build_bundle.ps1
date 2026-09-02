# build_bundle.ps1 — reconstruye el bundle self-contained de SpeedstersBeyond. LF, UTF8 sin BOM.
# Ensambla los factories (feature-por-carpeta) en SpeedstersBeyond.lua para loadstring-raw.
# Obsidian se carga en runtime dentro de main.lua (loadstring de su raw), NO se inlinea aquí.
$ErrorActionPreference = "Stop"
$Root = "C:\Users\trabajo\OneDrive\Escritorio\Scripts\SpeedstersBeyond"
$Out  = Join-Path $Root "SpeedstersBeyond.lua"

# ORDER: Core.State primero, main ultimo. require lazy → posicion del medio no importa, solo que TODO
# modulo requerido este presente. Escanear las carpetas evita quedar stale al agregar features nuevas.
$ORDER = @("Core/State.lua", "Net.lua")
foreach ($d in @("Movement", "AntiIdle", "Jobs", "Treadmill", "Ascension", "Economy", "Extras", "Safety")) {
    $dir = Join-Path $Root $d
    if (Test-Path $dir) {
        Get-ChildItem $dir -Filter *.lua | Sort-Object Name | ForEach-Object { $ORDER += "$d/$($_.Name)" }
    }
}
$ORDER += @("UI.lua", "main.lua")

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("-- SpeedstersBeyond bundle self-contained. No editar a mano (generado por build_bundle.ps1).`n")
[void]$sb.Append("local _MODS = {}`n")

foreach ($rel in $ORDER) {
    $p = Join-Path $Root $rel
    if (-not (Test-Path $p)) { Write-Host "[build] SKIP (no existe): $rel"; continue }
    $src  = [System.IO.File]::ReadAllText($p) -replace "`r`n","`n"
    $name = ($rel -replace "\.lua$","") -replace "/","."
    [void]$sb.Append("_MODS[`"$name`"] = (function()`n")
    [void]$sb.Append($src)
    [void]$sb.Append("`nend)()`n")
    Write-Host "[build] + $name"
}

[void]$sb.Append(@"
local _cache = {}
local SB
local function require(name)
    if _cache[name] then return _cache[name] end
    local factory = _MODS[name]
    if not factory then error("[SB] modulo no encontrado: " .. tostring(name)) end
    local m = factory(require, SB, nil)
    _cache[name] = m
    return m
end
-- Core.State crea el global SB (ignora su param). Lib (Obsidian) la carga main en runtime.
SB = _MODS["Core.State"](require, nil, nil)
_cache["Core.State"] = SB
SB.require = require
_MODS["main"](require, SB, nil)
return SB
"@.Replace("`r`n","`n"))

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Out, $sb.ToString(), $enc)
$len = (Get-Item $Out).Length
Write-Host "[build] OK -> $Out ($len bytes)"
