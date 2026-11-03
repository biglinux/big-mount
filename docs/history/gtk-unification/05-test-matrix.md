# 05 — Matriz de testes

Executado nesta máquina (Arch/BigLinux, GTK 4.22.5, libadwaita 1.9.4) em 2026-10-31.

## Suítes automáticas

| Suíte | O que roda | Resultado |
| --- | --- | --- |
| `tests/run-tests.sh new` | caminho de boot com stubs | 114 / 0 |
| `tests/lib-tests.sh` | biblioteca, Secure Erase do terminal e da aplicação (tickets) | 232 / 0 ¹ |
| `tests/drive-tests.sh` | motor com fixtures; `methods`, `scan` real numa pasta, `--items-from`, parsers do TestDisk e do PhotoRec | 234 / 0 |
| `tests/i18n-tests.sh` | catálogo, placeholders, pt_BR completo (1110 mensagens) | 38 / 0 |
| `tests/package-check.sh` | `package()`, arquivos instalados, dependências, nada de Qt, nada de `.md` em runtime | 92 / 0 |
| `tests/gui-tests.py` | a aplicação em Broadway com o motor substituto | 132 testes, OK |
| `tests/gui-e2e.py` | a aplicação com o **motor real** em arquivos de rascunho | 8 testes, OK |
| `tests/drive-integration.sh` | discos virtuais reais (loop, dm-error, dm-delay, LUKS), sudo | 173 / 0 |
| ShellCheck (comando do README) | todo o Shell | sem avisos |

¹ Antes eram 236: saíram os 6 testes do caminho de diálogos removido; os ~30 testes
novos do ticket rodam num subshell e contam como uma verificação no total (cada um
é impresso).

## Cenários do pedido

| # | Cenário | Onde | Situação |
| --- | --- | --- | --- |
| 1 | as duas flags abrem a mesma aplicação; o alias em Saúde | `gui-tests` Launcher e Routing; `drive-integration` | testado (processo real em Broadway) |
| 2 | com/sem disco, UUID, by-id, caminho, ambíguo, inexistente | Routing; `drive-tests` UUID | testado |
| 3 | HDD, SSD, NVMe, USB, SD, imagem, criptografado | Home | testado com fixtures |
| 4 | hotplug; troca de identidade de `/dev/sdX` | Hotplug | testado com fixtures; assistente volta à etapa 1 |
| 5 | disco crítico: recomendação não grava na origem | Wizard, Volumes | testado (montagem `--read-only --protect`) |
| 6 | mesmo disco, outra partição, symlink | `gui-tests` Wizard; `drive-integration` | testado: sem botão de exceção; motor compara topologia |
| 7 | destino cheio, sem permissão, desconectado | `drive-integration`; `gui-e2e` | testado no motor; janela mostra o texto do motor |
| 8 | muitos arquivos, Unicode, quebra de linha, nome com `-` | `drive-tests`, `gui-e2e`, ResultIndex | testado; nome com quebra de linha é recusado e dito |
| 9 | pausa, cancelamento, retomada, janela fechada, reinício | Jobs; `drive-integration` (queda de energia simulada) | testado |
| 10 | ddrescue e mapa | `drive-integration` com **substituto** | ddrescue real **não validado**: não instalado aqui |
| 11 | TestDisk/PhotoRec ausentes | Wizard, `drive-tests` methods | testado com fixtures |
| 12 | resultados ausentes, sem metadados, nada encontrado | Results, Jobs | testado |
| 13 | SMART indisponível, permissão negada | Health | testado com fixtures |
| 14 | Secure Erase recusado: sistema, USB, NVMe, partição, senha | Erase; `lib-tests` | testado |
| 15 | Secure Erase simulado: 2 confirmações, ticket, troca de disco, cancelamento, falha | Erase; `lib-tests` | testado; **nenhum apagamento real** |
| 16 | claro/escuro, estreito, teclado | Accessibility; capturas | parcial: alto contraste e fonte 200% revisados à mão nas capturas, não automatizados |
| 17 | CLI e boot sem regressão | todas as suítes de Shell | testado |
| 18 | CPU/RAM, zumbis | `tests/measure-app.py` | medido (07) |
| 19 | renderização real headless, sem PySide6 | `gui-tests` em Broadway | testado |
| 20 | capturas reais revisadas | `readme-screenshots.py` | feito |

## Não testado (e por quê)

- ddrescue real e qualquer disco físico com defeito: sem ddrescue e sem disco de
  laboratório nesta máquina.
- Wayland e X11 reais com leitor de tela: os testes usam Broadway; Orca não foi
  exercitado.
- Secure Erase em hardware: proibido fora de laboratório; só mocks.
- `.github/workflows/tests.yml` foi atualizado mas não rodou no GitHub nesta sessão.
