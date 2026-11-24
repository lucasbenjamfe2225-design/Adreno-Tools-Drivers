#!/usr/bin/env bash
set -euo pipefail

green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$REPO_ROOT/turnip_workdir"
NDKVER="android-ndk-r29"
NDK="$WORKDIR/$NDKVER/toolchains/llvm/prebuilt/linux-x86_64/bin"
BUILD_VERSION="${BUILD_VERSION:-2.0-Remaster}"
VARIANT="${VARIANT:-a650}"
MESA_COMMIT="${MESA_COMMIT:-22c08cc53bd0}"
# Prueba opcional (un cambio por vez): A650_NO_VK_MEMORY_MODEL=1
A650_NO_VK_MEMORY_MODEL="${A650_NO_VK_MEMORY_MODEL:-0}"

REVERT_COMMIT="a70d2af590db192f87b3af01f83a68b450edb4c3"

log() { echo -e "${green}$*${nocolor}"; }
die() { echo -e "${red}$*${nocolor}" >&2; exit 1; }

check_deps() {
    local deps="git meson ninja patchelf unzip curl pip flex bison zip glslangValidator python3 patch"
    for dep in $deps; do
        command -v "$dep" >/dev/null 2>&1 || die "Falta la dependencia: $dep"
    done
    pip install mako --break-system-packages >/dev/null 2>&1 || true
}

prepare_workdir() {
    mkdir -p "$WORKDIR"
    if [ ! -d "$WORKDIR/$NDKVER" ]; then
        log "Descargando Android NDK r29..."
        curl -fsSL "https://dl.google.com/android/repository/${NDKVER}-linux.zip" -o "$WORKDIR/${NDKVER}-linux.zip"
        unzip -q "$WORKDIR/${NDKVER}-linux.zip" -d "$WORKDIR"
    fi

    rm -rf "$WORKDIR/mesa"
    mkdir -p "$WORKDIR/mesa"
    git -C "$WORKDIR/mesa" init -q
    git -C "$WORKDIR/mesa" remote add origin https://gitlab.freedesktop.org/mesa/mesa.git

    if [ -z "$MESA_COMMIT" ]; then
        log "Obteniendo Mesa main (no fijado)..."
        git -C "$WORKDIR/mesa" fetch -q --depth=1 origin refs/heads/main
        git -C "$WORKDIR/mesa" checkout -q --detach FETCH_HEAD
    elif [ "${#MESA_COMMIT}" -eq 40 ]; then
        log "Obteniendo Mesa fijado en $MESA_COMMIT..."
        git -C "$WORKDIR/mesa" fetch -q --depth=1 origin "$MESA_COMMIT"
        git -C "$WORKDIR/mesa" checkout -q --detach FETCH_HEAD
    else
        log "Hash corto ($MESA_COMMIT): bajando historial de main sin archivos para resolverlo..."
        git -C "$WORKDIR/mesa" fetch -q --filter=blob:none origin refs/heads/main
        git -C "$WORKDIR/mesa" checkout -q --detach "$MESA_COMMIT" \
            || die "No encontre $MESA_COMMIT en main. Usa el hash completo de 40 caracteres."
    fi
}

revert_d32s8_commit() {
    log "A7xx: revirtiendo workaround D32S8 EARLY_Z_LATE_Z..."
    if ! git cat-file -e "${REVERT_COMMIT}^{commit}" 2>/dev/null; then
        git fetch -q --depth=2 origin "$REVERT_COMMIT"
    fi
    git revert --no-commit "$REVERT_COMMIT" || {
        git revert --abort 2>/dev/null || true
        git reset --hard HEAD
        die "Fallo al revertir $REVERT_COMMIT"
    }
}

apply_a650_base() {
    log "Adreno 650: fix D32S8 intacto, sin parches de a7xx."
    if [ "$A650_NO_VK_MEMORY_MODEL" = "1" ]; then
        log "Prueba: has_vk_memory_model = false"
        sed -i 's/bool has_vk_memory_model = true;/bool has_vk_memory_model = false;/g' src/freedreno/vulkan/tu_device.cc
    fi
    grep -n "has_vk_memory_model" src/freedreno/vulkan/tu_device.cc || true
}

