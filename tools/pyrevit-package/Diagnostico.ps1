<#
.SYNOPSIS
    Relatorio do estado do pyRevit nesta maquina. Nao altera nada.

.DESCRIPTION
    Mostra versao do pyRevit, onde esta o pyRevit_config.ini, quais pastas de
    extensao estao registradas, quais extensoes existem em cada uma e quais
    versoes do Revit estao instaladas. Util antes de empacotar (na maquina de
    origem) e antes de instalar (na de destino).

.PARAMETER Name
    Destaca no relatorio as extensoes cujo nome contenha este texto.
    Padrao: 3fstudio.

.EXAMPLE
    .\Diagnostico.ps1
#>
[CmdletBinding()]
param(
    [string]$Name = '3fstudio',
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'PyRevitIni.psm1') -Force

function Write-Titulo {
    param([string]$Texto)
    Write-Host ''
    Write-Host "== $Texto " -ForegroundColor Cyan -NoNewline
    Write-Host ('=' * [Math]::Max(0, 60 - $Texto.Length)) -ForegroundColor DarkCyan
}

$emWindows = $env:OS -eq 'Windows_NT'

Write-Titulo 'Maquina'
Write-Host "  Nome......... $($env:COMPUTERNAME)"
Write-Host "  PowerShell... $($PSVersionTable.PSVersion)"
Write-Host "  Sistema...... $([System.Environment]::OSVersion.VersionString)"

Write-Titulo 'pyRevit CLI'
$cli = Get-Command pyrevit -ErrorAction SilentlyContinue
if ($cli) {
    Write-Host "  Executavel... $($cli.Source)"
    try {
        $ver = & $cli.Source --version 2>$null | Select-Object -First 1
        Write-Host "  Versao....... $ver"
    } catch {
        Write-Warning "  Nao foi possivel ler a versao: $($_.Exception.Message)"
    }
} else {
    Write-Host '  Nao encontrada no PATH (normal se o pyRevit foi instalado so para o Revit).' -ForegroundColor Yellow
}

Write-Titulo 'Configuracao'
if (-not $ConfigPath) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        Write-Warning '  APPDATA nao definido; use -ConfigPath para indicar o arquivo.'
        $ConfigPath = ''
    } else {
        $ConfigPath = Get-PyRevitConfigPath
    }
}

$ini = [ordered]@{}
if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
    $item = Get-Item -LiteralPath $ConfigPath
    Write-Host "  Arquivo...... $ConfigPath"
    Write-Host "  Alterado em.. $($item.LastWriteTime)"
    $ini = Read-PyRevitIni -Path $ConfigPath
    Write-Host "  Secoes....... $($ini.Keys -join ', ')"
    if ($ini.Contains('core')) {
        foreach ($k in @('rocketmode', 'bincache', 'loadbeta', 'checkupdates')) {
            if ($ini['core'].Contains($k)) { Write-Host "  $k......... $($ini['core'][$k])" }
        }
    }
} else {
    Write-Host "  Nenhum pyRevit_config.ini em '$ConfigPath'." -ForegroundColor Yellow
    Write-Host '  Isso normalmente significa que o pyRevit ainda nao rodou nesta maquina.'
}

Write-Titulo 'Pastas de extensao'
$roots = @()
if ($ConfigPath) { $roots = @(Get-PyRevitExtensionSearchPath -ConfigPath $ConfigPath) }
if ($roots.Count -eq 0) {
    Write-Host '  Nenhuma pasta de extensao encontrada.' -ForegroundColor Yellow
} else {
    $encontrouAlvo = $false
    foreach ($root in $roots) {
        Write-Host "  $root" -ForegroundColor White
        $exts = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(extension|lib)$' })
        if ($exts.Count -eq 0) {
            Write-Host '     (vazia)' -ForegroundColor DarkGray
            continue
        }
        foreach ($ext in $exts) {
            $files = @(Get-ChildItem -LiteralPath $ext.FullName -Recurse -File -ErrorAction SilentlyContinue)
            $mb = 0
            if ($files.Count -gt 0) {
                $mb = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
            }
            $alvo = $ext.Name -like "*$Name*"
            if ($alvo) { $encontrouAlvo = $true }
            $cor = if ($alvo) { 'Green' } else { 'Gray' }
            $marca = if ($alvo) { '>' } else { ' ' }
            Write-Host ("   {0} {1}  ({2} arquivos, {3} MB)" -f $marca, $ext.Name, $files.Count, $mb) -ForegroundColor $cor
        }
    }

    Write-Host ''
    if ($encontrouAlvo) {
        Write-Host "  Extensao '$Name' presente: esta maquina pode ser a ORIGEM do pacote." -ForegroundColor Green
        Write-Host '  Proximo passo:  .\Empacotar.bat'
    } else {
        Write-Host "  Extensao '$Name' nao encontrada: esta maquina e o DESTINO." -ForegroundColor Yellow
        Write-Host '  Proximo passo:  .\Instalar.bat  (ou Bootstrap.ps1 -PackagePath <zip>)'
    }
}

Write-Titulo 'Revit instalado'
if (-not $emWindows) {
    Write-Host '  Consulta ao registro do Windows indisponivel neste sistema.' -ForegroundColor DarkGray
} else {
    $achou = $false
    foreach ($hive in @('HKLM:\SOFTWARE\Autodesk\Revit', 'HKCU:\SOFTWARE\Autodesk\Revit')) {
        try {
            $chaves = Get-ChildItem -Path $hive -ErrorAction Stop
        } catch {
            continue
        }
        foreach ($chave in $chaves) {
            Write-Host "  $($chave.PSChildName)"
            $achou = $true
        }
    }
    if (-not $achou) { Write-Host '  Nenhuma instalacao do Revit encontrada no registro.' -ForegroundColor Yellow }
}

Write-Host ''
Write-Host 'Relatorio somente leitura: nada foi alterado.' -ForegroundColor DarkGray
