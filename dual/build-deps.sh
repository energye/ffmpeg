#!/bin/sh
# 双版本外库静态编译（在构建镜像里跑一遍，产物 /opt/<name>-<arch>）。
# 用法：build-deps.sh [x64|arm64|386|arm|w64|all]
# 全静态（no-shared + -fPIC），只产 .a，不欠动态账。
# 许可：freetype(FTL/GPL二选一，取FTL)+harfbuzz(MIT)+fontconfig(MIT)+
# fribidi(LGPL)+libass(ISC)+openh264(BSD)+openssl(Apache-2)+zlib(zlib)，
# 和 LGPL 2.1 拼盘没问题；x264/x265/fdk 不在此装。
set -e
WHICH="${1:-x64}"
SRC=/tmp/deps
mkdir -p "$SRC"
cd "$SRC"

# 各库版本与 Dockerfile ENV 同源（改一处即可，另一处同步）。
FT=${FREETYPE_VER:-2.13.2}
HB=${HARFBUZZ_VER:-8.3.0}
FB=${FRIBIDI_VER:-1.0.13}
FC=${FONTCONFIG_VER:-2.15.0}
ASS=${LIBASS_VER:-0.17.1}
H264=${OPENH264_VER:-2.4.1}
OSSL=${OPENSSL_VER:-3.0.16}
ZL=${ZLIB_VER:-1.3.1}
EXPAT=${EXPAT_VER:-2.6.4}

need() { # file url [fallback-url]
  if [ -f "$1" ]; then return 0; fi
  # -f：HTTP 错误直接失败（不把 404 页面存成包）；下完先验包，
  # 主源是坏包就换备用源重下（实测 zlib.net 回的不是 gzip）。
  if curl -fSL --retry 3 --retry-all-errors --max-time 120 -o "$1" "$2" && verify "$1" 2>/dev/null; then
    return 0
  fi
  echo "primary bad for $1, trying fallback" >&2
  rm -f "$1"
  if [ -n "$3" ]; then
    curl -fSL --retry 3 --retry-all-errors --max-time 180 -o "$1" "$3" && verify "$1"
  else
    return 1
  fi
}
verify() { # file : list fully or fail
  case "$1" in
    *.tar.xz) tar tJf "$1" >/dev/null ;;
    *) tar tzf "$1" >/dev/null ;;
  esac
}
need freetype-$FT.tar.gz "https://download.savannah.gnu.org/releases/freetype/freetype-$FT.tar.gz" \
  "https://download-mirror.savannah.gnu.org/releases/freetype/freetype-$FT.tar.gz"
need harfbuzz-$HB.tar.xz "https://github.com/harfbuzz/harfbuzz/releases/download/$HB/harfbuzz-$HB.tar.xz"
need fribidi-$FB.tar.xz "https://github.com/fribidi/fribidi/releases/download/v$FB/fribidi-$FB.tar.xz" \
  "https://download-mirror.savannah.gnu.org/releases/fribidi/fribidi-$FB.tar.xz"
need fontconfig-$FC.tar.gz "https://www.freedesktop.org/software/fontconfig/release/fontconfig-$FC.tar.gz" \
  "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$FC/fontconfig-$FC.tar.gz"
need libass-$ASS.tar.gz "https://github.com/libass/libass/releases/download/$ASS/libass-$ASS.tar.gz"
need openh264-$H264.tar.gz "https://github.com/cisco/openh264/archive/refs/tags/v$H264.tar.gz"
need openssl-$OSSL.tar.gz "https://www.openssl.org/source/openssl-$OSSL.tar.gz" \
  "https://github.com/openssl/openssl/releases/download/openssl-$OSSL/openssl-$OSSL.tar.gz"
need zlib-$ZL.tar.gz "https://github.com/madler/zlib/releases/download/v$ZL/zlib-$ZL.tar.gz" \
  "https://zlib.net/zlib-$ZL.tar.gz"
