#!/bin/bash
# Build mainline Linux 7.3 (7.3.0-tsv) for Lenovo ThinkSmart View CD-18781Y
#   Base: msm8953-mainline barni2000/7.3/develop @ 755ffc44d5d8442adeec8bbaa02108478089c4d7
#   Patches: kernel/patches/0001..0909 (43 patches total)
set -euo pipefail

export PATH=/usr/lib/llvm-19/bin:$PATH
HERE=$(cd "$(dirname "$0")" && pwd)
BASE_COMMIT=755ffc44d5d8442adeec8bbaa02108478089c4d7
TARBALL=${TARBALL:-$HERE/linux-7.3.tar.gz}
SRC=${SRC:-$HERE/linux-7.3}
OUT=${OUT:-$HERE/build-7.3}
STAGE=${STAGE:-$HERE/stage}
JOBS=${JOBS:-$(nproc)}

if [ ! -d "$SRC" ]; then
	if [ ! -f "$TARBALL" ]; then
		echo "== Fetching msm8953-mainline Linux 7.3 ($BASE_COMMIT)"
		curl -fL --retry 3 -o "$TARBALL.part" \
			"https://codeload.github.com/msm8953-mainline/linux/tar.gz/$BASE_COMMIT"
		mv "$TARBALL.part" "$TARBALL"
	fi
	echo "== Extracting $TARBALL"
	tar xzf "$TARBALL" -C "$HERE"
	mv "$HERE/linux-$BASE_COMMIT" "$SRC"
	rm -f "$OUT/.patched"
fi

K="make -C $SRC O=$OUT ARCH=arm64 LLVM=1 -j$JOBS"

if [ ! -e "$OUT/.patched" ]; then
	echo "== Applying $(ls -1 "$HERE/patches"/*.patch | wc -l) kernel patches"
	for p in $(ls -1 "$HERE/patches"/*.patch | sort); do
		git -C "$SRC" apply --whitespace=nowarn "$p" || {
			echo "PATCH FAILED: $p" >&2
			exit 1
		}
		echo "   applied $(basename "$p")"
	done

	echo "== Configuring kernel"
	cp "$HERE/config/lenovo-cd-18781y.config" \
	   "$SRC/arch/arm64/configs/lenovo-cd-18781y.config"
	mkdir -p "$OUT"
	$K defconfig msm8953.config no-unused-drivers.config lenovo-cd-18781y.config
	sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-tsv"/' "$OUT/.config"
	sed -i 's/^CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/' "$OUT/.config"
	$K olddefconfig
	touch "$OUT/.patched"
fi

echo "== Building Image.gz, dtbs, and modules"
$K Image.gz dtbs modules

echo "== Staging stripped modules"
rm -rf "$STAGE"
$K INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install
VER=$(cat "$OUT/include/config/kernel.release")
rm -f "$STAGE/lib/modules/$VER/build" "$STAGE/lib/modules/$VER/source"
tar -C "$STAGE/lib/modules" -cf "$STAGE/modules.tar" "$VER"

echo "== Build complete ($VER)"
ls -lh "$OUT/arch/arm64/boot/Image.gz" \
       "$OUT/arch/arm64/boot/dts/qcom/apq8053-lenovo-cd-18781y.dtb" \
       "$STAGE/modules.tar"
