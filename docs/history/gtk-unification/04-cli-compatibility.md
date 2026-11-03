# 04 — Compatibilidade do CLI

## Entradas gráficas

| Chamada | Antes | Agora |
| --- | --- | --- |
| `bigmount --gui-drive` | janela Qt; sem PySide6, diálogos | a aplicação, no início |
| `bigmount --gui-drive /dev/sdb1` ou `PASTA` | janela Qt com o disco selecionado | a aplicação, no disco (resolvido pelo motor) |
| `bigmount --gui-drive UUID=…` / `/dev/disk/by-uuid/…` | não aceitava | aceita se houver um único dispositivo; ambíguo → aviso e início |
| `bigmount --gui-drive-check [DISCO]` | diálogos KDialog/Zenity | **alias**: a mesma aplicação, aberta em **Saúde** |
| `bigmount --gui` → “Verificar a unidade” | `bm_gui_drive` | `--gui-drive-check` do disco |
| sem sessão gráfica | diálogos ou texto | sai com 25 e aponta `bigmount --drive` |
| sem GTK 4 / libadwaita ≥ 1.5 | — | notificação e stderr dizem o que falta; 25 |
| como root | Qt recusava | recusa com 5 e explica |
| segunda chamada com a janela aberta | segunda janela | vai para a janela aberta, no alvo pedido |

O lançador `.desktop` e o menu do Dolphin continuam chamando `--gui-drive` (o
`.desktop` ganhou `StartupWMClass=org.biglinux.big-mount`).

## Comandos de terminal (inalterados)

`--drive` e todos os subcomandos, opções e códigos de saída anteriores continuam
iguais; `--secure-erase DISCO` continua exigindo terminal e o nome digitado.
`carve` sem `--categories` num terminal continua abrindo a interface do PhotoRec;
com `--json` continua respondendo no fim, com o mesmo `recovered`/`ok`/`exit`
(agora por meio de um trabalho, que também aparece em `jobs`).

## Adições ao `--drive` (todas com `--json`)

```text
resolve ALVO                         qual disco é este alvo
methods ALVO                         formas de recuperar, disponíveis, recomendada
scan --source PASTA [--categories L] [--copy-to D] [--no-wait|--dry-run]
carve ... --categories L [--no-wait|--dry-run]
results ID                           índice e contagem por tipo de uma lista ou busca
partitions ALVO [--search] [--json]  tabela, ou análise sem gravação
image ... --expect-diskseq N --then-carve PASTA --categories L [--dry-run --json]
mount ... --expect-diskseq N
copy ... --items-from ARQUIVO_NUL | --results-of ID
destinations --device DEV
safe-remove ALVO
erase-check DISCO | erase-prepare DISCO
__erase-run TICKET --typed NOME [--allow-services] [--unfreeze]   (interno)
```

`L` é `all` ou uma lista de `photos,videos,documents,audio,archives`; qualquer outra
palavra é recusada (2). Novos campos nos JSON existentes só foram acrescentados:
`stable_id`, `diskseq`, `size`, `trim`, `removable`, `hotplug`, `rotational`,
`pttype` em cada disco; `read_at`, `nvme_*` no SMART; `result_kind`, `pausable`,
`scanned`, `pass`, `bad_bytes`, `categories`, `then_carve`, `copy_to`, `level` nos
trabalhos; `fstype` nos destinos; `powered_off` em `unmount`.

## Removido

- `drive-gui.py` em PySide6 (substituído pelo lançador GTK de mesmo nome).
- `bm_gui_drive`, `bm_pick_drive` e `bm_gui_secure_erase` de `cli.sh` (o caminho de
  diálogos). Os textos de `bm_erase_*_doc` continuam, usados pelo terminal e pela
  aplicação.
- `pyside6` das dependências opcionais; `python`, `python-gobject`, `gtk4` e
  `libadwaita>=1.5` entraram nas dependências (só carregados por `--gui-drive*`), e
  `polkit` (o `pkexec` do helper), `rsync` (toda cópia) e `smartmontools` (a página
  Saúde) passaram de opcionais a obrigatórios. `ddrescue` e `testdisk` continuam
  opcionais: a aplicação diz o que falta. A versão passou a 2.4.0.
