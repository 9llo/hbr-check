*Leia em outros idiomas: [English](README.md), [Português](README.pt-BR.md).*

# ESXi & HBR Appliance Diagnostics

Um conjunto de ferramentas de diagnóstico em PowerShell abrangente para ambientes VMware. Este script interativo fornece recursos automatizados para se conectar aos servidores vCenter, inspecionar hosts ESXi em busca de erros de thumbprint na Replicação Baseada em Host (HBR), extrair dados de pareamento internos diretamente dos appliances HBR e comparar sistematicamente os bancos de dados entre os datacenters de replicação para apontar discrepâncias.

## Funcionalidades

Um menu de interface de usuário (UI) interativo (`Show-Menu`) encapsula três módulos de diagnóstico distintos:

### 1. Check hbr-agent thumbprint error (Verificar erro de thumbprint no hbr-agent)
- **Registro Automatizado:** Conecta-se a um vCenter alvo (ignorando com segurança os avisos sobre SSLs inválidos).
- **Seleção de Cluster:** Exibe uma janela interativa via `Out-GridView` para permitir que o usuário escolha um ou varíos clusters.
- **Automação SSH:** Interroga cada host ESXi nos clusters alvo, habilitando o `TSM-SSH` dinamicamente (se estiver desabilitado), estabelecendo um túnel SSH usando a senha root informada e analisando o log `/var/run/log/hbr-agent.log`.
- **Validação:** Assinala especificamente os hosts que contiverem strings com a mensagem de problema como em `Thumbprint and certificate is not allowed to send replication data`.
- **Relatórios:** Ao final, desativa de maneira segura as conexões SSH estabelecidas e gera localmente CSVs com marcações de data/hora isolando o status dos erros mapeados por nó.

### 2. Extract pairing info from replication appliance (Extrair propriedades do appliance de replicação)
- **Acesso Direto ao Appliance:** Efetua uma conexão SSH direta para investigar internamente os servidores de Replicação VMware (vSphere Replication Appliance).
- **Descoberta do Banco de Dados:** Executa automaticamente `/usr/bin/hbrsrv-bin --print-default-db` para encontrar de modo dinâmico a localização interna do diretório do DB primário que sofreu mount.
- **Extração SQL:** Instancia no command pipeline o seu sqlite interno local executando consultas formatadas (`select * from HostInfo`), resultando perfeitamente no empacotamento completo de sua tabela interna de hosts dentro de um CSV padronizado de relatórios na pasta `/HostInfo/`.

### 3. Compare hostInfo between appliance replications (Comparar o hostInfo entre pareamentos cruzados)
- **Análise Cruzada entre os Logs:** Pede a prévia seleção via Grid de um Banco de Dados "Origem" (.CSV gerado pela extração 2) e um "Alvo".
- **Mapeamento de IDs (UUID):** Exige um identificador associativo pelo arquivo de contexto local preenchido e formatado `pairings.csv` para destrinchar remotamente os equivalentes do seu respectivo datacenter pela lista cruzada.
- **Batimento Computacional de Array:** Automatiza sem necessitar intervenção em query externa um varrimento de discrepâncias através do comando `Compare-Object`, verificando nativamente registros unicamente locais (`sem o cabeçalho UUID` pelo regex de parser `:` na Origin) aos correspondentes virtuais (`Iniciando obrigatoriamente pela indexação do UUID selecionado`) cadastrados de modo equivalente em seu destino.  
- **Modos de Verificação Direcionais:** Entrega flexibilidade perguntando interativamente se a auditoria relacional deverá ocorrer em um método Bi-Direcional nativo (prospecção de buracos isolados operantes dos dois caminhos sem mapeamento pareado do lado correspondente) ou se somente irá isolar o modelo Unidirecional (Listar todos servidores locais válidos cadastrados no DB de origem que atritaram a sincronização e não se replicaram formalmente para sua base pareada isolada de Destino).
- **Alerta de Inconsistências:** Apresenta todas as discrepâncias do processo de modo explícito nas camadas Grid UI do Powershell a todo instante da auditoria final sem corromper CSVs externos salvos e registrados da execução na `/results/`. 

---

