# 02 — Sistema de design

Referência estudada: `biglinux-noise-reduction-pipewire`, parte Python/GTK
(`app/biglinux_microphone`, `app/big_gtk_kit`, `docs/ui-ux.md`). Nenhum código foi
copiado: o kit de lá é de cartões que abrem ao passar o mouse, um padrão que não
serve aqui (o pedido proíbe depender de hover). Foram adotados os princípios: uma
janela, widgets nativos, nomes acessíveis em botões de ícone, respeito ao tema e ao
alto contraste, estado nunca só por cor, refluxo em 1024×600 e estreito, e “uma
configuração carregada não é um diagnóstico de saúde”.

## Componentes

| Necessidade | Componente |
| --- | --- |
| janela | `Adw.ApplicationWindow` + `Adw.ToastOverlay` + `Adw.NavigationSplitView` |
| páginas | `Adw.NavigationView` / `Adw.NavigationPage`, `Adw.ToolbarView`, `Adw.HeaderBar` |
| seções do disco | `Adw.ViewStack` + `Adw.ViewSwitcher` (largo) / `Adw.ViewSwitcherBar` (estreito) |
| listas | `Adw.PreferencesGroup` + `Adw.ActionRow`/`ExpanderRow`/`ComboRow`/`SpinRow` |
| vazio e espera | `Adw.StatusPage` |
| perguntas | `Adw.AlertDialog` (libadwaita ≥ 1.5) |
| largura de leitura | `Adw.Clamp` |
| resultados | `Gtk.ColumnView` sobre um `Gio.ListModel` próprio |
| escolha de arquivos | `Gtk.ListView` + `Gtk.TreeListModel` + `Gtk.DirectoryList` |
| diálogos de arquivo | `Gtk.FileDialog` (portal) |

Peças próprias em `gui/widgets.py`: `LevelBadge` (ícone + texto do nível),
`UsageBar`, `Stat` (número + o que conta), `notice` (aviso com ícone e ação),
`button_row` (botões que quebram de linha), `fact_row` (nome pequeno, valor
selecionável), `TextDialog` (texto técnico monoespaçado, com copiar).

## Cor, tipografia e forma

- Só cores nomeadas do Adwaita (`@accent_color`, `@error_color`, `@warning_color`,
  `@success_color`, `alpha(currentColor, …)`), para claro, escuro e alto contraste.
  Um teste falha se `style.css` tiver `#rrggbb` ou `rgb()`.
- Classes de tipo do Adwaita: `title-1/2/3/4`, `heading`, `caption`, `dim-label`,
  `numeric`, `monospace`.
- Cartões com raio de 14 px e 16 px de respiro; ícones simbólicos do tema
  (`drive-harddisk-symbolic`, `drive-harddisk-solidstate-symbolic`,
  `drive-removable-media-symbolic`, `media-flash-symbolic`, …).
- Ação principal em azul (`suggested-action`) só quando é a recomendada: em disco
  com alerta, “Recuperar arquivos”/“Resgatar meus arquivos”.
- Vermelho (`destructive-action`, `.danger-panel`) só no Secure Erase.

## Linguagem

- Primeiro o que importa para a pessoa, depois o técnico (“Detalhes”, ⋮).
- “Nenhum alerta encontrado nas informações consultadas” — nunca “saudável”.
- Três palavras que não se misturam: arquivos que **existem** (lista), **candidatos**
  (busca por conteúdo), arquivos **copiados**. O contrato JSON tem `result_kind`.
- Nenhuma porcentagem sem total medido; “≈” quando o total é estimado.

## Capturas

Geradas pela janela real por `tests/readme-screenshots.py` (claro e escuro, inglês e
português) e revisadas uma a uma; ficam em `docs/images/app-*.png`.
