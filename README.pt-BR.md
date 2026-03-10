*Leia em outros idiomas: [English](README.md), [Português](README.pt-BR.md).*

# ESXi HBR Check

Um script em PowerShell criado para conectar iterativamente a um servidor VMware vCenter, pesquisar clusters selecionados pelo usuário via `Out-GridView` e analisar logs dos hosts ESXi para identificar erros de thumbprint na Replicação Baseada em Host (HBR) via SSH. Os resultados são exportados de forma organizada para um arquivo CSV e apresentados em uma grid gráfica.

## Principais Funcionalidades

- **Verificação Automatizada de Dependências**: Verifica e instala silenciosamente os módulos necessários `VMware.PowerCLI` e `Posh-SSH`.
- **Seleção Interativa de Clusters**: Apresenta um `Out-GridView` interativo para permitir que os usuários escolham rapidamente um ou vários clusters alvo do vCenter.
- **Automação SSH**: Estabelece e encerra dinamicamente interfaces SSH para cada Host ESXi alvo após ignorar verificações estritas usando a senha root do ESXi.
- **Agregação de Logs**: Lê `/var/run/log/hbr-agent.log`, busca por `Thumbprint and certificate is not allowed to send replication data`, limpa espaços no output e consolida as ocorrências.
- **Exportação e Auditoria**:
  - `logs/..`: Salva uma transcrição contínua da execução localmente em arquivos de log com data e hora.
  - `results/..`: Salva e exporta para CSV o mapeamento dos resultados e erros contendo propriedades exatas para relatórios externos.

---

## Pré-requisitos

- **PowerShell 5.1+** (Ambiente Windows recomendado, dada a dependência do `Out-GridView` e disponibilidade padrão da PSGallery).
- **Credenciais**: Autenticação com nível de administrador para o `vCenter` alvo e a senha `root` unificada aplicada aos respectivos Hosts ESXi em seus clusters.

---

## Como Começar

### 1. Clonar o Repositório

```bash
git clone https://github.com/9llo/hbr-check.git
cd hbr-check
```

### 2. Execução

Você pode executar o script via PowerShell diretamente e ele solicitará interativamente os argumentos ausentes (`Server`, `Username`, `Password`, ESXi `Root Password`):

```powershell
.\hbr-check.ps1
```

Caso queira passar os parâmetros implicitamente para evitar os prompts de diálogo iniciais:

```powershell
.\hbr-check.ps1 -Server "vcenter.local" -Username "administrator@vsphere.local" -Password "SuaSenhaSecreta"
```

*Nota: O script estabelece substituições de segurança dinamicamente para ignorar certificados SSL inválidos do vCenter internamente usando `Set-PowerCLIConfiguration`.*

### 3. Revisar os Resultados

A execução é concluída com um resumo geral consolidando os hosts validados (`Processed Hosts`, `Total Errors`).

Após a conclusão, os resultados são mapeados para árvores de diretórios isoladas:
- Arquivos detalhados `.log` serão gerados automaticamente em `.\logs\`.
- As listas analisadas de combinações de cluster e erros contendo booleanos serão salvas explicitamente em `.\results\` como `.csv`.

---

## Estrutura do Diretório

```text
esxi-hbr-check/
├── hbr-check.ps1     # Script de execução principal
├── logs/             # Arquivos de transcrição ignorados no Git (Gerados dinamicamente)
├── results/          # CSVs de exportação ignorados no Git (Gerados dinamicamente)
└── .gitignore        # Filtragem de exclusão explícita
```