apply_a7xx_base() {
    revert_d32s8_commit
    if ! grep -A20 'a7xx_gen1 = GPUProps(' src/freedreno/common/freedreno_devices.py | grep -q 'has_early_preamble = False'; then
        sed -i '/a7xx_gen1 = GPUProps(/a \\        has_early_preamble = False,' src/freedreno/common/freedreno_devices.py
    fi
    python3 -m py_compile src/freedreno/common/freedreno_devices.py
}

apply_oneui_glitch() {
    patch -p1 --forward < "$REPO_ROOT/8g2_ui_glitch.patch"
}

verify_mesa_mr_44838() {
    local kgsl="src/freedreno/vulkan/tu_knl_kgsl.cc"
    [ -f "$kgsl" ] || die "Falta $kgsl"
    grep -Fq 'kgsl_syncobj_merge(struct tu_device *device' "$kgsl" || die "Mesa no tiene fix 1da50a1b"
    grep -Fq 'return kgsl_poll_timestamp(device, context_id, timestamp);' "$kgsl" || die "Mesa no tiene fix e984ef29"
}

apply_android_ndk_fixes() {
    sed -i 's/typedef const native_handle_t\* buffer_handle_t;/typedef void* buffer_handle_t;/g' include/android_stub/cutils/native_handle.h || true
    sed -i 's/, hnd->handle/, (void *)hnd->handle/g' src/util/u_gralloc/u_gralloc_fallback.c || true
    sed -i -E 's/([a-z_]+)->handle->/((const native_handle_t *)\1->handle)->/g' src/vulkan/runtime/vk_android.c || true
    sed -i 's/anb->handle->/((const native_handle_t *)anb->handle)->/g' src/vulkan/runtime/vk_android.c || true
    sed -i "/-Werror=gnu-empty-initializer/d" meson.build || true
}

clean_turnip_driver_names() {
    find src/freedreno/vulkan -type f -name "*.c*" -exec sed -i 's/"Turnip Adreno (TM) %s[^"]*"/"Turnip Adreno (TM) %s%.0s"/g' {} + || true
    find src/freedreno/vulkan -type f -name "*.c*" -exec sed -i 's/"turnip Mesa driver (whitebelyash branch)"/"Turnip"/g' {} + || true
    find src/freedreno/vulkan -type f -name "*.c*" -exec sed -i 's/"turnip Mesa driver"/"Turnip"/g' {} + || true
}

configure_variant() {
    case "$VARIANT" in
        a650) apply_a650_base; clean_turnip_driver_names ;;
        a7xx) apply_a7xx_base; clean_turnip_driver_names ;;
        a7xx-oneui) apply_a7xx_base; apply_oneui_glitch; clean_turnip_driver_names ;;
        *) die "VARIANT invalido: $VARIANT" ;;
    esac
}

build_android() {
    local cver=36
    [ -f "$NDK/aarch64-linux-android${cver}-clang" ] || cver=35
    [ -f "$NDK/aarch64-linux-android${cver}-clang" ] || cver=34
    [ -f "$NDK/aarch64-linux-android${cver}-clang" ] || die "Clang Android aarch64 no encontrado"

    mkdir -p "$WORKDIR/bin"
    ln -sf "$NDK/clang" "$WORKDIR/bin/cc"
    ln -sf "$NDK/clang++" "$WORKDIR/bin/c++"
    export PATH="$WORKDIR/bin:$NDK:$PATH"
    export CC=clang CXX=clang++ AR=llvm-ar RANLIB=llvm-ranlib STRIP=llvm-strip OBJDUMP=llvm-objdump OBJCOPY=llvm-objcopy
    export LDFLAGS="-fuse-ld=lld"

    cat > android-aarch64.txt <<EOF
[binaries]
ar = '$NDK/llvm-ar'
c = ['$NDK/aarch64-linux-android${cver}-clang']
cpp = ['$NDK/aarch64-linux-android${cver}-clang++']
c_ld = '$NDK/ld.lld'
cpp_ld = '$NDK/ld.lld'
strip = '$NDK/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$NDK/pkg-config', '/usr/bin/pkg-config']

