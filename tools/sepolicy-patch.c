// Adiciona uma regra allow a uma policy SELinux binaria (Android).
// Compile: gcc -O2 -o sepolicy-patch sepolicy-patch.c /usr/lib/libsepol.a -lpthread
// Uso: ./sepolicy-patch in.policy out.policy <src> <tgt> <class> <perm>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sepol/policydb/policydb.h>
#include <sepol/policydb/avtab.h>
#include <sepol/policydb/hashtab.h>

int main(int argc, char **argv) {
    if (argc != 7) { printf("uso: %s in out src tgt class perm\n", argv[0]); return 1; }
    policydb_t pdb; policydb_init(&pdb);
    FILE *f = fopen(argv[1], "rb");
    policy_file_t pf; memset(&pf,0,sizeof(pf)); pf.type=PF_USE_STDIO; pf.fp=f;
    if (policydb_read(&pdb,&pf,0)) { printf("read fail\n"); return 1; }
    fclose(f);
    type_datum_t *st=(type_datum_t*)hashtab_search(pdb.p_types.table,argv[3]);
    type_datum_t *tt=(type_datum_t*)hashtab_search(pdb.p_types.table,argv[4]);
    class_datum_t *cl=(class_datum_t*)hashtab_search(pdb.p_classes.table,argv[5]);
    if (!st||!tt||!cl) { printf("lookup fail (src=%s tgt=%s cls=%s)\n",argv[3],argv[4],argv[5]); return 1; }
    perm_datum_t *pm=(perm_datum_t*)hashtab_search(cl->permissions.table,argv[6]);
    if (!pm) { printf("perm fail\n"); return 1; }
    printf("%s=%u %s=%u %s=%u %s=%u bit=0x%x\n", argv[3],st->s.value,argv[4],tt->s.value,argv[5],cl->s.value,argv[6],pm->s.value,1u<<(pm->s.value-1));
    avtab_key_t key; memset(&key,0,sizeof(key));
    key.source_type=st->s.value; key.target_type=tt->s.value;
    key.target_class=cl->s.value; key.specified=AVTAB_ALLOWED;
    avtab_datum_t d; memset(&d,0,sizeof(d)); d.data=1u<<(pm->s.value-1);
    avtab_ptr_t ex=avtab_search_node(&pdb.te_avtab,&key);
    if (ex) { ex->datum.data |= d.data; printf("OR existente -> 0x%x\n", ex->datum.data); }
    else if (avtab_insert(&pdb.te_avtab,&key,&d)) { printf("insert fail\n"); return 1; }
    else printf("inserido\n");
    FILE *o=fopen(argv[2],"wb");
    policy_file_t po; memset(&po,0,sizeof(po)); po.type=PF_USE_STDIO; po.fp=o;
    int rc=policydb_write(&pdb,&po); fclose(o);
    printf("write rc=%d\n",rc); return 0;
}
