# Handoff — continuar na máquina local (W2)

Contexto para uma sessão do Claude Code aberta **na própria W2**, continuando o
trabalho iniciado numa sessão na nuvem.

## Objetivo

Levar a extensão pyRevit **3fstudio** (arquivos + configurações) da máquina W1
para a W2.

## O que já existe neste repositório

Branch: `claude/ecstatic-fermat-uvcz9i` — PR #1.

Tudo vive em `tools/pyrevit-package/`:

| Arquivo | Papel |
|---|---|
| `Export-PyRevitPackage.ps1` | Empacota a extensão + `pyRevit_config.ini` num `.zip` |
| `Install-PyRevitPackage.ps1` | Instala o `.zip` e mescla as configurações |
| `Bootstrap.ps1` | Baixa as ferramentas do GitHub e chama export/install |
| `lib/PyRevitIni.psm1` | Leitura/escrita/merge do ini do pyRevit |
| `Empacotar.bat` / `Instalar.bat` | Atalhos de duplo clique |
| `Diagnostico.ps1` | Relatório read-only do estado do pyRevit na máquina |
| `README.md` | Documentação das duas pontas do fluxo |

Comportamento já garantido: exclui `__pycache__`/`.git`/`*.pyc`; registra o
diretório em `[core] userextensions` **sem apagar** os caminhos existentes;
mescla só as seções da própria extensão (ex.: `[3fstudio.extension]`); faz
backup da extensão anterior e do `.ini` antes de escrever; suporta `-WhatIf`;
esvazia credenciais (`password`, `token`, `secret`) na cópia que vai no pacote e
nunca sobrescreve as que já existem na máquina de destino.

## O que foi testado (e o que não foi)

Testado ponta a ponta com PowerShell 7.4 em Linux: export → zip → install →
reinstalação, merge de config preservando caminhos e seções de terceiros, e o
fluxo do `Bootstrap.ps1` baixando do GitHub.

**Não testado em Windows real:** o caminho do `robocopy` (no Linux rodou o
fallback `Copy-Item`), os `.bat`, a chamada da CLI `pyrevit clearcache` e a
descoberta automática da extensão em `%APPDATA%\pyRevit\Extensions`. É
exatamente o que uma sessão local na W2 consegue validar.

## Estado atual

A W2 ainda não tem a extensão instalada. Falta saber se a `3fstudio.extension`
existe na W1 e como a W2 a alcança (`.zip` já gerado, pasta de rede, pendrive).

## Próximos passos na W2

1. Conferir o que já existe na máquina:

   ```powershell
   .\tools\pyrevit-package\Diagnostico.ps1
   ```

2. Instalar, conforme o caso:

   ```powershell
   # já tenho o .zip da W1
   .\tools\pyrevit-package\Install-PyRevitPackage.ps1 -PackagePath 'D:\pacote.zip'

   # a W2 enxerga a pasta da W1 pela rede/pendrive
   .\tools\pyrevit-package\Bootstrap.ps1 -ExportFrom '\\W1\...\3fstudio.extension'
   ```

   Rode antes com `-WhatIf` para ver o plano sem alterar nada.

3. Abrir o Revit e confirmar que a aba aparece; se não, `pyrevit clearcache` e
   conferir **pyRevit → Settings → Custom Extension Directories**.

4. Corrigir na branch o que o Windows real revelar (robocopy, `.bat`,
   descoberta automática) e empurrar para a PR #1.
