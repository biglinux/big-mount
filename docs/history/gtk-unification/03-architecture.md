# 03 — Arquitetura

```text
bigmount --gui-drive [ALVO]  ─┐
bigmount --gui-drive-check   ─┴─ cli.sh → drive.sh: bm_gui_drive_main SEÇÃO ALVO
                                   (sem sessão gráfica → 25 e aponta para --drive;
                                    como root → 5; nunca carregado no boot)
                                └─ python3 -I drive-gui.py --target ALVO --section health
                                     verifica GTK 4 / libadwaita ≥ 1.5 (senão 25)
                                     └─ gui/application.py  Adw.Application única
                                          (org.biglinux.big-mount: a 2ª chamada vai
                                           para a janela aberta, no alvo pedido)
                                          └─ gui/window.py  estado: discos, trabalhos
                                               ├─ gui/engine.py   bigmount --drive … --json
                                               ├─ gui/monitor.py  udevadm monitor + tabela de montagens
                                               ├─ gui/models.py   dataclasses dos JSON
                                               └─ gui/pages/*.py  páginas
```

## Fronteira

A janela não decide nada sobre discos. Toda verificação está no Shell:

| Pergunta | Comando |
| --- | --- |
| quais discos, com identidade | `list` (`stable_id`, `diskseq`, `trim`, `size`) |
| qual disco é este alvo | `resolve ALVO` (dispositivo, pasta, `/dev/disk/by-*`, `UUID=…`; ambíguo → 20) |
| como está | `diagnose [--smart]` |
| o que dá para fazer, e o recomendado | `methods ALVO` |
| para onde | `destinations --source\|--device`, e o `--dry-run` de cada operação |
| fazer | `mount --expect-diskseq`, `copy --items-from/--results-of`, `scan`, `carve --categories`, `image --expect-diskseq --then-carve`, `partitions [--search]` |
| acompanhar | `jobs`, `status`, `results`, `report` |
| apagar | `erase-check`, `erase-prepare`, `__erase-run` (ver 06) |

O Python só lê o índice de resultados (arquivo NUL que o motor escreveu) e mostra
miniaturas de arquivos já salvos em outro disco.

## Processos e o laço do GTK

- `Gio.Subprocess.communicate_async`: o laço nunca bloqueia. Perguntas têm limite
  de 60 s (SIGTERM); operações não têm, porque o motor tem seus próprios limites.
- Jobs são supervisores destacados (`setsid`) do motor: fechar a janela só avisa;
  `Engine.shutdown` encerra apenas perguntas em andamento.
- Uma lista de discos por vez; pedidos no meio viram uma única releitura depois.
- Trabalhos: consulta a cada 5 s só enquanto algum roda; a página de um trabalho,
  a cada 1,5 s só enquanto visível. Janela ociosa: 0 chamadas (medido, ver 07).
- Hotplug: `udevadm monitor` e `GioUnix.MountMonitor`, com debounce de 700 ms.
  A seleção segue `stable_id` (serial, senão UUID do primeiro sistema de arquivos,
  senão nome+tamanho). Outro disco com o mesmo `/dev/sdb` não é o mesmo disco.

## Novos trabalhos do motor

| Tipo | Supervisor | Pausa | Resultado |
| --- | --- | --- | --- |
| `scan` | `find -xdev -printf` → `awk` classifica e escreve o índice | não (cancelar guarda o parcial) | `existing-files`, nomes e datas reais |
| `carve` | PhotoRec `/cmd` com as famílias do tipo pedido; lê o fim da tela para passo/setor/achados/ETA | não | `carved-candidates`, sem nomes nem datas |
| `image` (`--then-carve`) | o de antes; guarda `img.source` para não misturar discos | sim | `disk-image`; a busca depois só com clique |

Formato do índice: `tamanho\tmtime\tcategoria\tcaminho\0`, bytes como estão.

## Módulos

```text
usr/lib/big-mount/
  drive-gui.py           lançador: versões, root, mensagem de falta de dependência
  drive-erase.sh         Secure Erase para a aplicação (novo)
  gui/application.py     Adw.Application, ações e atalhos, roteamento --target/--section
  gui/window.py          janela, lateral, estado de discos e trabalhos, navegação
  gui/engine.py          cliente tipado do motor
  gui/monitor.py         hotplug
  gui/models.py          Device, Volume, Health, Job, Methods, UiState
  gui/widgets.py         peças comuns
  gui/common.py          gettext, tamanhos e tempos
  gui/style.css          complemento mínimo do Adwaita
  gui/pages/overview.py  início
  gui/pages/device.py    disco: visão geral, recuperar, saúde, histórico, menu
  gui/pages/rescue.py    assistente, escolha de arquivos, partições
  gui/pages/job.py       um trabalho; lista de trabalhos
  gui/pages/results.py   resultados virtuais, miniaturas, pré-visualização
  gui/pages/maintenance.py  Secure Erase
```

Nenhum `.md` é lido em tempo de execução (verificado em `package-check.sh`).
