obj-m := hello.o
KDIR ?= $(HOME)/jm21-kbuild/msm515
all:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=arm64 LLVM=1 modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
