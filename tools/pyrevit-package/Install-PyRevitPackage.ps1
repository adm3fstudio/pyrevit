<#
.SYNOPSIS
    Instala na maquina atual um pacote gerado por Export-PyRevitPackage.ps1.

.DESCRIPTION
    Copia as extensoes do pacote para a pasta de extensoes do usuario, registra
    essa pasta em [core] userextensions do pyRevit_config.ini e mescla as secoes
    de configuracao especificas das extensoes empacotadas. O ini existente e
    salvo em backup antes de qualquer alteracao, assim como qualquer versao
    anterior das extensoes.

.PARAMETER PackagePath
    Caminho do .zip ou da pasta do pacote. Se omitido, o script usa a pasta onde
    ele mesmo esta (caso tipico: rodar tools\Install-PyRevitPackage.ps1 de dentro
    do pacote ja extraido).

.PARAMETER TargetPath
    Pasta de destino das extensoes. Padrao: %APPDATA%\pyRevit\Extensions.

.PARAMETER SkipConfig
    Instala apenas os arquivos, sem tocar no pyRevit_config.ini.

.PARAMETER IncludeCoreSettings
    Alem das secoes das extensoes, copia tambem preferencias gerais de [core]
    (rocketmode, bincache, loadbeta, etc.). Nao copia dados de ambiente/clones.

.PARAMETER Force
    Substitui extensoes ja instaladas sem criar copia de backup.

.EXAMPLE
    .\Install-PyRevitPackage.ps1 -PackagePath C:\Temp\3fstudio-pyrevit-package-20260917-1030.zip

.EXAMPLE
    .\Install-PyRevitPackage.ps1 -IncludeCoreSettings -Verbose
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackagePath,
    [string]$TargetPath = (Join-Path $env:APPDATA 'pyRevit\Extensions'),
    [string]$ConfigPath,
    [switch]$SkipConfig,
    [switch]$IncludeCoreSettings,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path (Join-Path $PSScriptRoot 'lib') 'PyRevitIni.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    $modulePath = Join-Path $PSScriptRoot 'PyRevitIni.psm1'
}
Import-Module $modulePath -Force

if (-not $ConfigPath) { $ConfigPath = Get-PyRevitConfigPath }

# ---------------------------------------------------------------- pacote ----
$tempExtract = $null
if (-not $PackagePath) {
    # Rodando de dentro do pacote extraido: manifest.json fica um nivel acima.
    $candidates = @($PSScriptRoot, (Split-Path -Parent $PSScriptRoot))
    $PackagePath = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'manifest.json')) } | Select-Object -First 1
    if (-not $PackagePath) {
        throw 'Informe -PackagePath: nao encontrei manifest.json perto deste script.'
    }
}

if (-not (Test-Path -LiteralPath $PackagePath)) {
    throw "Pacote nao encontrado: $PackagePath"
}

if ((Get-Item -LiteralPath $PackagePath).PSIsContainer) {
    $packageRoot = (Resolve-Path -LiteralPath $PackagePath).Path
} else {
    $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) ("pyrevit-pkg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Write-Verbose "Extraindo pacote em $tempExtract"
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $tempExtract -Force
    $packageRoot = $tempExtract
}

$manifestPath = Join-Path $packageRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "manifest.json nao encontrado em '$packageRoot'. O pacote parece invalido."
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "Pacote: $($manifest.extensionName)" -ForegroundColor Cyan
Write-Host "Gerado em: $($manifest.createdUtc) (maquina $($manifest.createdOnMachine))"

$sourceExtRoot = Join-Path $packageRoot 'extensions'
$sourceExtensions = @(Get-ChildItem -LiteralPath $sourceExtRoot -Directory -ErrorAction SilentlyContinue)
if ($sourceExtensions.Count -eq 0) { throw "O pacote nao contem extensoes em '$sourceExtRoot'." }

# --------------------------------------------------------------- arquivos ---
if (-not (Test-Path -LiteralPath $TargetPath)) {
    if ($PSCmdlet.ShouldProcess($TargetPath, 'Criar pasta de extensoes')) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }
}
if (Test-Path -LiteralPath $TargetPath) {
    $TargetPath = (Resolve-Path -LiteralPath $TargetPath).Path
}

