#include <linux/module.h>
#include <linux/kernel.h>

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("jm21 ABI test: verifica vermagic + modversions");
MODULE_AUTHOR("jm21-tree");

static int __init jm21abi_init(void)
{
	pr_info("jm21abi: loaded\n");
	return 0;
}

static void __exit jm21abi_exit(void)
{
	pr_info("jm21abi: unloaded\n");
}

module_init(jm21abi_init);
module_exit(jm21abi_exit);
