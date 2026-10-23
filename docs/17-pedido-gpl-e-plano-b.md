# 17 — Pedido de código-fonte GPL à FiiO (+ plano B)

## 1. Por que o pedido é legítimo (e não um favor)

`[FW]` Os módulos de áudio do JM21 declaram licença GPL no próprio `.modinfo`:

| Módulo | Licença declarada |
|--------|-------------------|
| `cs43198.ko` | `GPL` |
| `dac_core_module.ko` | `GPL v2` |
| `anolog_board_jm21.ko` | `GPL v2` |
| `fiio_primary_modules.ko` | `GPL` |
| `gw-fpga.ko` | `GPL` |
| `fiio_underlay_modules.ko`, `fiio_headset_jack.ko`, `fiio_snd_soc_dummy_dai.ko`, `fiio_config.ko`, `fiio_gpio_debug_module.ko` | GPL (mesma árvore) |

Pela GPLv2 §3, quem distribui o binário deve fornecer o código correspondente
completo a quem o recebeu. Comprar o aparelho nos torna destinatários.

`[FW]` O repositório público da FiiO (`FiiOapp/FiiO_Kernel_OpenSource`) é
**Linux 2.6.31.3 para Ingenic** — players antigos, não o JM21. Ou seja: o fonte
deste aparelho **não está publicado**; o pedido é o único caminho oficial.

## 2. Identificadores para o pedido

```
Modelo              : FiiO JM21 (3 GB / 32 GB)
Firmware            : 1.1.1 (pacote completo beta/JM21-update-1.1.1.zip)
Build fingerprint   : qti/bengal_515/bengal_515:13/TKQ1.230110.001/
                      eng.fiio.20260428.144644:user/dev-keys
Kernel              : 5.15.41-android13-8-g9ded8564ff52-dirty
Toolchain (banner)  : Android clang 14.0.7 (r450784e), LLD 14.0.7
Vermagic            : 5.15.41-g9ded8564ff52-dirty SMP preempt mod_unload
                      modversions aarch64
```

SHA-256 dos módulos (para eles identificarem a build exata):

```
ad32570b9dda2e935c35eadccce2ac3f327b9e43e09191788e8d103e26d52ccf  cs43198.ko
3918796dfff0a2d5d1ad30e3d0e2ddf71077e2617409ce8fc333f6c90f767565  dac_core_module.ko
5479557bae1fa69bb551dbdcd0323b1e3ed9d62d396222a7dc5a4851c08d051d  anolog_board_jm21.ko
b126147030ca881d9aae5586705ce6e88841fd74ec2dd319d39d845c5d8ad701  gw-fpga.ko
ca0448e42c55f1072d83115942121a587124dbd8a4732f4c93b47c7f4d3617eb  fiio_primary_modules.ko
2ea91fabfcc199e67d1670a400972b584be57d6a32cd292ae8b2b00368b2c544  fiio_underlay_modules.ko
b510a6976989508f82ac5e7a0e30e922075a77299592ea64c16d2cbba3a2ec99  fiio_headset_jack.ko
3ffcddc3f348e694eb459cb87aa07fbc72afcf7ab649ed5c51fd1312866c1a87  fiio_snd_soc_dummy_dai.ko
e65ec5f505e55d5bb4be26777d8881dbdee2772ae4dc293934c1d80dcbad3337  fiio_config.ko
3f4b6da7363127b134e1c057b86a1e5005793b4ab983dd407d47e6ff60ba5994  fiio_gpio_debug_module.ko
```

## 3. E-mail (inglês, pronto para enviar)

> **To:** support@fiio.com
> **Cc:** (se houver) open-source compliance / legal
> **Subject:** GPLv2 source code request — FiiO JM21, firmware 1.1.1 (kernel modules)
>
> Dear FiiO Support,
>
> I own a FiiO JM21 digital audio player (3 GB / 32 GB variant) running
> firmware 1.1.1.
>
> The device ships several kernel modules that declare GPL licensing in their
> own `.modinfo` sections (license=GPL / license=GPL v2), including
> `cs43198.ko`, `dac_core_module.ko`, `anolog_board_jm21.ko`, `gw-fpga.ko`,
> `fiio_primary_modules.ko`, `fiio_underlay_modules.ko`,
> `fiio_headset_jack.ko`, `fiio_snd_soc_dummy_dai.ko`, `fiio_config.ko` and
> `fiio_gpio_debug_module.ko`.
>
> Under section 3 of the GNU General Public License version 2, as a recipient
> of these binaries I am entitled to the complete corresponding source code.
> I am therefore requesting:
>
> 1. The complete corresponding source code for the modules listed above (or
>    the kernel tree from which they were built), including Kconfig/Makefile
>    files and any out-of-tree module directories.
> 2. The kernel `.config` used for this build.
> 3. The exact base revision and the patch set applied on top of it. From the
>    device banner, the base appears to be `5.15.41-android13-8-g9ded8564ff52`
>    with local modifications (`-dirty`).
> 4. The toolchain used (the banner reports Android clang 14.0.7 / LLD 14.0.7).
> 5. Any build or packaging scripts needed to reproduce these modules.
>
> For identification of the exact build, the modules' SHA-256 hashes and the
> build fingerprint are listed at the end of this message.
>
> If the source is already published, a download link is sufficient. I am
> happy to cover reasonable costs of media and shipping if it must be sent
> physically, as permitted by GPLv2 §3.
>
> I would appreciate a reply within 30 days. If the request cannot be
> fulfilled directly, please forward it to the person or team responsible for
> your open-source compliance.
>
> Thank you for your attention.
>
> Kind regards,
> [NOME]
> [ENDEREÇO DE ENTREGA, se aplicável]
> [E-MAIL] · [TELEFONE opcional]
>
> ---
> Device: FiiO JM21 (3 GB / 32 GB)
> Firmware: 1.1.1 — full package `JM21-update-1.1.1.zip`
> Build fingerprint: `qti/bengal_515/bengal_515:13/TKQ1.230110.001/eng.fiio.20260428.144644:user/dev-keys`
> Kernel: `5.15.41-android13-8-g9ded8564ff52-dirty`
> Vermagic: `5.15.41-g9ded8564ff52-dirty SMP preempt mod_unload modversions aarch64`
> Toolchain: Android clang 14.0.7 (r450784e), LLD 14.0.7
> Module SHA-256:
> [colar a lista do §2]

