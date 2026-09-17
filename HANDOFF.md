# Handoff — continuar numa sessão local (W1 ou W2)

Contexto para uma sessão do Claude Code rodando **na máquina Windows do
usuário**, continuando o trabalho iniciado numa sessão na nuvem (que não tem
acesso a disco Windows, Revit, PowerShell nem ao pyRevit instalado).

## Objetivo

Levar a extensão pyRevit **3fstudio** (arquivos + configurações) da máquina
**W1** (origem, tem a extensão) para a **W2** (destino).

## Papéis das máquinas

| Máquina | Papel | O que roda |
|---|---|---|
| W1 | origem | `Diagnostico.ps1` → `Empacotar.bat` (gera o `.zip`) |
| W2 | destino | `Diagnostico.ps1` → `Instalar.bat` (consome o `.zip`) |

O `.zip` do pacote viaja entre as duas por pendrive, rede ou OneDrive. Se a W2
enxergar a pasta da W1 pela rede, dá para pular a etapa manual com
`Bootstrap.ps1 -ExportFrom <caminho>`, que empacota e instala de uma vez.

## O que já existe neste repositório

Branch: `claude/ecstatic-fermat-uvcz9i` — PR #1. Tudo em `tools/pyrevit-package/`:

| Arquivo | Papel |
|---|---|
| `Diagnostico.ps1` | Relatório read-only; diz se a máquina é origem ou destino |
| `Export-PyRevitPackage.ps1` | Empacota a extensão + `pyRevit_config.ini` num `.zip` |
| `Install-PyRevitPackage.ps1` | Instala o `.zip` e mescla as configurações |
| `Bootstrap.ps1` | Baixa as ferramentas do GitHub e chama export/install |
| `lib/PyRevitIni.psm1` | Leitura/escrita/merge do ini do pyRevit |
| `Empacotar.bat` / `Instalar.bat` / `Diagnostico.bat` | Atalhos de duplo clique |
| `README.md` | Documentação das duas pontas do fluxo |

Comportamento já garantido: exclui `__pycache__`/`.git`/`*.pyc`; registra o
diretório em `[core] userextensions` **sem apagar** os caminhos existentes;
mescla só as seções da própria extensão (ex.: `[3fstudio.extension]`); faz
backup da extensão anterior e do `.ini` antes de escrever; suporta `-WhatIf`;
esvazia credenciais (`password`, `token`, `secret`) na cópia que vai no pacote e
nunca sobrescreve as que já existem na máquina de destino.

## O que foi testado (e o que não foi)

Testado ponta a ponta com PowerShell 7.4 **em Linux**: export → zip → install →
reinstalação, merge de config preservando caminhos e seções de terceiros,
redação de credenciais nos dois sentidos, e o `Bootstrap.ps1` baixando do
GitHub.

**Nunca rodou em Windows real.** Ainda não foram exercitados:

- o ramo do `robocopy` em `Copy-ExtensionTree` (no Linux rodou o fallback
  `Copy-Item`) — atenção a caminhos com espaço, acento, UNC (`\\servidor\...`)
  e acima de 260 caracteres;
- os wrappers `.bat` (política de execução, `%~dp0` com espaço no caminho);
- a chamada `pyrevit clearcache` e a leitura de `pyrevit --version`;
- a descoberta automática em `%APPDATA%\pyRevit\Extensions` e a leitura de
  clones em `[environment]`;
- a consulta ao registro do Revit no `Diagnostico.ps1`.

É exatamente o que uma sessão local consegue validar.

## Próximos passos

Na W1 (origem):

1. `.\tools\pyrevit-package\Diagnostico.ps1` — confirmar que acha a
   `3fstudio.extension` e ver onde ela mora.
2. `.\tools\pyrevit-package\Export-PyRevitPackage.ps1 -WhatIf` e depois sem
   `-WhatIf` — conferir o conteúdo do `.zip` gerado (sem `__pycache__`, sem
   `.pyc`, com `config/pyRevit_config.ini` e `manifest.json`).
3. Levar o `.zip` para a W2.

Na W2 (destino):

4. `.\tools\pyrevit-package\Diagnostico.ps1` — registrar o estado ANTES.
5. `Install-PyRevitPackage.ps1 -PackagePath <zip> -WhatIf`, depois de verdade.
6. Abrir o Revit e confirmar a aba; se não aparecer, `pyrevit clearcache` e
   conferir **pyRevit → Settings → Custom Extension Directories**.

Em qualquer máquina: corrigir na branch o que o Windows real revelar e empurrar
para a PR #1, anotando aqui o que passou a estar verificado.
