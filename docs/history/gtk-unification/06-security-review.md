# 06 — Revisão de segurança

## Privilégio

- A aplicação roda como o usuário; recusa root (5). O que precisa de mais passa por
  UDisks2/polkit (montar, desbloquear, Secure Erase) ou pelo helper via pkexec
  (proteger, SMART, partições, imagem). Nenhuma ação polkit nova.
- O helper ganhou um único caso: `partitions DEV search i386|gpt`, que roda
  `testdisk /nolog /cmd DEV partition_X,analyze`. A lista de comandos é fixa e não
  contém `write`; o tipo de tabela é verificado contra duas palavras. Testado numa
  imagem: hash idêntico antes e depois.

## Execução

- Sempre `argv` em lista (`Gio.Subprocess`); nenhum `shell=True`, `os.system` ou
  `eval` (testes procuram por eles).
- A senha de um volume criptografado vai do `Gtk.PasswordEntry` direto ao UDisks2 por
  D-Bus e o campo é limpo; nunca aparece em argumentos (teste e cenário LUKS real).
- Seleções grandes vão em arquivo NUL `0600` no `XDG_RUNTIME_DIR`, nunca em argumentos.
- Rótulos e nomes de arquivo são texto: `use_markup=False` em labels e linhas, e
  `GLib.markup_escape_text` onde o Adwaita só aceita marcação (título de grupo).
- Nomes de arquivo encontrados nunca são executados nem abertos por aplicativo
  externo; a pré-visualização decodifica imagens com GdkPixbuf num thread, com limite
  de tamanho, e não é oferecida para disco em risco (seria mais uma leitura).

## Nunca gravar na origem

- Toda recuperação passa pelo `--dry-run` do motor, que compara topologia
  (partição, LUKS, LVM) e recusa o mesmo disco físico, destino dentro da origem e
  origem dentro do destino. A aplicação **não** oferece as opções `--allow-*`.
- `--results-of ID` é a única exceção de “mesmo sistema de arquivos”: copiar
  candidatos que já estão no destino de uma busca nossa. Só a pasta registrada no
  trabalho, nunca um caminho dado.
- A imagem registra a identidade do disco (`img.source`): continuar a imagem de um
  disco com outro é recusado.
- `mount` e `image` recebem `--expect-diskseq` do disco que a janela mostrou.

## Secure Erase pela aplicação

Motor intocado: `bm_erase_check` decide quem pode, `bm_erase_run` apaga via
`Drive.Ata.SecurityEraseUnit`. O novo `drive-erase.sh` só conversa:

1. `erase-check` — elegibilidade e partições; não altera nada.
2. Confirmação 1 na janela: explicação em vermelho, “NÃO É RECUPERAÇÃO”, Cancelar
   como padrão e Escape.
3. `erase-prepare --expect-diskseq N` — revalida, recusa um disco que não é o
   que a janela mostrou e cria um **ticket** aleatório de 128 bits, `0600`,
   amarrado a disco + diskseq + serial, válido 10 minutos, de uso único.
4. Confirmação 2: o nome do disco digitado; o botão só habilita com o nome exato, e
   Enter não apaga.
5. `__erase-run TICKET --typed NOME` — compara o nome **no Shell**, revalida
   identidade e elegibilidade, trava o disco, confere de novo o diskseq do ticket,
   libera (montagens/LUKS), e para em
   serviços dependentes ou estado *frozen* devolvendo a pergunta; só continua com
   `--allow-services`/`--unfreeze` depois de uma decisão explícita. polkit pede a
   senha de administrador como sempre.
6. O resultado é o de `bm_erase_result_doc`; “Disco apagado” só aparece com código 0.

Não há `--assume-yes` nem atalho; um teste procura por eles. A janela inibe
suspensão e logout durante o apagamento e não fecha. Limite honesto: um programa do
mesmo usuário poderia chamar o UDisks2 diretamente, como sempre pôde; a barreira
real continua sendo o polkit.

Testes: tickets forjados, vencidos, de caminho, com nome quase certo, de disco
trocado (diskseq e serial), sistema surgido no meio, trava ocupada, ocupado,
serviços, frozen, falha que não é chamada de sucesso; e, com o motor real, recusa
para o disco do sistema em execução e ticket forjado sem efeito.

## Achados corrigidos durante a revisão

- O PhotoRec responde 0 a um comando que não entendeu: agora “syntax error” vira falha.
- A família `dovecot` do PhotoRec transforma áreas vazias em milhares de candidatos
  vazios (visto numa imagem esparsa): desligada em “todos os tipos”.
- Uma origem desmontada no meio do assistente voltava a ser usada pelo caminho
  antigo: agora o assistente volta à etapa 3 e avisa.