### Versão curta (formulário/suporte)

> Hello. I own a FiiO JM21 running firmware 1.1.1. The player ships GPL-licensed
> kernel modules (`cs43198.ko`, `dac_core_module.ko`, `anolog_board_jm21.ko`,
> `gw-fpga.ko`, `fiio_primary_modules.ko` and others). Under GPLv2 §3 I request
> the complete corresponding source code, the kernel `.config` and the base
> revision (`5.15.41-android13-8-g9ded8564ff52-dirty`) plus applied patches.
> A download link is fine; I can cover media/shipping costs. Please forward to
> your open-source compliance contact if needed. Thank you.

## 4. Plano B — assumindo que não respondem

Premissa realista: a maioria dos fabricantes de DAP ignora ou demora. O plano
técnico **não depende** deles; o pedido é upside, não bloqueio.

### 4.1 O que o fonte resolveria (e o que já temos)

| Informação | Sem fonte | Com fonte |
|------------|-----------|-----------|
| Mapa de registradores do CS43198 | **temos** (datasheet + decompilado) | confirmação |
| Pipeline de volume/ganho | **temos** (tabelas + código) | confirmação |
| Sequência de energia e tempos | **temos** (20/10/10/50 ms) | confirmação |
| Contrato de eventos (notifier) | **temos** (BTF + decompilado) | confirmação |
| Lista de atributos sysfs | parcial (precisa terminar) | direto |
| Protocolo SPI do FPGA | **não temos** | direto |
| Layout da partição `fiioconfig` | **não temos** | direto |
| Qual amp liga em qual nó | **não temos** | indireto (netlist) |

Ou seja: ~70% do que queremos já saiu por engenharia reversa. O que o fonte
realmente destrava é **FPGA** e **fiioconfig**.

### 4.2 Escalonamento (se silêncio)

1. **D+0**: enviar para `support@fiio.com` e para o canal oficial de contato do
   site. Guardar o ID do ticket.
2. **D+15**: reenviar citando o ticket, pedindo apenas confirmação de
   recebimento e o contato de compliance.
3. **D+30**: carta formal (e-mail + PDF assinado) ao distribuidor que vendeu o
   aparelho (AliExpress/loja), explicando que a distribuição do binário sem o
   fonte correspondente é descumprimento da GPLv2 §3 e pedindo que encaminhem
   ao fornecedor.
4. **D+45**: contatar uma entidade de compliance de copyleft
   (ex.: Software Freedom Conservancy — *Copyleft Compliance*) apresentando o
   caso com a evidência (`.modinfo`, hashes, fingerprint). Isso costuma resolver
   por pressão institucional, mas é lento e não gera código no curto prazo.
5. **Paralelo**: manter a engenharia reversa andando. Nada aqui bloqueia.

### 4.3 Fallback técnico (o que fazemos independentemente)

| Alvo | Método | Saída |
|------|--------|-------|
| Superfície sysfs completa | decompilar módulos restantes e extrair os `device_attribute` | API de controle documentada |
| Caminho userspace→kernel | mapear as 41 regras `on property:` + props da HAL | diagrama fechado |
| HAL proprietária | Ghidra em `libfiioaudio.so`/`libfiioaqm.so` | DSD/DoP/MQA e nós tocados |
| FPGA | analisar o bitstream GW1NZ-1 | há ou não DSP de áudio |
| `fiioconfig` | dump no aparelho + BTF do `fiio_config.ko` | layout do blob |
| Topologia/ganho | medição de bancada (`15` §4) | fato, não inferência |

### 4.4 Regra de decisão

Não paramos nada esperando resposta. Se o fonte chegar, ele **substitui
inferência por leitura** — e o dossiê registra a troca de status, sem apagar o
que já foi concluído por evidência própria.
