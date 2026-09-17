<#
.SYNOPSIS
    Baixa as ferramentas de pacote do GitHub e instala a extensao nesta maquina.

.DESCRIPTION
    Pensado para a maquina de destino (ex.: W2), onde ainda nao existe nada
    baixado. Baixa o repositorio, localiza os scripts e:

      - com -PackagePath: instala o .zip gerado na maquina de origem;
      - com -ExportFrom: empacota a extensao a partir de um caminho acessivel
        (pasta de rede da outra maquina, pendrive, OneDrive) e ja instala;
      - sem nenhum dos dois: apenas deixa as ferramentas prontas e mostra os
        proximos passos.

.PARAMETER PackagePath
    Caminho do .zip gerado por Export-PyRevitPackage.ps1 na maquina de origem.

.PARAMETER ExportFrom
    Caminho da pasta <nome>.extension de origem, acessivel a partir desta
    maquina (ex.: \\W1\c$\Users\fulano\AppData\Roaming\pyRevit\Extensions\3fstudio.extension).

.PARAMETER SourceConfig
    Opcional, junto com -ExportFrom: pyRevit_config.ini da maquina de origem
    (ex.: \\W1\c$\Users\fulano\AppData\Roaming\pyRevit\pyRevit_config.ini).

.EXAMPLE
    .\Bootstrap.ps1 -PackagePath D:\3fstudio-pyrevit-package-20260917-1030.zip

.EXAMPLE
    .\Bootstrap.ps1 -ExportFrom \\W1\Compartilhado\3fstudio.extension
#>
[CmdletBinding()]
param(
    [string]$PackagePath,
    [string]$ExportFrom,
    [string]$SourceConfig,
    [string]$TargetPath = (Join-Path $env:APPDATA 'pyRevit\Extensions'),
    [string]$RepoZipUrl = 'https://github.com/adm3fstudio/pyrevit/archive/refs/heads/claude/ecstatic-fermat-uvcz9i.zip',
    [switch]$IncludeCoreSettings,
    [switch]$SkipConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# TLS 1.2 e obrigatorio para falar com o GitHub no Windows PowerShell 5.1.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Verbose 'Nao foi possivel ajustar o protocolo TLS; seguindo com o padrao.'
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('pyrevit-tools-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$zip = Join-Path $work 'repo.zip'

Write-Host "Baixando ferramentas de $RepoZipUrl" -ForegroundColor Cyan
Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zip -UseBasicParsing
Expand-Archive -LiteralPath $zip -DestinationPath $work -Force

$exportScript = Get-ChildItem -LiteralPath $work -Recurse -Filter 'Export-PyRevitPackage.ps1' -File |
    Select-Object -First 1
if (-not $exportScript) {
    throw "Nao encontrei Export-PyRevitPackage.ps1 dentro do download ($work)."
}
$toolsDir = $exportScript.Directory.FullName
$installScript = Join-Path $toolsDir 'Install-PyRevitPackage.ps1'
Write-Host "Ferramentas em: $toolsDir" -ForegroundColor Green

if ($ExportFrom) {
    if (-not (Test-Path -LiteralPath $ExportFrom)) {
        throw "Caminho de origem nao acessivel a partir desta maquina: $ExportFrom"
    }

    $exportArgs = @{
        SourcePath = @($ExportFrom)
        OutputPath = $work
    }
    if ($SourceConfig) { $exportArgs['ConfigPath'] = $SourceConfig }

    Write-Host "`nEmpacotando a partir de $ExportFrom" -ForegroundColor Cyan
    & $exportScript.FullName @exportArgs

    $generated = Get-ChildItem -LiteralPath $work -Filter '*.zip' -File |
        Where-Object { $_.Name -ne 'repo.zip' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $generated) { throw 'O empacotamento nao gerou nenhum .zip.' }
    $PackagePath = $generated.FullName
}

if (-not $PackagePath) {
    Write-Host ''
    Write-Host 'Ferramentas prontas, mas nenhum pacote foi indicado.' -ForegroundColor Yellow
    Write-Host 'Escolha um dos caminhos:'
    Write-Host "  1) Ja tenho o .zip da outra maquina:"
    Write-Host "     & '$installScript' -PackagePath 'C:\caminho\pacote.zip'"
    Write-Host '  2) Consigo enxergar a pasta da extensao pela rede/pendrive:'
    Write-Host "     & '$($exportScript.FullName)' -SourcePath '\\W1\...\3fstudio.extension' -OutputPath '$work'"
    Write-Host '  3) Nao tenho nada ainda: rode Empacotar.bat na maquina de origem primeiro.'
    return
}

Write-Host "`nInstalando pacote: $PackagePath" -ForegroundColor Cyan
$installArgs = @{
    PackagePath = $PackagePath
    TargetPath  = $TargetPath
}
if ($IncludeCoreSettings) { $installArgs['IncludeCoreSettings'] = $true }
if ($SkipConfig) { $installArgs['SkipConfig'] = $true }

& $installScript @installArgs

Write-Host "`nArquivos temporarios em: $work" -ForegroundColor DarkGray
Write-Host 'Pode apagar essa pasta depois de conferir que a extensao carregou.'
