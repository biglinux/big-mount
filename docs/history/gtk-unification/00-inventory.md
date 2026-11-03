# 00 — Inventário e linha de base

Estado do repositório em `e0f56a4` (master), antes da unificação.

## Duas interfaces que faziam quase a mesma coisa

| Entrada | O que abria | Tecnologia |
| --- | --- | --- |
| `bigmount --gui-drive [DISCO]` | gerenciador de unidades e resgate (`drive-gui.py`, 1730 linhas); sem PySide6, caía no diálogo abaixo | Python + PySide6 (Qt) |
| `bigmount --gui-drive-check [DISCO]` | `bm_gui_drive` em `cli.sh`: verificação da unidade em diálogos e **Apagar a unidade inteira…** | KDialog/Zenity |
| **Verificar e apagar…** no gerenciador | abria um *segundo processo* com `--gui-drive-check` | — |

Resultado: duas identidades visuais, duas navegações e dois fluxos de Secure Erase
(o terminal e os diálogos), com o gerenciador Qt delegando ao diálogo.

## O motor (fonte da verdade, mantido)

| Módulo | Contrato |
| --- | --- |
| `drive.sh` | `list`, `inspect`, `diagnose [--smart]`, `mount`, `unmount`, `protect`, `unlock`, todos com `--json`; códigos de saída 20–25 |
| `drive-detect.sh` | um único `lsblk`, nunca lê o dispositivo |
| `drive-diag.sh` | nível de saúde com `basis` (de onde vem o veredito), SMART sob pedido, montagem somente leitura |
| `drive-copy.sh` | `destinations`, `copy` (verificações, `--dry-run`), jobs com supervisor destacado, `status`, `pause`, `cancel`, `resume`, `report [--anonymize]` |
| `drive-recovery.sh` | `image` (ddrescue com mapa, via helper), `partitions` (TestDisk `/list`), `carve` (PhotoRec, síncrono) |
| `bigmount-drive-helper` | `protect`, `unprotect`, `smart`, `partitions`, `image`, via pkexec |
| `lib.sh` | `bm_erase_check`, `bm_erase_run`, `bm_erase_unfreeze`, `bm_remove_core` |

## Lacunas do motor encontradas (preenchidas nesta unificação)

- Nenhuma identidade estável no JSON: a janela Qt guardava a seleção por `/dev/sdX`.
- Nenhuma resolução de UUID; nenhum jeito de saber “qual disco é este alvo” em JSON.
- Nenhum filtro por tipo: `carve` sempre buscava todos os tipos, e era síncrono
  (a janela Qt ficava esperando, sem progresso).
- Nenhuma lista do que *existe* por tipo (a “análise rápida”).
- `partitions` só fazia `/list` em texto; nenhuma análise sem gravação, nenhum JSON.
- Nenhum jeito de uma janela pedir o Secure Erase sem terminal, a não ser os diálogos.
- `copy --item` um a um: uma seleção grande virava milhares de argumentos.

## Linha de base dos testes (antes de qualquer mudança)

| Suíte | Resultado |
| --- | --- |
| `tests/run-tests.sh new` | 114 passaram, 0 falharam |
| `tests/lib-tests.sh` | 236 / 0 |
| `tests/drive-tests.sh` | 180 / 0 |
| `tests/i18n-tests.sh` | 38 / 0 |
| `tests/package-check.sh` | 69 / 0 |
| `tests/gui-tests.py` (PySide6, `QT_QPA_PLATFORM=offscreen`) | 37 testes, OK |

Ambiente: GTK 4.22.5, libadwaita 1.9.4, PyGObject 3.56.3, Python 3.14.7, Arch/BigLinux,
Plasma 6 em Wayland. TestDisk/PhotoRec 7.2, smartctl e rsync instalados; **ddrescue
ausente** (o caminho da imagem só foi validado com o substituto que já existia em
`drive-integration.sh`). Sem Xvfb: os testes gráficos usam `gtk4-broadwayd`.

## Riscos registrados no início

- O alias `--gui-drive-check` era o único caminho gráfico para o Secure Erase:
  removê-lo sem um substituto equivalente deixaria a função inacessível pela GUI.
- `tests/run-tests.sh` verifica quem chama `bm_erase_run`; qualquer novo caminho
  precisa ser explícito nesse teste.
- O caminho de boot (`bigmount` sem argumentos) não pode passar a carregar Python
  ou GTK: `drive-tests.sh` já verifica isso e foi mantido.
