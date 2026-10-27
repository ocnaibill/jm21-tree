# Sepolicy

## O que a FIIO mudou (medido)

Surpresa das medições (`docs/47` §7.4): **não existe nenhuma entrada `fiio` ou
`mqa` em `property_contexts`** — nem em `plat_property_contexts`, nem em
`vendor`/`system_ext`/`product`/`odm`. As properties usadas pela FIIO
(`fiio.current.play.device`, `fiio.cur.session.id`, `mqa.audio.type`,
`output.device.usb.card.id`) caem no `default_prop`.

Consequência: quem pode setá-las é quem tem permissão sobre `default_prop` — no
stock, o `system_server`, que roda o framework patcheado. Foi exatamente por
isso que a GSI falhou com:

```
Unable to set property "mqa.audio.type" to "0": error code: 0x18
```

## O que trazer

1. Mantendo o framework patcheado, `fiio.*` e `mqa.*` **funcionam como no
   stock** (mesmo mecanismo: `default_prop` via `system_server`). Nada a fazer.
2. Se algum **serviço de vendor** precisar setar essas props, aí sim:
   - declarar tipos próprios (`fiio_prop`) em `property_contexts`;
   - regras `allow <dominio> fiio_prop:property_service set;`.
3. Regras de domínio dos serviços FIIO, se entrarem como binários:
   `fiio_charger_manager`, `fiio_init_service`, `fiio_drop_caches`,
   `fiio_headset_jack`.

## Arquivos esperados aqui

```
sepolicy/
├── vendor/    -> BOARD_VENDOR_SEPOLICY_DIRS
└── private/   -> SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS
```

Ainda vazios. Para preencher: extrair do stock os tipos próprios da FIIO.

```bash
# os .cil estao dentro das imagens
debugfs -R "dump /etc/selinux/vendor_sepolicy.cil /tmp/vendor.cil" \
    dumps/fw-1.1.1/vendor.img
grep -oE "fiio[a-z_]*" /tmp/vendor.cil | sort -u
```

## Nota de método

As medições mostraram que a FIIO **não** criou tipos de property próprios — o que
é incomum e um pouco frouxo do ponto de vista de segurança. Isso simplifica o
port (nada a portar nesse eixo) mas significa que qualquer processo com acesso a
`default_prop` pode escrever nessas props.