$installed = @()
foreach ($ext in $sourceExtensions) {
    $dest = Join-Path $TargetPath $ext.Name

    if (Test-Path -LiteralPath $dest) {
        if ($Force) {
            if ($PSCmdlet.ShouldProcess($dest, 'Remover versao anterior')) {
                Remove-Item -LiteralPath $dest -Recurse -Force
            }
        } else {
            $backup = "$dest.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            if ($PSCmdlet.ShouldProcess($dest, "Mover versao anterior para $backup")) {
                Move-Item -LiteralPath $dest -Destination $backup
                Write-Host "Backup da versao anterior: $backup" -ForegroundColor Yellow
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($dest, 'Instalar extensao')) {
        Copy-ExtensionTree -Source $ext.FullName -Destination $dest
        Write-Host "Instalada: $dest" -ForegroundColor Green
        $installed += $ext.Name
    }
}

# ------------------------------------------------------------ configuracao --
if (-not $SkipConfig) {
    $packageConfig = Join-Path (Join-Path $packageRoot 'config') 'pyRevit_config.ini'
    $targetIni = Read-PyRevitIni -Path $ConfigPath
    $changed = $false

    if (Test-Path -LiteralPath $ConfigPath) {
        $iniBackup = "$ConfigPath.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        if ($PSCmdlet.ShouldProcess($ConfigPath, "Backup em $iniBackup")) {
            Copy-Item -LiteralPath $ConfigPath -Destination $iniBackup -Force
            Write-Host "Backup da configuracao: $iniBackup" -ForegroundColor Yellow
        }
    } else {
        Write-Warning "pyRevit_config.ini nao existe ainda em '$ConfigPath'. Um novo sera criado."
    }

    if (Add-PyRevitExtensionPath -Ini $targetIni -ExtensionDir $TargetPath) {
        Write-Host "Pasta registrada em [core] userextensions: $TargetPath" -ForegroundColor Green
        $changed = $true
    } else {
        Write-Verbose 'Pasta ja estava registrada em userextensions.'
    }

    if (Test-Path -LiteralPath $packageConfig) {
        $sourceIni = Read-PyRevitIni -Path $packageConfig

        # Secoes especificas das extensoes empacotadas (ex.: [3fstudio.extension]).
        foreach ($section in $sourceIni.Keys) {
            $matchesExtension = $false
            foreach ($extName in $sourceExtensions.Name) {
                $extKey = $extName -replace '\.(extension|lib)$', ''
                if ($section -like "$extKey*") { $matchesExtension = $true }
            }
            if (-not $matchesExtension) { continue }

            if (-not $targetIni.Contains($section)) { $targetIni[$section] = [ordered]@{} }
            foreach ($key in $sourceIni[$section].Keys) {
                $targetIni[$section][$key] = $sourceIni[$section][$key]
            }
            Write-Host "Secao de configuracao aplicada: [$section]" -ForegroundColor Green
            $changed = $true
        }

        if ($IncludeCoreSettings -and $sourceIni.Contains('core')) {
            # Apenas preferencias portateis; caminhos e ambiente ficam de fora.
            $portableKeys = @(
                'checkupdates', 'autoupdate', 'verbose', 'debug', 'filelogging',
                'startuplogtimeout', 'requiredhostbuild', 'minhostdrivefreespace',
                'loadbeta', 'cpython_engine_version', 'rocketmode', 'bincache',
                'usercanupdate', 'usercanextend', 'usercanconfig', 'colorize_docs',
                'tooltip_debug_info', 'routes_host', 'routes_port'
            )
            foreach ($key in $portableKeys) {
                if ($sourceIni['core'].Contains($key)) {
                    if (-not $targetIni.Contains('core')) { $targetIni['core'] = [ordered]@{} }
                    $targetIni['core'][$key] = $sourceIni['core'][$key]
                    $changed = $true
                }
            }
            Write-Host 'Preferencias gerais de [core] aplicadas.' -ForegroundColor Green
        }
    } else {
        Write-Verbose 'Pacote sem config/pyRevit_config.ini; apenas o caminho foi registrado.'
    }

    if ($changed -and $PSCmdlet.ShouldProcess($ConfigPath, 'Gravar configuracao')) {
        Write-PyRevitIni -Ini $targetIni -Path $ConfigPath
        Write-Host "Configuracao atualizada: $ConfigPath" -ForegroundColor Green
    }
}

# ------------------------------------------------------------------- final --
$cli = Get-Command pyrevit -ErrorAction SilentlyContinue
if ($cli -and $PSCmdlet.ShouldProcess('pyrevit clearcache', 'Limpar cache do pyRevit')) {
    try {
        & $cli.Path clearcache | Out-Null
        Write-Host 'Cache do pyRevit limpo.' -ForegroundColor Green
    } catch {
        Write-Warning "Nao foi possivel rodar 'pyrevit clearcache': $($_.Exception.Message)"
    }
} elseif (-not $cli) {
    Write-Host "CLI 'pyrevit' nao encontrada no PATH - o cache sera reconstruido no proximo Revit." -ForegroundColor Yellow
}

if ($tempExtract -and (Test-Path -LiteralPath $tempExtract)) {
    Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nConcluido. Extensoes instaladas: $($installed -join ', ')" -ForegroundColor Green
Write-Host 'Feche e abra o Revit (ou use Reload no painel pyRevit) para carregar a extensao.'