need expat-$EXPAT.tar.gz "https://github.com/libexpat/libexpat/releases/download/R_2_6_4/expat-$EXPAT.tar.gz"
# 完整性门禁：坏包直接报错，不让半截包混进编译。
for f in freetype-$FT.tar.gz harfbuzz-$HB.tar.xz fribidi-$FB.tar.xz fontconfig-$FC.tar.gz libass-$ASS.tar.gz openh264-$H264.tar.gz openssl-$OSSL.tar.gz zlib-$ZL.tar.gz expat-$EXPAT.tar.gz; do
  verify "$f" || { echo "BAD TARBALL $f，删掉重下" >&2; rm -f "$f"; exit 3; }
done

build_one_arch() { # arch-tag cc cxx
  TAG="$1"; CC="$2"; CXX="$3"
  PF=/opt
  # zlib（静态，各目标一份）。
  rm -rf zl-$TAG && mkdir zl-$TAG && tar -xzf zlib-$ZL.tar.gz -C zl-$TAG --strip-components=1
  case "$TAG" in
    x64) ZCROSS="" ;;
    arm64) ZCROSS="aarch64-linux-gnu-" ;;
    386) ZCROSS="" ;;
    arm) ZCROSS="arm-linux-gnueabihf-" ;;
    w64) ZCROSS="x86_64-w64-mingw32-" ;;
    w64arm) ZCROSS="aarch64-w64-mingw32-" ;;
  esac
  (cd zl-$TAG && CC="$CC" CFLAGS="-fPIC" ./configure --static --prefix=$PF/zlib-$TAG && make -j"$(nproc)" CC="$CC" AR="${ZCROSS}ar" RANLIB="${ZCROSS}ranlib" && make install && ${ZCROSS}ranlib $PF/zlib-$TAG/lib/libz.a)
  # openssl（静态；w64/w64arm 走系统 schannel，不编）。
  # 386 用宿主 gcc -m32，内核头靠镜像里 /usr/include/i386-linux-gnu/asm
  # 软链接顶上（见 Dockerfile），apps 照常编，不用跳过。
  if [ "$TAG" != "w64" ] && [ "$TAG" != "w64arm" ]; then
    rm -rf ossl-$TAG && mkdir ossl-$TAG && tar -xzf openssl-$OSSL.tar.gz -C ossl-$TAG --strip-components=1
    case "$TAG" in
      x64) OSSL_TGT="linux-x86_64" OSSL_PFX="" ;;
      arm64) OSSL_TGT="linux-aarch64" OSSL_PFX="--cross-compile-prefix=aarch64-linux-gnu-" ;;
      386) OSSL_TGT="linux-x86" OSSL_PFX="" ;;
      arm) OSSL_TGT="linux-armv4" OSSL_PFX="--cross-compile-prefix=arm-linux-gnueabihf-" ;;
    esac
    # openssl 的 Configure 自己管 CC：$OSSL_PFX 里带了交叉前缀，
    # 这里只递前缀不递 "CC=xxx"（递了它会把 CC 当编译器名拼错成
    # "aarch64-linux-gnu-aarch64-linux-gnu-gcc"）。
    # make 时再显式给 CC/AR（Configure 生成的 Makefile 默认 CC=cc，交叉要盖掉）。
    case "$TAG" in
      x64) OSSL_MAKE_CC="gcc" ;;
      386) OSSL_MAKE_CC="gcc -m32" ;;
      *) OSSL_MAKE_CC="$CC" ;;
    esac
    (cd ossl-$TAG && perl ./Configure --prefix=$PF/ossl-$TAG no-shared -fPIC no-tests $OSSL_TGT $OSSL_PFX && make -j"$(nproc)" CC="$OSSL_MAKE_CC" AR="${OSSL_PFX#--cross-compile-prefix=}ar" RANLIB="${OSSL_PFX#--cross-compile-prefix=}ranlib" && make install_sw)
  fi
  # 全架构统一走完整静态链（含 w64/w64arm 的 Windows 烧字链，
  # 与 linux/mac 对齐；openssl 只在 linux 编，win 走系统 schannel）。
  # freetype（静态，harfbuzz 关，免循环依赖）。
  # 交叉要递 --host（autoconf 不认 CC 前缀，得明说目标三元组，否则它拿
  # 交叉编的 apinames 去本机跑，直接 Error 77）。
  case "$TAG" in
    x64) FT_HOST="" ;; arm64) FT_HOST="--host=aarch64-linux-gnu" ;;
    386) FT_HOST="--host=i686-linux-gnu" ;; arm) FT_HOST="--host=arm-linux-gnueabihf" ;;
    w64) FT_HOST="--host=x86_64-w64-mingw32" ;;
    w64arm) FT_HOST="--host=aarch64-w64-mingw32" ;;
  esac
  rm -rf ft-$TAG && mkdir ft-$TAG && tar -xzf freetype-$FT.tar.gz -C ft-$TAG --strip-components=1
  # mingw 下没有系统 zlib 头，freetype 的 gzip 模块要指到自建 zlib-$TAG
  # （linux 靠镜像里 zlib1g-dev 顶着，不用加）。
  case "$TAG" in
    w64|w64arm) FT_EXTRA_CFLAGS="-I$PF/zlib-$TAG/include"; FT_EXTRA_LDFLAGS="-L$PF/zlib-$TAG/lib" ;;
    *) FT_EXTRA_CFLAGS=""; FT_EXTRA_LDFLAGS="" ;;
  esac
  (cd ft-$TAG && CC="$CC" CFLAGS="-fPIC $FT_EXTRA_CFLAGS" LDFLAGS="$FT_EXTRA_LDFLAGS" ./configure $FT_HOST --disable-shared --enable-static --without-harfbuzz --without-bzip2 --without-png --prefix=$PF/freetype-$TAG && make -j"$(nproc)" && make install)
  # expat（静态，fontconfig 的 XML 解析依赖，MIT 许可；交叉递 --host 同上）。
  rm -rf ex-$TAG && mkdir ex-$TAG && tar -xzf expat-$EXPAT.tar.gz -C ex-$TAG --strip-components=1
  (cd ex-$TAG && CC="$CC" CFLAGS="-fPIC" ./configure $FT_HOST --disable-shared --enable-static --without-examples --without-tests --without-docbook --prefix=$PF/expat-$TAG && make -j"$(nproc)" && make install)
  # harfbuzz（静态，指向上一步的 freetype；--libdir=lib 钉死，
  # meson 在 Debian 系默认装 lib/<arch>/ 下，.pc 会找不到）。
  # 交叉用 --cross-file（meson 不认 CC 前缀，得明说目标机，否则
  # "Executables created by c compiler are not runnable"）。
  meson_cross=""
  case "$TAG" in
    x64) ;;
    arm64) cat > /tmp/meson-cross-arm64.ini <<'EOF'
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkgconfig = 'pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
      meson_cross="--cross-file /tmp/meson-cross-arm64.ini" ;;
    arm) cat > /tmp/meson-cross-arm.ini <<'EOF'
