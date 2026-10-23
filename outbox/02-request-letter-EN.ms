.ps 11
.ll 6.4i
.nr LL 6.4i
.PP
FiiO Electronics Technology Co., Ltd.
.br
Attn.: Open Source Compliance / Technical Support
.br
Guangzhou, Guangdong, China
.PP
Date: [DATA]
.PP
.B "Subject: GPLv2 section 3(b) request - complete corresponding source code for FiiO JM21 (firmware 1.1.1)"
.PP
Dear Sir or Madam,
.PP
I am the owner of a FiiO JM21 digital audio player (3 GB / 32 GB variant), running firmware version 1.1.1.
.PP
The device contains several loadable kernel modules distributed in binary form whose
.I .modinfo
sections declare GPL licensing:
.PP
.nf
    cs43198.ko                    license=GPL
    dac_core_module.ko            license=GPL v2
    anolog_board_jm21.ko          license=GPL v2
    gw-fpga.ko                    license=GPL
    fiio_primary_modules.ko       license=GPL
    fiio_underlay_modules.ko      license=GPL
    fiio_headset_jack.ko          license=GPL
    fiio_snd_soc_dummy_dai.ko     license=GPL
    fiio_config.ko                license=GPL
    fiio_gpio_debug_module.ko     license=GPL
.fi
.PP
Please note that the filename
.I anolog_board_jm21.ko
is reproduced exactly as shipped in the firmware; it is spelled with an "o" in the device, in the device tree
.I (fiio,anolog_board)
and in the module itself.
.PP
Under section 3(b) of the GNU General Public License version 2, these binaries were distributed to me together with a written offer to provide the complete corresponding source code. I hereby exercise that offer as a recipient of the device.
.PP
I request:
.IP "1." 4
The complete corresponding source code for the modules listed above (or the kernel tree from which they were built), including Kconfig/Makefile files and any out-of-tree module directories.
.IP "2." 4
The kernel .config used for this build.
.IP "3." 4
The exact base revision and the patch set applied on top of it. From the device banner, the base appears to be 5.15.41-android13-8-g9ded8564ff52 with local modifications (suffix -dirty).
.IP "4." 4
The toolchain used (the banner reports Android clang 14.0.7 and LLD 14.0.7).
.IP "5." 4
Any build or packaging scripts needed to reproduce these modules.
.PP
For identification of the exact build, the build fingerprint, kernel version, vermagic and the SHA-256 hash of each module are listed in the enclosure.
.PP
If the source is already published, a download link is sufficient. I am happy to cover reasonable costs of media and shipping if it must be sent physically, as permitted by GPLv2 section 3.
.PP
I would appreciate a reply within 30 days. If this request cannot be fulfilled directly, please forward it to the person or team responsible for your open-source compliance.
.PP
Thank you for your attention.
.PP
Yours faithfully,
.PP
.br
[NOME COMPLETO]
.br
[ENDERECO PARA ENVIO FISICO, se aplicavel]
.br
[E-MAIL]  |  [TELEFONE, opcional]
.PP
.B Enclosures:
build identifiers, module hash list, .modinfo excerpts.