## Estrutura do Diretório

```text
esxi-hbr-check/
├── hbr-check.ps1     # Processador unificado e invólucro do menu base da aplicação
├── pairings.csv      # Mapeamentos pré-montados da arquitetura para a identificação do datacenter auxiliar pelo ID gerado internamente pelo Appliance
├── logs/             # Camada de rastreamentos textuais nativos para troubleshooting local em execuções transacionais em andamento isoladas no diretório ignoradas via commit
├── HostInfo/         # Alocação de armazenamentos SQL desempacotados provenientes da Opção de Extração (2)
├── results/          # Alocação dos CSVs sintéticos finalizados da exportação das discrepâncias auditadas via Opção 1 e Opção de pareamento divergente Opção 3
└── .gitignore        # Gestão rigorosa em exclusões programáticas não acidentais ao subir em push com informações confidenciais do vCenter dos clientes
```

## Pré-requisitos

- **PowerShell 5.1+** (Um ambiente Windows ativo nativo é inteiramente recomendado devido as exigências visuais gráficas geradas obrigatoriamente pela pipeline ao depender da janela nativa do painel `Out-GridView` entre processamentos do terminal).
- Possuir uma conta central válida autenticada portadora da permissão e privilégios totais na infraestrutura como **Administrador nos vCenter(s)** listados aos alvos em execução.
- Credenciais originais ou chave unificadas na instância `root` para operar livre dos limites restritos dentro de qualquer **Hypervisor local base associado ativamente** (Necessário p/ os saltos da Opção 1) via túneis SSH formatados entre as checagens com grep interno pelo script nas validações exclusivas do serviço SSH.
- Credenciais exclusivas em nível admin associadas ao banco de administração dentro **Appliance Primário alvo da Replication**. (Exclusivo da camada Option 2) logada nas pesquisas do shell de varreduras via SQLite.  
- Tabela nativa `pairings.csv` populada prévia preenchida exatamente nos termos indicativos cruzando nomes padronizados identificáveis pelo comando contendo cabeçalhos explícitos  estruturados como: `name,pairing_id`.

Seu processamento foi modelado estritamente usando empacotamentos sob `VMware.PowerCLI` somada aos pacotes interativos em nuvem `Posh-SSH`. A inicialização central do loop validará agressivamente as chaves isoladas localmente em cache injetando download com as diretivas seguras em `CurrentUser` pelo portal PSGallery público se os requisitos pré-cadastros indicarem falha local. 

---

## Como Começar a Usar

### 1. Clonar este Projeto do Repositório 

```bash
git clone https://github.com/9llo/hbr-check.git
cd hbr-check
```

### 2. Preencher a Matriz do Pairing (Unicamente se a execução de Comparativos - Output Menu (Opção 3) for testada internamente sob execuções válidas reais).

Crie e garanta que o dicionário de variáveis diretas do `pairings.csv` se consolide adequadamente no host alocado para o terminal operando o seu PS.

```csv
name,pairing_id
Meu-DR-Remoto-SP,7f73033e-4578-45e6-9274-582b421c5413
Meu-DR-Remoto-RJ,bb1641ce-741f-4348-b8cc-ce960c0bb8ca
```

### 3. Ações e Comandos In-Line Básicos:

Você pode carregar as invocações interativas em tela ou preencher em CLI com as flags automatizadas caso a Opção 1 demande repetição manual direta isolada das lógicas parciais visuais iniciais programadas.  

Modo GUI de interface clássica orientador padrão de opções modulares (O Menu será invocado como o portal hub listando sequencialmente [1] / [2] / [3]):  

```powershell
.\hbr-check.ps1
```

Ocultado as rotas dialógicas base para injeção via parâmetros do painel central se a tarefa final desejar validações da rota no sub-módulo interno isolado pela infra (Lógica O1 conectoma direta vCenter primária sem falhas visíveis do servidor com a certificação omitida intencionalmente na autoridade bypass interno Set-PowerCLIConfiguration Session False). 

```powershell
.\hbr-check.ps1 -Server "vcenter.lablocal" -Username "Meu-Admin-No-Site@vsphere.local" -Password "Minha-Senha-Secreta"
```