[binaries]
c = 'arm-linux-gnueabihf-gcc'
cpp = 'arm-linux-gnueabihf-g++'
ar = 'arm-linux-gnueabihf-ar'
strip = 'arm-linux-gnueabihf-strip'
pkgconfig = 'pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOF
      meson_cross="--cross-file /tmp/meson-cross-arm.ini" ;;
    386) cat > /tmp/meson-cross-386.ini <<'EOF'
[binaries]
c = 'gcc'
cpp = 'g++'
ar = 'ar'
strip = 'strip'
pkgconfig = 'pkg-config'
[properties]
c_args = ['-m32', '-fPIC']
c_link_args = ['-m32']
cpp_args = ['-m32', '-fPIC']
cpp_link_args = ['-m32']
[host_machine]
system = 'linux'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'
EOF
      meson_cross="--cross-file /tmp/meson-cross-386.ini" ;;
    w64) cat > /tmp/meson-cross-w64.ini <<'EOF'
[binaries]
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
pkgconfig = 'pkg-config'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
      meson_cross="--cross-file /tmp/meson-cross-w64.ini" ;;
    w64arm) cat > /tmp/meson-cross-w64arm.ini <<'EOF'
[binaries]
c = 'aarch64-w64-mingw32-clang'
cpp = 'aarch64-w64-mingw32-clang++'
ar = 'aarch64-w64-mingw32-ar'
strip = 'aarch64-w64-mingw32-strip'
pkgconfig = 'pkg-config'
[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
      meson_cross="--cross-file /tmp/meson-cross-w64arm.ini" ;;
  esac
  # 386 的 meson 交叉：c_args 加 -m32（cross 文件里写死了 gcc，得补旗标）。
  case "$TAG" in
    386) MESON_CFLAGS="-fPIC -m32" MESON_CXXFLAGS="-fPIC -m32" ;;
    *) MESON_CFLAGS="-fPIC" MESON_CXXFLAGS="-fPIC" ;;
  esac
  rm -rf hb-$TAG && mkdir hb-$TAG && tar -xJf harfbuzz-$HB.tar.xz -C hb-$TAG --strip-components=1
  # 测试/工具/文档二进制不编：交叉下它们链宿主 libz.so（x86_64）直接炸（实测 386/arm64/arm 全挂
  # 在 test-vector 链接上），且我们只要静态库，跳过省时省事。x64 同步关，行为一致。
  (cd hb-$TAG && CC="$CC" CXX="$CXX" CFLAGS="$MESON_CFLAGS" CXXFLAGS="$MESON_CXXFLAGS" PKG_CONFIG_PATH=$PF/freetype-$TAG/lib/pkgconfig:$PF/zlib-$TAG/lib/pkgconfig meson setup $meson_cross -Dtests=disabled -Dutilities=disabled -Ddocs=disabled -Dicu=disabled --default-library=static --libdir=lib --prefix=$PF/harfbuzz-$TAG build && ninja -C build && ninja -C build install)
  # fribidi + fontconfig + libass（静态；fribidi 同样钉 --libdir=lib）。
  rm -rf fb-$TAG && mkdir fb-$TAG && tar -xJf fribidi-$FB.tar.xz -C fb-$TAG --strip-components=1
  (cd fb-$TAG && CC="$CC" CFLAGS="$MESON_CFLAGS" meson setup $meson_cross -Dtests=false -Ddocs=false -Dbin=false --default-library=static --libdir=lib --prefix=$PF/fribidi-$TAG build && ninja -C build && ninja -C build install)
  rm -rf fc-$TAG && mkdir fc-$TAG && tar -xzf fontconfig-$FC.tar.gz -C fc-$TAG --strip-components=1
  # LDFLAGS 指到自建 zlib-$TAG：fc-cache 等工具二进制要链 -lz，交叉目标（386/arm64/arm）
  # 在宿主 /usr/lib 下只有 x86_64 的 libz 会炸（实测 386 挂在 fc-cache 链接上），库本身不欠账。
  (cd fc-$TAG && CC="$CC" CFLAGS="-fPIC" LDFLAGS="-L$PF/zlib-$TAG/lib" PKG_CONFIG_PATH=$PF/freetype-$TAG/lib/pkgconfig:$PF/fribidi-$TAG/lib/pkgconfig:$PF/expat-$TAG/lib/pkgconfig:$PF/zlib-$TAG/lib/pkgconfig ./configure $FT_HOST --disable-shared --enable-static --disable-docs --disable-libxml2 --with-expat=$PF/expat-$TAG --prefix=$PF/fontconfig-$TAG && make -j"$(nproc)" && make install)
  rm -rf as-$TAG && mkdir as-$TAG && tar -xzf libass-$ASS.tar.gz -C as-$TAG --strip-components=1
  # fontconfig 开着（系统字体查找要它；静态 .a 上一步已备好，不欠动态账）。
  # 交叉同样递 --host（libass 的 configure 也要明说）。
  (cd as-$TAG && CC="$CC" CFLAGS="-fPIC" PKG_CONFIG_PATH=$PF/freetype-$TAG/lib/pkgconfig:$PF/harfbuzz-$TAG/lib/pkgconfig:$PF/fribidi-$TAG/lib/pkgconfig:$PF/fontconfig-$TAG/lib/pkgconfig:$PF/expat-$TAG/lib/pkgconfig:$PF/zlib-$TAG/lib/pkgconfig ./configure $FT_HOST --disable-shared --enable-static --prefix=$PF/ass-$TAG && make -j"$(nproc)" && make install)
  # openh264（静态；install 会顺带装 .so，删掉只留 .a，免得后人误链动态）。
  # 注意：install 也要带同一套 CC/CXX/ARCH/USE_ASM——它的依赖会触发二次构建，
  # 不带就是本机默认（64 位+开汇编），会把刚编好的 32 位 .o 混成 64 位再链，
  # 直接炸（实测 386 挂在 libopenh264.so.2.4.1 的 -m64 重链上）。
  # Windows（w64/w64arm）：宿主 uname 是 linux，openh264 按 linux 规则
  # 拼动态库链接（-soname，走 lld 不认，直接炸），其实我们只要静态 .a。
  # 先只编静态库装上（install-static-lib+头+静态版 .pc），跳过动态那半。
  rm -rf h264-$TAG && mkdir h264-$TAG && tar -xzf openh264-$H264.tar.gz -C h264-$TAG --strip-components=1
  case "$TAG" in
    w64|w64arm)
      (cd h264-$TAG && make CC="$CC" CXX="$CXX" ARCH=$(arch_map "$TAG") USE_ASM=No -j"$(nproc)" libopenh264.a && make CC="$CC" CXX="$CXX" ARCH=$(arch_map "$TAG") USE_ASM=No PREFIX=$PF/openh264-$TAG install-static-lib && make CC="$CC" CXX="$CXX" ARCH=$(arch_map "$TAG") USE_ASM=No PREFIX=$PF/openh264-$TAG openh264-static.pc && mkdir -p $PF/openh264-$TAG/lib/pkgconfig && cp -f openh264-static.pc $PF/openh264-$TAG/lib/pkgconfig/openh264.pc)
      ;;
    *)
      (cd h264-$TAG && make CC="$CC" CXX="$CXX" ARCH=$(arch_map "$TAG") USE_ASM=No -j"$(nproc)" && make CC="$CC" CXX="$CXX" ARCH=$(arch_map "$TAG") USE_ASM=No PREFIX=$PF/openh264-$TAG install && rm -f $PF/openh264-$TAG/lib/libopenh264.so*)
      ;;
  esac
}

arch_map() {
  case "$1" in
    x64|w64) echo x86_64 ;; arm64|w64arm) echo aarch64 ;; 386) echo i386 ;; arm) echo arm ;;
  esac
}

case "$WHICH" in
  need-only) echo "need-only done (tarballs verified above)" ;;
  x64) build_one_arch x64 gcc g++ ;;
  arm64) build_one_arch arm64 aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ ;;
  386) build_one_arch 386 "gcc -m32" "g++ -m32" ;;
  arm) build_one_arch arm arm-linux-gnueabihf-gcc arm-linux-gnueabihf-g++ ;;
  w64) build_one_arch w64 x86_64-w64-mingw32-gcc x86_64-w64-mingw32-g++ ;;
  w64arm) build_one_arch w64arm aarch64-w64-mingw32-clang "aarch64-w64-mingw32-clang++" ;;
  all) for a in x64 arm64 386 arm w64 w64arm; do "$0" "$a"; done ;;
  *) echo "unknown $WHICH" >&2; exit 2 ;;
esac
echo "deps $WHICH done"
