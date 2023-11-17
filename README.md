# sev

An example of Makefile to build SEV-SNP artifacts:

```
build/opt/amdese/bin/qemu-system-x86_64 kernel ld loader nvram:
	DOCKER_BUILDKIT=1 docker image build \
		--build-arg=CMDLINE='console=tty0 console=ttyS0 debug panic=-1' \
		--output=type=local,dest=build \
		--target=test .

	cp --preserve build/boot/*.efi kernel
	cp --preserve build/boot/ld-* .
	# cp --preserve build/boot/ld-800f12-4 ld
	cp --preserve build/boot/ld-a00f11-1 ld
	cp --preserve build/opt/amdese/share/qemu/OVMF.fd loader
	cp --preserve build/opt/amdese/share/qemu/OVMF.fd nvram
```
