<#
.SYNOPSIS
    Funcoes compartilhadas para ler/escrever o pyRevit_config.ini e localizar
    pastas de extensoes do pyRevit.
.NOTES
    Compativel com Windows PowerShell 5.1 (padrao do Windows 10/11).
    O arquivo de configuracao do pyRevit e gerado pelo configparser do Python,
    entao a leitura preserva secoes, chaves e comentarios na ordem original.
#>

Set-StrictMode -Version Latest

function Get-PyRevitConfigPath {
    <#
    .SYNOPSIS
        Caminho padrao do pyRevit_config.ini do usuario atual.
    #>
    [CmdletBinding()]
    param()

    Join-Path $env:APPDATA 'pyRevit\pyRevit_config.ini'
}

function Read-PyRevitIni {
    <#
    .SYNOPSIS
        Le um .ini e devolve um dicionario ordenado: secao -> (chave -> valor).
    .DESCRIPTION
        Linhas em branco e comentarios sao descartados; os valores mantem o
        texto bruto (ex.: listas no formato JSON usadas pelo pyRevit).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $ini = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $ini }

    $section = '__global__'
    $ini[$section] = [ordered]@{}

    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) { continue }

        if ($trimmed -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            if (-not $ini.Contains($section)) { $ini[$section] = [ordered]@{} }
            continue
        }

        $idx = $trimmed.IndexOf('=')
        if ($idx -lt 1) { continue }

        $key = $trimmed.Substring(0, $idx).Trim()
        $value = $trimmed.Substring($idx + 1).Trim()
        $ini[$section][$key] = $value
    }

    if ($ini['__global__'].Count -eq 0) { $ini.Remove('__global__') }
    return $ini
}

function Write-PyRevitIni {
    <#
    .SYNOPSIS
        Grava o dicionario devolvido por Read-PyRevitIni de volta em disco.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Ini,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $sb = New-Object System.Text.StringBuilder
    foreach ($section in $Ini.Keys) {
        if ($section -eq '__global__') { continue }
        [void]$sb.AppendLine("[$section]")
        foreach ($key in $Ini[$section].Keys) {
            [void]$sb.AppendLine("$key = $($Ini[$section][$key])")
        }
        [void]$sb.AppendLine()
    }

    # UTF-8 sem BOM: o configparser do Python nao lida bem com BOM.
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), $encoding)
}

function ConvertFrom-PyRevitList {
    <#
    .SYNOPSIS
        Converte o valor JSON usado pelo pyRevit (ex.: userextensions) em array.
    #>
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }

    try {
        $parsed = $Value | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Verbose "Valor nao e JSON valido, ignorando: $Value"
        return @()
    }

    if ($null -eq $parsed) { return @() }
    return @($parsed | Where-Object { $_ -is [string] -and $_.Trim() -ne '' })
}

function ConvertTo-PyRevitList {
    <#
    .SYNOPSIS
        Converte um array de caminhos no formato JSON esperado pelo pyRevit.
    #>
    [CmdletBinding()]
    param([string[]]$Items)

    if (-not $Items -or $Items.Count -eq 0) { return '[]' }

    $escaped = foreach ($item in $Items) {
        '"' + ($item -replace '\\', '\\' -replace '"', '\"') + '"'
    }
    '[' + ($escaped -join ', ') + ']'
}

function Add-PyRevitExtensionPath {
    <#
    .SYNOPSIS
        Garante que um diretorio esteja registrado em [core] userextensions.
    .OUTPUTS
        $true se o ini foi alterado, $false se o caminho ja existia.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Ini,
        [Parameter(Mandatory)] [string]$ExtensionDir
    )

    if (-not $Ini.Contains('core')) { $Ini['core'] = [ordered]@{} }

    $current = @()
    if ($Ini['core'].Contains('userextensions')) {
        $current = @(ConvertFrom-PyRevitList $Ini['core']['userextensions'])
    }

    $normalized = $ExtensionDir.TrimEnd('\')
    foreach ($existing in $current) {
        if ($existing.TrimEnd('\') -ieq $normalized) { return $false }
    }

    $current += $normalized
    $Ini['core']['userextensions'] = ConvertTo-PyRevitList $current
    return $true
}

function Get-PyRevitExtensionSearchPath {
    <#
    .SYNOPSIS
        Lista os diretorios onde extensoes do pyRevit costumam estar instaladas.
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Get-PyRevitConfigPath)
    )

    $paths = New-Object System.Collections.Generic.List[string]

    $ini = Read-PyRevitIni -Path $ConfigPath
    if ($ini.Contains('core') -and $ini['core'].Contains('userextensions')) {
        foreach ($p in (ConvertFrom-PyRevitList $ini['core']['userextensions'])) {
            $paths.Add($p)
        }
    }

    # Clones do pyRevit trazem extensoes embutidas em <clone>\extensions
    if ($ini.Contains('environment') -and $ini['environment'].Contains('clones')) {
        try {
            $clones = $ini['environment']['clones'] | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $clones.PSObject.Properties) {
                $paths.Add((Join-Path $prop.Value 'extensions'))
            }
        } catch {
            Write-Verbose 'Nao foi possivel interpretar [environment] clones.'
        }
    }

    $paths.Add((Join-Path $env:APPDATA 'pyRevit\Extensions'))
    $paths.Add((Join-Path $env:APPDATA 'pyRevit-Master\extensions'))
    if ($env:ProgramData) {
        $paths.Add((Join-Path $env:ProgramData 'pyRevit\Extensions'))
        $paths.Add((Join-Path $env:ProgramData 'pyRevit-Master\extensions'))
    }

    $seen = @{}
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $key = $p.TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if (Test-Path -LiteralPath $p) { $p.TrimEnd('\') }
    }
}

function Copy-ExtensionTree {
    <#
    .SYNOPSIS
        Copia uma pasta de extensao ignorando lixo de build e metadados de git.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        $roboArgs = @(
            $Source, $Destination, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1',
            '/XD', '__pycache__', '.git', '.vs', '.idea',
            '/XF', '*.pyc', '*.pyo', '*.log'
        )
        & $robocopy.Path @roboArgs | Out-Null
        # Robocopy: 0-7 sao codigos de sucesso.
        if ($LASTEXITCODE -ge 8) {
            throw "Falha do robocopy (codigo $LASTEXITCODE) ao copiar '$Source'."
        }
        return
    }

    Write-Verbose 'robocopy nao encontrado, usando Copy-Item.'
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    Get-ChildItem -LiteralPath $Destination -Recurse -Force -Include '__pycache__', '.git' -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $Destination -Recurse -Force -Include '*.pyc', '*.pyo' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function @(
    'Get-PyRevitConfigPath',
    'Read-PyRevitIni',
    'Write-PyRevitIni',
    'ConvertFrom-PyRevitList',
    'ConvertTo-PyRevitList',
    'Add-PyRevitExtensionPath',
    'Get-PyRevitExtensionSearchPath',
    'Copy-ExtensionTree'
)