[built-in options]
c_args = ['-D__ANDROID__', '-mcpu=cortex-a77', '-O3', '-Wno-error', '-Wno-error=gnu-empty-initializer', '-Wno-gnu-empty-initializer', '-Wno-deprecated-declarations', '-Wno-incompatible-pointer-types-discards-qualifiers', '-Wno-incompatible-pointer-types']
cpp_args = ['-D__ANDROID__', '-mcpu=cortex-a77', '-O3', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-Wno-error', '-Wno-error=gnu-empty-initializer', '-Wno-gnu-empty-initializer', '-Wno-deprecated-declarations', '-Wno-incompatible-pointer-types-discards-qualifiers', '-Wno-incompatible-pointer-types']
cpp_link_args = ['--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

    cat > native.txt <<EOF
[build_machine]
c = ['clang']
cpp = ['clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

    local build_dir="build-android-aarch64"
    local output_dir="/tmp/turnip-$VARIANT"
    rm -rf "$build_dir" "$output_dir"

    meson setup "$build_dir" --cross-file android-aarch64.txt --native-file native.txt \
        --prefix "$output_dir" -Dbuildtype=release -Db_ndebug=true -Dstrip=true \
        -Dplatforms=android -Dvideo-codecs= -Dplatform-sdk-version=${cver} \
        -Dandroid-stub=true -Dgallium-drivers= -Dvulkan-drivers=freedreno \
        -Dvulkan-beta=true -Dfreedreno-kmds=kgsl -Degl=disabled \
        -Dandroid-libbacktrace=disabled

    ninja -C "$build_dir" install
    [ -f "$output_dir/lib/libvulkan_freedreno.so" ] || die "libvulkan_freedreno.so no fue generada"
}

package_variant() {
    local mesa_short
    mesa_short="$(git rev-parse --short=12 HEAD)"
    local pretty_name desc suffix
    case "$VARIANT" in
        a650) pretty_name="Turnip R28 Adreno 650 Remaster"; desc="Adreno 650 / SD870 (Cortex-A77, KGSL, D32S8 fix intacto) basado en StevenMXZ"; suffix="R28_Adreno650_Remaster" ;;
        a7xx) pretty_name="Turnip A7xx"; desc="StevenMXZ A7xx Android/Bionic"; suffix="A7xx" ;;
        a7xx-oneui) pretty_name="Turnip A7xx OneUI Glitch"; desc="StevenMXZ A7xx + OneUI glitch fix"; suffix="A7xx-OneUI-Glitch" ;;
    esac

    local output_dir="/tmp/turnip-$VARIANT"
    cd "$output_dir/lib"
    cat > meta.json <<EOF
{
  "schemaVersion": 1,
  "name": "$pretty_name",
  "description": "$desc - Mesa $mesa_short",
  "author": "lucasbenjamfe2225 (base: StevenMXZ)",
  "packageVersion": "$BUILD_VERSION",
  "vendor": "Mesa",
  "driverVersion": "Mesa-$mesa_short",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF
    local zip_name="Turnip_${suffix}_${mesa_short}.zip"
    rm -f "$WORKDIR/$zip_name"
    zip -9 -q "$WORKDIR/$zip_name" libvulkan_freedreno.so meta.json
    log "Generado: $WORKDIR/$zip_name"
}

main() {
    check_deps
    prepare_workdir
    cd "$WORKDIR/mesa"
    log "Mesa: $(git rev-parse HEAD)"
    log "Variante: $VARIANT"
    verify_mesa_mr_44838
    configure_variant
    apply_android_ndk_fixes
    build_android
    package_variant
}

main "$@"
