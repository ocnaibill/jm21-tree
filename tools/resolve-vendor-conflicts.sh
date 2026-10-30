#!/usr/bin/env bash
# Resolve conflitos "overriding commands" entre blobs e modulos do Soong,
# um por rodada, ate o kati passar. O lista fica em tools/vendor-auto-skip.txt.
set -uo pipefail
R=/home/ocnaibill/repos/jm21-tree
cd "$R"
for round in $(seq 1 120); do
    python3 tools/gen-vendor-mk.py >/dev/null 2>&1
    systemd-run --user --unit="kat-loop" --collect -p MemoryMax=11G -- \
        bash -c 'cd /home/ocnaibill/lineage20 && source build/envsetup.sh >/dev/null 2>&1 && lunch lineage_jm21-userdebug >/dev/null 2>&1 && mka bacon -j8 > /tmp/kat.log 2>&1' >/dev/null 2>&1
    for i in $(seq 1 120); do systemctl --user is-active -q kat-loop || break; sleep 5; done
    T=$(grep -oE "overriding commands for target \`out/target/product/jm21/[^']+" /tmp/kat.log | head -1 | sed 's|.*/jm21/||')
    if [ -z "$T" ]; then
        echo "rodada $round: SEM CONFLITO NOVO" | tee -a /tmp/kat-loop.txt
        grep -oE "\[ *[0-9]+% [0-9]+/[0-9]+\]" /tmp/kat.log | tail -1 >> /tmp/kat-loop.txt
        exit 0
    fi
    echo "$T" >> tools/vendor-auto-skip.txt
    echo "rodada $round: + $T" | tee -a /tmp/kat-loop.txt
done
