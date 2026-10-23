PACOTE DE PEDIDO GPL - FiiO JM21 (firmware 1.1.1)
=================================================

O que tem aqui
--------------
00-README.txt .............. este arquivo
01-request-email-EN.txt .... corpo do e-mail, pronto para colar (ingles)
02-request-letter-EN.pdf ... mesma carta em PDF, para anexar ou enviar por
                             outros canais (impressa/assinada)
02-request-letter-EN.ms .... fonte groff da carta (se quiser editar e regerar)
03-build-identifiers.txt ... fingerprint, versao de kernel, toolchain e
                             metadados do pacote OTA
04-modules-sha256.txt ...... SHA-256 de cada modulo GPL distribuido
05-evidence-modinfo.txt .... license= e vermagic= extraidos de cada modulo
                             (a prova de que sao GPL e da build exata)

O que preencher antes de enviar
-------------------------------
No e-mail e no PDF:
  [NOME COMPLETO]
  [ENDERECO PARA ENVIO FISICO, se aplicavel]  (GPLv2 §3 permite exigir custo
                                               de midia/envio; se nao quiser
                                               receber fisico, escreva
                                               "electronic copy is preferred")
  [E-MAIL] e [TELEFONE, opcional]
  [DATA] (so no PDF)

Para onde enviar
----------------
Primario : support@fiio.com
Alternativa: formulario de contato do site oficial (use a versao curta)
Se houver canal de imprensa/legal, vale copiar (CC).

O que anexar
------------
Anexe 03, 04 e 05. O 02 (PDF) pode ir anexado ou ser enviado depois, no
escalonamento do plano B (D+30).

Detalhe importante sobre o nome do modulo
-----------------------------------------
O arquivo e "anolog_board_jm21.ko" - com "o", nao "a". E typo da propria FiiO,
repetido no device tree ("fiio,anolog_board") e nos logs. NAO corrija: o pedido
precisa citar exatamente o nome que existe no firmware.

Guarde o protocolo
------------------
Anote data/hora do envio e o ID do ticket. Se nao houver resposta:
  D+15  reenviar citando o ticket, pedindo o contato de compliance
  D+30  carta formal (02-request-letter-EN.pdf) ao distribuidor que vendeu
  D+45  entidade de compliance de copyleft, com este pacote como evidencia

Plano completo: docs/17-pedido-gpl-e-plano-b.md no repositorio.
