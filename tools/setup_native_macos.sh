#!/bin/sh
# Reproduce the headless native test environment. Requires Xcode CLT, cmake,
# pkg-config, FreeType and zlib. Everything downloaded/built stays under $task_dir.
set -eu
task_dir=${1:-/private/tmp/sceneprogress-tests}
mkdir -p "$task_dir"
task_dir=$(cd "$task_dir" && pwd)
fetch() {
    if [ ! -d "$3/.git" ]; then git clone "$1" "$3"; fi
    git -C "$3" checkout "$2"
}
fetch https://github.com/koreader/koreader.git 79b24c0a3af7ea115f0bae3810855ed6328a1741 "$task_dir/koreader"
git -C "$task_dir/koreader" submodule update --init base
git -C "$task_dir/koreader/base" submodule update --init thirdparty/kpvcrlib/crengine
fetch https://github.com/LuaJIT/LuaJIT.git 2a8e017ef1ece6a95b983ffca073d30609dce7c4 "$task_dir/luajit"
fetch https://github.com/Cyan4973/xxHash.git 680bf463fa1ca0461b9a7c2dab7556e1f54cf4cf "$task_dir/xxhash"
fetch https://github.com/ZimProjects/SRELL.git 04233e350a336553fc368296600bb9aa5636d82b "$task_dir/srell"
MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-14.0} make -C "$task_dir/luajit" -j4
make -C "$task_dir/xxhash" -j4 PREFIX="$task_dir/native" install
mkdir -p "$task_dir/srell-prefix"
if [ ! -e "$task_dir/srell-prefix/include" ]; then ln -s "$task_dir/srell" "$task_dir/srell-prefix/include"; fi
task_pc_path="$task_dir/native/lib/pkgconfig:$(pkg-config --variable pc_path pkg-config)"
PKG_CONFIG_PATH="$task_pc_path" cmake \
    -S "$task_dir/koreader/base/thirdparty/kpvcrlib/crengine" -B "$task_dir/cre-build" \
    -DAUTO=OFF -DFREETYPE=ON -DZLIB=ON -DSRELL=ON -DSRELL_ROOT="$task_dir/srell-prefix" \
    -DANTIWORD=OFF -DCHMLIB=OFF -DBUILD_SHARED_LIBS=OFF
cmake --build "$task_dir/cre-build" -j4
# Intentional word splitting for compiler flags emitted by pkg-config.
# shellcheck disable=SC2046
c++ -std=c++17 -shared -fPIC -I"$task_dir/luajit/src" -I"$task_dir/koreader/base" \
    -I"$task_dir/koreader/base/thirdparty/kpvcrlib/crengine/crengine/include" -I"$task_dir/cre-build" \
    $(pkg-config --cflags freetype2 zlib) "$task_dir/koreader/base/cre.cpp" \
    "$task_dir/cre-build/libcrengine.a" "$task_dir/native/lib/libxxhash.a" \
    $(pkg-config --libs freetype2 zlib) -L"$task_dir/luajit/src" -lluajit -o "$task_dir/native/cre.so"
install_name_tool -change /usr/local/lib/libluajit-5.1.2.dylib "$task_dir/luajit/src/libluajit.so" "$task_dir/native/cre.so"
printf 'Native test environment: %s\n' "$task_dir"
