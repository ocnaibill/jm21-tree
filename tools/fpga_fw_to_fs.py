#!/usr/bin/env python3
"""Converte o bitstream binario da FiiO (Gowin .fw) para o formato texto .fs
que o Apicula (gowin_unpack) entende.

Formato descoberto por medicao (docs/30):
  header : 20*FF | 2*FF | A5C3 | 06..ID | 10.. | 51.. | 0B.. | D2.. | 12.. | 3B <frames>
  data   : <frames> linhas de 122 bytes uteis
  footer : 18*FF 3473 | 0A000000 <user code> | 8*FF | 08 000000 | 8*FF | FFFF

Cada linha de dados no .fs = payload + CRC16-ARC (2 B, little-endian) + 6*FF.
O CRC cobre (header sem preambulo/D2) para o 1o frame; depois 6*FF + payload.
"""
import sys

B2B = [f"{i:08b}" for i in range(256)]


def crc16_arc(data: bytes, crc: int = 0x0000) -> int:
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def bits(bs: bytes) -> str:
    return "".join(B2B[b] for b in bs)


def convert(fw_path: str, out_path: str, frames: int = 274, frame_size: int = 160):
    d = open(fw_path, "rb").read()

    # localiza as pecas sem depender de tamanhos fixos
    i3b = d.find(bytes.fromhex("3b800112"))
    if i3b < 0:
        raise SystemExit("nao achei a linha 3B (contagem de frames)")
    header = d[: i3b + 4]
    if len(header) < 66:
        raise SystemExit(f"header curto: {len(header)}")

    iusr = d.rfind(bytes.fromhex("3473"))
    if iusr < 0:
        raise SystemExit("nao achei o footer 3473")
    footer = d[iusr - 18 :]

    raw = d[len(header) : iusr - 18]

    # dados comprimidos: a chave vem da linha 0x51 (ba[5]); 0xdb -> 8 zeros
    key = header[45]
    data = bytearray()
    for b in raw:
        if b == key:
            data += b"\x00" * 8
        else:
            data.append(b)
    need = frames * frame_size
    if len(data) < need:
        raise SystemExit(f"dados curtos apos descomprimir: {len(data)} < {need}")
    data = bytes(data[:need])

    # reconstroi as linhas do header (22*FF = 20 + 2, como no .fs do Gowin)
    h = header
    assert h[:22] == b"\xff" * 22, "preamble inesperado"
    assert h[22:24] == bytes.fromhex("a5c3"), "magic inesperado"
    hdr_lines = [
        h[0:20],                              # FF x20   (preambulo)
        h[20:22],                             # FF x2    (preambulo)
        h[22:24],                             # A5C3     (preambulo)
        h[24:32],                             # 06 ID
        h[32:40],                             # 10
        h[40:48],                             # 51
        h[48:52],                             # 0B
        h[52:60],                             # D2 (nao entra no CRC)
        h[60:64],                             # 12
        h[64:68],                             # 3B
    ]

    # o header da FiiO marca compressao (bit 13 da linha 0x10), mas os dados
    # estao SEM compressao (274 x 122 bytes exatos); limpa a flag
    l10 = int.from_bytes(hdr_lines[4], "big") & ~(1 << 13)
    hdr_lines[4] = l10.to_bytes(8, "big")

    seed = b"".join(l for l in hdr_lines[3:] if l[:1] != b"\xd2")

    with open(out_path, "w") as f:
        for line in hdr_lines:
            f.write(bits(line) + "\n")

        crc_in = seed
        for n in range(frames):
            payload = data[n * frame_size : (n + 1) * frame_size]
            c = crc16_arc(crc_in + payload)
            f.write(bits(payload) + bits(bytes((c & 0xFF, c >> 8))) + "1" * 48 + "\n")
            crc_in = b"\xff" * 6

        # resto (bytes apos os frames) + footer: o leitor trata como rodape
        rest = data[need:]
        if rest:
            f.write(bits(rest) + "\n")
        for off in range(0, len(footer), 8):
            chunk = footer[off : off + 8]
            f.write(bits(chunk) + "\n")

    print(f"{out_path}: header {len(header)} B, {frames} frames de {frame_size} B "
          f"(bruto {len(raw)} B, chave 0x{key:02x}, descomprimido {len(data)} B), "
          f"footer {len(footer)} B")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("uso: fpga_fw_to_fs.py <arquivo.fw> <saida.fs>")
    convert(sys.argv[1], sys.argv[2])
