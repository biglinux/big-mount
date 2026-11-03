# 07 — Desempenho

Medido com `python3 tests/measure-app.py` (Broadway, motor substituto) e com o motor
real nesta máquina (3 discos), em 2026-10-31.

| Medida | Resultado |
| --- | --- |
| do processo até pedir a lista de discos | 1,9 s (inclui `dbus-run-session` e importar GTK/libadwaita) |
| memória da janela ociosa (RSS) | 100 MiB |
| CPU da janela ociosa em 20 s | 0 ms |
| chamadas ao motor com a janela ociosa em 20 s | 0 |
| processos filhos ociosa | 1 (`udevadm monitor`), 0 zumbis |
| `bigmount --drive list --json` (motor real) | ~150 ms |
| índice de 100 000 resultados | lido em 0,09 s, busca em 0,05 s, +9 MiB |
| índice de 1 000 000 resultados | lido em 0,88 s, busca em 0,47 s, +98 MiB |

Por quê:

- Nada faz polling quando nada roda: hotplug por eventos, montagens pelo monitor do
  GLib, trabalhos consultados só enquanto algum está rodando.
- Resultados: os nomes ficam no arquivo mapeado (`mmap`); a memória guarda só
  deslocamentos, tamanhos e categorias em `array`. Só as linhas visíveis viram
  objetos (`Gio.ListModel` próprio). Filtro e ordenação rodam num thread.
- Miniaturas: um worker, fila LIFO limitada a 64, cache LRU de 256, só para
  candidatos já salvos em outro disco; nunca lê a origem por uma miniatura.
- A escolha de arquivos lê uma pasta só quando a pessoa a abre, com prioridade baixa,
  sem monitorar mudanças.
- A barra sem total pulsa a cada 180 ms só enquanto visível e só com animações ligadas.

O caminho de boot não mudou: `bigmount` sem argumentos continua sem carregar nenhum
módulo de unidade, Python ou GTK (`drive-tests.sh` e `gui-tests.py` verificam).
