<#
.SYNOPSIS
    Empacota uma extensao do pyRevit (por padrao a 3fstudio) junto com as
    configuracoes relevantes, gerando um .zip pronto para instalar em outra maquina.

.DESCRIPTION
    O script procura a pasta <nome>.extension nos locais usuais do pyRevit
    (pastas registradas em userextensions, %APPDATA%\pyRevit\Extensions,
    %PROGRAMDATA%\pyRevit\Extensions e extensoes de clones), copia o conteudo
    ignorando __pycache__/.git/*.pyc, inclui uma copia do pyRevit_config.ini e
    grava um manifest.json descrevendo o pacote.

.PARAMETER Name
    Nome (ou parte do nome) da extensao. Padrao: 3fstudio.

.PARAMETER SourcePath
    Caminho explicito da pasta .extension. Quando informado, a busca automatica
    e ignorada. Aceita varios caminhos.

.PARAMETER OutputPath
    Pasta onde o .zip sera criado. Padrao: a pasta atual.

.PARAMETER ConfigPath
    Caminho do pyRevit_config.ini de origem. Padrao: %APPDATA%\pyRevit\pyRevit_config.ini.

.PARAMETER SkipConfig
    Nao inclui o pyRevit_config.ini no pacote (so as extensoes).

.PARAMETER NoZip
    Deixa o pacote como pasta, sem compactar.

.EXAMPLE
    .\Export-PyRevitPackage.ps1
    Empacota a extensao 3fstudio na pasta atual.

.EXAMPLE
    .\Export-PyRevitPackage.ps1 -Name 3fstudio -OutputPath D:\Temp -Verbose
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = '3fstudio',
    [string[]]$SourcePath,
    [string]$OutputPath = (Get-Location).Path,
    [string]$ConfigPath,
    [switch]$SkipConfig,
    [switch]$NoZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'PyRevitIni.psm1') -Force

if (-not $ConfigPath) { $ConfigPath = Get-PyRevitConfigPath }

function Resolve-ExtensionFolder {
    param([string]$Pattern, [string[]]$Explicit)

    if ($Explicit) {
        foreach ($p in $Explicit) {
            if (-not (Test-Path -LiteralPath $p)) {
                throw "Caminho informado em -SourcePath nao existe: $p"
            }
            Get-Item -LiteralPath $p
        }
        return
    }

    $found = @{}
    foreach ($root in (Get-PyRevitExtensionSearchPath -ConfigPath $ConfigPath)) {
        Write-Verbose "Procurando em: $root"
        $candidates = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$Pattern*" -and $_.Name -match '\.(extension|lib)$' }
        foreach ($c in $candidates) {
            $key = $c.Name.ToLowerInvariant()
            if ($found.ContainsKey($key)) {
                Write-Verbose "Ignorando duplicata: $($c.FullName)"
                continue
            }
            $found[$key] = $true
            $c
        }
    }
}

$extensions = @(Resolve-ExtensionFolder -Pattern $Name -Explicit $SourcePath)
if ($extensions.Count -eq 0) {
    Write-Host 'Pastas verificadas:' -ForegroundColor Yellow
    Get-PyRevitExtensionSearchPath -ConfigPath $ConfigPath | ForEach-Object { Write-Host "  $_" }
    throw "Nenhuma extensao com '$Name' no nome foi encontrada. Use -SourcePath para indicar a pasta manualmente."
}

Write-Host "Extensoes encontradas ($($extensions.Count)):" -ForegroundColor Cyan
$extensions | ForEach-Object { Write-Host "  $($_.FullName)" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$packageName = "$Name-pyrevit-package-$stamp"
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) $packageName

if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
if (-not $PSCmdlet.ShouldProcess($stagingRoot, 'Montar pacote')) { return }

New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
$extRoot = Join-Path $stagingRoot 'extensions'
New-Item -ItemType Directory -Path $extRoot -Force | Out-Null

$manifestExtensions = @()
foreach ($ext in $extensions) {
    $dest = Join-Path $extRoot $ext.Name
    Write-Host "Copiando $($ext.Name)..." -ForegroundColor Cyan
    Copy-ExtensionTree -Source $ext.FullName -Destination $dest

    $files = @(Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue)
    $size = 0
    if ($files.Count -gt 0) { $size = ($files | Measure-Object -Property Length -Sum).Sum }
    $manifestExtensions += [pscustomobject]@{
        name       = $ext.Name
        sourcePath = $ext.FullName
        fileCount  = $files.Count
        sizeBytes  = [int64]$size
    }
}

$configIncluded = $false
$extensionSections = @()
if (-not $SkipConfig) {
    if (Test-Path -LiteralPath $ConfigPath) {
        $configDir = Join-Path $stagingRoot 'config'
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $configDir 'pyRevit_config.ini') -Force
        $configIncluded = $true

        $ini = Read-PyRevitIni -Path $ConfigPath
        foreach ($section in $ini.Keys) {
            foreach ($ext in $extensions) {
                $extKey = $ext.Name -replace '\.(extension|lib)$', ''
                if ($section -like "$extKey*") { $extensionSections += $section }
            }
        }
        Write-Host "Configuracao incluida: $ConfigPath" -ForegroundColor Cyan
    } else {
        Write-Warning "pyRevit_config.ini nao encontrado em '$ConfigPath'. O pacote seguira sem configuracao."
    }
}

$pyrevitVersion = $null
$cli = Get-Command pyrevit -ErrorAction SilentlyContinue
if ($cli) {
    try { $pyrevitVersion = (& $cli.Path --version 2>$null | Select-Object -First 1) } catch { }
}

$manifest = [pscustomobject]@{
    packageFormat     = 1
    extensionName     = $Name
    createdUtc        = (Get-Date).ToUniversalTime().ToString('o')
    createdOnMachine  = $env:COMPUTERNAME
    pyrevitVersion    = $pyrevitVersion
    includesConfig    = $configIncluded
    configSections    = @($extensionSections | Select-Object -Unique)
    extensions        = @($manifestExtensions)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stagingRoot 'manifest.json') -Encoding UTF8

# O instalador viaja junto com o pacote.
$toolsDir = Join-Path $stagingRoot 'tools'
New-Item -ItemType Directory -Path (Join-Path $toolsDir 'lib') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-PyRevitPackage.ps1') -Destination $toolsDir -Force
Copy-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'lib') 'PyRevitIni.psm1') -Destination (Join-Path $toolsDir 'lib') -Force
$installerBat = Join-Path $PSScriptRoot 'Instalar.bat'
if (Test-Path -LiteralPath $installerBat) {
    Copy-Item -LiteralPath $installerBat -Destination $stagingRoot -Force
}
$readme = Join-Path $PSScriptRoot 'README.md'
if (Test-Path -LiteralPath $readme) {
    Copy-Item -LiteralPath $readme -Destination $stagingRoot -Force
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}
$OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path

if ($NoZip) {
    $final = Join-Path $OutputPath $packageName
    if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Recurse -Force }
    Move-Item -LiteralPath $stagingRoot -Destination $final
    Write-Host "`nPacote pronto: $final" -ForegroundColor Green
} else {
    $zipPath = Join-Path $OutputPath "$packageName.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    $sizeMb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 2)
    Write-Host "`nPacote pronto: $zipPath ($sizeMb MB)" -ForegroundColor Green
    Write-Host 'Copie esse arquivo para a outra maquina e rode Instalar.bat (ou tools\Install-PyRevitPackage.ps1).'
}
