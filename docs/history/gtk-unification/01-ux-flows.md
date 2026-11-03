# 01 — Fluxos de UX

## Mapa da aplicação (uma janela)

```text
Big-Mount
├── Lateral (sempre visível em telas largas)
│   ├── Início
│   ├── Discos: um por disco, com ícone de alerta quando há
│   └── Cópias e buscas (com o número das que estão rodando)
└── Conteúdo (Adw.NavigationView)
    ├── Início: “Seus discos e dispositivos”, alerta com “Resgatar meus arquivos”,
    │           trabalhos em andamento, um cartão por disco
    ├── Disco (Adw.ViewStack)
    │   ├── Visão geral: volumes, montar somente leitura, abrir, desmontar, desbloquear
    │   ├── Recuperar: o que dá para fazer e “Começar a recuperar arquivos”
    │   ├── Saúde: veredito com evidência, achados, o que fazer, SMART, detalhes,
    │   │          “Manutenção avançada → Apagar dados permanentemente”
    │   ├── Histórico: cópias e buscas deste disco
    │   └── Mais opções (⋮): detalhes técnicos, exportar diagnóstico,
    │                         bloquear gravação, remover com segurança, manutenção
    ├── Assistente de recuperação (5 etapas)
    ├── Trabalho (progresso de uma cópia, lista, busca ou imagem)
    ├── Resultados (lista virtual com filtros)
    ├── Partições perdidas (TestDisk, só leitura)
    └── Manutenção avançada (Secure Erase)
```

Uma operação, um fluxo: “Recuperar arquivos” no cartão, no disco, na saúde e no
alerta abrem o mesmo assistente; “Verificar disco” e `--gui-drive-check` abrem a
mesma página de saúde.

## Três pessoas, a mesma tarefa: copiar os arquivos de um disco com defeito

**Criança de 10 anos.** Abre o Big-Mount. Vê um aviso vermelho: “ST1000… relatou
problemas sérios. Copie seus arquivos para outro disco antes de tentar qualquer
reparo” e o botão azul **Resgatar meus arquivos**. Clica. Etapa 1 já vem com o
volume certo marcado → **Próximo**. Etapa 2: “Todos os tipos” já marcado →
**Próximo**. Etapa 3: “Copiar arquivos diretamente — Recomendado” já marcado; um
aviso amarelo diz que nada começa sem ela → **Próximo**. O volume é montado
somente leitura (o diálogo já vem com a proteção marcada). Etapa 4: o disco de
backup já vem escolhido; “Dá para salvar aqui: 1,2 TB livres” → **Próximo**.
Etapa 5: origem → destino, “Nada é gravado na origem” → **Começar**. Fecha a
janela: o aviso diz que o trabalho continua.

**Pessoa idosa.** O mesmo caminho, com textos que dizem o que vai acontecer, sem
siglas na primeira camada, botões grandes e nenhuma ação que dependa de passar o
mouse por cima. Com fontes a 200% os botões quebram de linha em vez de alargar a
janela.

**Especialista.** Vai direto ao disco, lê o SMART com origem e horário, abre
“Mensagens do registro do sistema” e “Detalhes técnicos”, escolhe a análise
profunda (imagem ddrescue primeiro, busca depois), ajusta conflito, verificação,
tempo para deixar de lado e limite de velocidade em “Mais opções” da etapa 5, e
confere o comando equivalente no terminal (`bigmount --drive …`).

## O assistente

| Etapa | Mostra | Pode bloquear |
| --- | --- | --- |
| 1 De onde | discos com volumes, “O disco inteiro”, “Uma imagem de disco salva antes” | disco desconectado ou trocado: volta para cá e avisa |
| 2 O quê | Todos, Fotos, Vídeos, Documentos, Áudio, Arquivos compactados; o que cada tipo não acha | — |
| 3 Como | o recomendado pelo motor primeiro, com o porquê; os indisponíveis com o motivo; “Avançado” com imagem e partições | método indisponível |
| 4 Para onde | lugares em outro disco; os inválidos aparecem desativados com o motivo; “Escolher outra pasta…” | toda recusa do `--dry-run` do motor; mesmo disco físico não tem botão |
| 5 Confirmar | origem → destino, método, o quê, tamanhos, avisos do motor, a promessa honesta | — |

“Voltar” nunca perde escolhas. “Cancelar” fecha o assistente sem ter feito nada.
Nada lê o disco antes de **Começar**, exceto o diálogo de montagem pedido pela
própria pessoa e a medição do total que o motor só faz em disco sem alertas.

## Estados (os mesmos em toda a janela)

`idle`, `loading`, `ready`, `attention`, `error`, `running`, `paused`, `cancelled`,
`partial`, `completed`, `device-disconnected`, `authorization-required` — em
`gui/models.py` (`UiState`). Cada trabalho os deriva do estado do motor
(`pending…stopping` → running, `needs-attention`/`interrupted` → partial, etc.).
Um disco que sumiu mostra “O disco foi desconectado — Nada mais foi feito”.

## Critérios de acessibilidade aplicados

- Estado nunca só por cor: `LevelBadge` sempre tem ícone e texto.
- Botões só com ícone têm nome acessível e dica.
- Diálogos: resposta segura como padrão e Escape = resposta segura.
- Atalhos: F5/Ctrl+R atualizar, Ctrl+Q sair, Ctrl+J trabalhos, Alt+Home início.
- Reflui a 360 px de largura (breakpoint em 720sp): uma coluna, seções no rodapé.
- Movimento reduzido: com animações desligadas, a barra sem total não pulsa.
- Textos de dispositivos e arquivos nunca são tratados como marcação.
