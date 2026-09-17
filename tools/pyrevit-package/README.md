# Pacote de extensão pyRevit (3fstudio)

Ferramentas para levar a extensão **3fstudio** e as configurações do pyRevit de
uma máquina para outra: um script empacota tudo num `.zip`, outro instala.

## Antes de tudo: diagnóstico

Rode em **qualquer uma das duas máquinas** para saber onde você está (nada é
alterado — é só leitura):

```powershell
.\Diagnostico.ps1     # ou duplo clique em Diagnostico.bat
```

Ele lista a versão do pyRevit, o `pyRevit_config.ini`, todas as pastas de
extensão registradas com o que há dentro, as versões do Revit instaladas, e diz
se aquela máquina é a **origem** (tem a `3fstudio.extension`) ou o **destino**.

## Na máquina de origem (onde a extensão já funciona)

1. Copie a pasta `tools/pyrevit-package` para a máquina.
2. Dê duplo clique em **`Empacotar.bat`** (ou rode no PowerShell):

   ```powershell
   .\Export-PyRevitPackage.ps1
   ```

3. É gerado `3fstudio-pyrevit-package-<data>.zip` contendo:

   ```
   extensions/3fstudio.extension/   # a extensão, sem __pycache__/.git/*.pyc
   config/pyRevit_config.ini        # cópia da configuração de origem
   manifest.json                    # o que foi empacotado, quando e onde
   tools/                           # o instalador viaja junto
   Instalar.bat
   ```

Se a extensão não for encontrada automaticamente, aponte a pasta:

```powershell
.\Export-PyRevitPackage.ps1 -SourcePath "C:\Caminho\3fstudio.extension"
```

Outras opções: `-Name` (outra extensão), `-OutputPath`, `-SkipConfig`
(só arquivos), `-NoZip` (deixa como pasta).

## Atalho na máquina de destino (sem baixar nada antes)

Abra o **PowerShell** e cole o bloco abaixo — ele baixa o `Bootstrap.ps1` deste
repositório, que por sua vez busca as ferramentas e instala:

```powershell
$b = "$env:TEMP\Bootstrap.ps1"
irm 'https://raw.githubusercontent.com/adm3fstudio/pyrevit/claude/ecstatic-fermat-uvcz9i/tools/pyrevit-package/Bootstrap.ps1' -OutFile $b

# 1) já tenho o .zip gerado na outra máquina
& $b -PackagePath 'D:\3fstudio-pyrevit-package-20260917-1030.zip'

# 2) enxergo a pasta da extensão pela rede / pendrive / OneDrive
& $b -ExportFrom '\\W1\Compartilhado\3fstudio.extension' -SourceConfig '\\W1\Compartilhado\pyRevit_config.ini'

# 3) só quero as ferramentas prontas e ver as opções
& $b
```

No modo 2 ele empacota a partir do caminho informado e instala em seguida — não
é preciso mexer na máquina de origem, basta enxergar a pasta dela.

Se aparecer erro de política de execução, rode antes:
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

## Na máquina de destino

1. Instale o pyRevit normalmente (https://pyrevitlabs.io) e feche o Revit.
2. Extraia o `.zip` **por completo**.
3. Dê duplo clique em **`Instalar.bat`**, ou:

   ```powershell
   .\tools\Install-PyRevitPackage.ps1 -PackagePath "C:\Temp\3fstudio-pyrevit-package-20260917-1030.zip"
   ```

O instalador:

- copia as extensões para `%APPDATA%\pyRevit\Extensions`;
- registra essa pasta em `[core] userextensions` do `pyRevit_config.ini`
  **sem apagar** os caminhos que já existiam;
- aplica as seções de configuração da própria extensão (ex.: `[3fstudio.extension]`);
- roda `pyrevit clearcache` se a CLI estiver no PATH.

Nada é sobrescrito sem rede de segurança: uma extensão já instalada vira
`<nome>.extension.bak-<data>` e o `pyRevit_config.ini` ganha um `.bak-<data>`
antes de ser alterado.

Opções úteis:

| Opção | Efeito |
|---|---|
| `-TargetPath <pasta>` | Instala em outra pasta (ex.: uma pasta de rede compartilhada) |
| `-IncludeCoreSettings` | Também copia preferências gerais de `[core]` (rocketmode, bincache, loadbeta…) |
| `-SkipConfig` | Só copia arquivos, não mexe no `.ini` |
| `-Force` | Substitui a versão anterior sem criar backup |
| `-WhatIf` | Mostra o que faria, sem alterar nada |

4. Abra o Revit. A aba da extensão deve aparecer; se não, use
   **pyRevit → Reload** ou confira em **pyRevit → Settings → Custom Extension Directories**.

## Credenciais

O `pyRevit_config.ini` guarda usuário e senha de repositórios privados de
extensão. O empacotador **esvazia** os valores de chaves como `password`,
`token` e `secret` antes de gravar a cópia no pacote, e avisa quais foram
removidas — o `.zip` pode circular por pendrive ou e-mail sem levar segredo
junto.

Na instalação, a regra é a mesma em espelho: uma credencial já existente na
máquina de destino **nunca** é sobrescrita pelo valor vazio do pacote, e se não
houver nenhuma o instalador avisa qual preencher.

## O que *não* é copiado

Dados de ambiente da máquina de origem — seções `[environment]` (clones e
attachments do pyRevit), caminhos de stylesheet e a instalação do pyRevit em si.
Isso é específico de cada máquina e o pyRevit regenera no destino.

## Solução de problemas

- **"execução de scripts desabilitada"**: use os `.bat`, que já passam
  `-ExecutionPolicy Bypass`, ou rode
  `powershell -ExecutionPolicy Bypass -File .\Install-PyRevitPackage.ps1`.
- **Extensão não aparece no Revit**: confirme que a pasta terminada em
  `.extension` está diretamente dentro do diretório registrado, feche todas as
  instâncias do Revit e rode `pyrevit clearcache`.
- **Pacote muito grande**: verifique se há `.git` ou arquivos de modelo dentro
  da extensão — o empacotador já ignora `__pycache__`, `.git`, `*.pyc` e `*.log`.
