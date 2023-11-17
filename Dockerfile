# syntax=docker/dockerfile:1

FROM ubuntu:22.04 as linux

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	apt-get update && \
	apt-get install --assume-yes --no-install-recommends \
		bc \
		bison \
		build-essential \
		ca-certificates \
		cpio \
		debhelper \
		flex \
		git \
		libelf-dev \
		libssl-dev \
		linux-image-oem-22.04d \
		rsync \
		zstd

# XXX: CONFIG_MODULE_SIG_ALL is not touched in AMDESE repo

RUN git clone --branch=snp-host-latest --depth=1 https://github.com/AMDESE/linux.git && \
	cd linux && \
	cp /boot/config-* .config && \
	./scripts/config --disable AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT && \
	./scripts/config --disable CONFIG_MODULE_SIG_ALL && \
	./scripts/config --disable DEBUG_PREEMPT && \
	./scripts/config --disable IOMMU_DEFAULT_PASSTHROUGH && \
	./scripts/config --disable LOCALVERSION_AUTO && \
	./scripts/config --disable MODULE_SIG_KEY && \
	./scripts/config --disable PREEMPT_COUNT && \
	./scripts/config --disable PREEMPT_DYNAMIC && \
	./scripts/config --disable PREEMPTION && \
	./scripts/config --disable SYSTEM_REVOCATION_KEYS && \
	./scripts/config --disable SYSTEM_TRUSTED_KEYS && \
	./scripts/config --disable UBSAN && \
	./scripts/config --enable AMD_MEM_ENCRYPT && \
	./scripts/config --enable CGROUP_MISC && \
	./scripts/config --enable DEBUG_INFO && \
	./scripts/config --enable DEBUG_INFO_REDUCED && \
	./scripts/config --enable EXPERT && \
	./scripts/config --enable KVM_AMD_SEV && \
	./scripts/config --module CRYPTO_DEV_CCP_DD && \
	./scripts/config --module SEV_GUEST && \
	./scripts/config --module X86_CPUID && \
	./scripts/config --set-str LOCALVERSION "-amdese-$(git describe --always)" && \
	make --jobs="$(nproc)" bindeb-pkg

FROM ubuntu:22.04 as ovmf

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	apt-get update && \
	apt-get install --assume-yes --no-install-recommends \
		acpica-tools \
		build-essential \
		ca-certificates \
		git \
		nasm \
		python-is-python3 \
		uuid-dev

SHELL ["/usr/bin/bash", "-c"]

RUN git clone --branch=snp-latest --depth=1 --recurse-submodules --shallow-submodules https://github.com/AMDESE/ovmf.git && cd ovmf && make --directory=BaseTools --jobs="$(nproc)" && touch OvmfPkg/AmdSev/Grub/grub.efi && . ./edksetup.sh && build --arch=X64 --platform=OvmfPkg/AmdSev/AmdSevX64.dsc --tagname=GCC5

FROM ubuntu:22.04 as qemu

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	apt-get update && \
	apt-get install --assume-yes --no-install-recommends \
		build-essential \
		ca-certificates \
		git \
		libglib2.0-dev \
		libpixman-1-dev \
		libslirp-dev \
		ninja-build \
		pkg-config

RUN git clone --branch=snp-latest --depth=1 https://github.com/AMDESE/qemu.git && cd qemu && ./configure --enable-slirp --enable-trace-backends=log --prefix=/opt/amdese --target-list=x86_64-softmmu && make --jobs="$(nproc)" install

FROM ubuntu:22.04 as boot-test

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	apt-get update && \
	apt-get install --assume-yes --no-install-recommends \
		build-essential \
		initramfs-tools \
		isc-dhcp-client \
		netbase \
		python3-pefile \
		python3-pip \
		systemd \
		wget && \
	pip install sev-snp-measure && \
	wget --output-document=/usr/local/bin/ukify https://raw.githubusercontent.com/systemd/systemd/main/src/ukify/ukify.py && chmod +x /usr/local/bin/ukify && \
	wget https://go.dev/dl/go1.21.3.linux-amd64.tar.gz && tar --directory=/usr/local --extract --file=go1.21.3.linux-amd64.tar.gz

COPY --from=linux --link /*.deb .

RUN dpkg --install *.deb

COPY --from=ovmf --link /ovmf/Build/AmdSev/DEBUG_GCC5/FV/OVMF.fd .

COPY --link examples examples

COPY --link go.* .

COPY --link profiles profiles

ARG CMDLINE

RUN CGO_ENABLED=0 /usr/local/go/bin/go build -ldflags='-s -w' -tags=dev,sev -trimpath ./profiles/test/guest-cli && install -D guest-cli /usr/lib/initramfs-tools/bin/guest-cli && \
	cp --recursive profiles/test/initramfs-tools/* /usr/share/initramfs-tools/ && \
	update-initramfs -ck all && \
	ukify --cmdline="${CMDLINE} boot=test" /boot/vmlinuz-* /boot/initrd.img-* && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0x800f12 --vcpus=1 > ld-800f12-1 && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0x800f12 --vcpus=2 > ld-800f12-2 && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0x800f12 --vcpus=3 > ld-800f12-3 && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0x800f12 --vcpus=4 > ld-800f12-4 && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0xa00f11 --vcpus=1 > ld-a00f11-1 && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0xa00f11 --vcpus=2 > ld-a00f11-2 && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0xa00f11 --vcpus=3 > ld-a00f11-3 && \
	sev-snp-measure --kernel *.efi --mode=snp --ovmf=OVMF.fd --vcpu-sig=0xa00f11 --vcpus=4 > ld-a00f11-4

FROM scratch as test

COPY --from=boot-test --link /*.efi /boot /ld-* /boot/

COPY --from=linux --link /*.buildinfo /*.changes /*.deb /linux/

COPY --from=ovmf --link /ovmf/Build/AmdSev/DEBUG_GCC5/FV/OVMF.fd /opt/amdese/share/qemu/

COPY --from=qemu --link /opt/amdese /opt/amdese
