#!/usr/bin/env bash
# 全量重建 CPython 调试构建,并重新生成编译数据库。
#
#   study/scripts/rebuild.sh
#
# 四步:configure → make clean → 在 bear 下全量编译 → 校验产物,整个过程几分钟。
# 每个选项为什么这样设,见 study/00. 编译配置.md。
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="$repo/build"
llvm="$(brew --prefix llvm)"
jobs="$(sysctl -n hw.ncpu)"

die() { echo "失败:$*" >&2; exit 1; }

# shell 里 export 的 CPPFLAGS / LDFLAGS 之类会被 configure 记进 Makefile,
# 编译时 make 还会再读一遍。统一清掉,让构建只受下面写明的参数影响。
clean_env=(env -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS -u LIBS -u OPT
           -u CPATH -u LIBRARY_PATH -u PKG_CONFIG_PATH)

mkdir -p "$build"
cd "$build"

echo "[1/4] configure   (输出在 build/configure.log)"
"${clean_env[@]}" \
    CC="$llvm/bin/clang" \
    PKG_CONFIG_PATH="$(brew --prefix tcl-tk@8)/lib/pkgconfig" \
    GDBM_CFLAGS="-I$(brew --prefix gdbm)/include" \
    GDBM_LIBS="-L$(brew --prefix gdbm)/lib -lgdbm" \
    ../configure \
        --with-pydebug \
        --with-openssl="$(brew --prefix openssl@3.0)" \
        OPT="-g -O0 -Wall" \
    > configure.log 2>&1 || die "configure 出错,见 build/configure.log"

echo "[2/4] make clean"
"${clean_env[@]}" make clean > /dev/null || die "make clean 出错"

# bear 在 macOS 上靠"用自己的包装程序顶替已知名字的编译器"来记录编译命令。
# Makefile 里的 CC 是 configure 写死的绝对路径,包装程序顶替不了,结果是空数据库。
# 所以只在这一次 make 的命令行上把 CC 覆盖成不带路径的 clang,
# 并把 Homebrew LLVM 放到 PATH 最前面,保证解析到的还是同一个编译器。
echo "[3/4] 全量编译    (输出在 build/build.log)"
db_new=compile_commands.new.json
rm -f "$db_new"
"${clean_env[@]}" PATH="$llvm/bin:$PATH" \
    bear --output "$db_new" -- make -j"$jobs" CC=clang > build.log 2>&1 \
    || die "编译出错,见 build/build.log"

echo "[4/4] 校验"

# 编译数据库:确认拦截到了东西再替换,避免把好的数据库覆盖成 []。
n="$(./python -c 'import json, pathlib, sys; print(len(json.loads(pathlib.Path(sys.argv[1]).read_text())))' "$db_new")"
[ "$n" -ge 200 ] || die "编译数据库只有 $n 条(正常 260 条以上),旧的 compile_commands.json 没有动"
mv "$db_new" compile_commands.json

# 解释器版本要和源码一致。
src_ver="$(sed -n 's/^#define PY_VERSION *"\(.*\)"$/\1/p' ../Include/patchlevel.h)"
bin_ver="$(./python -c 'import platform; print(platform.python_version())')"
[ "$src_ver" = "$bin_ver" ] || die "build/python 是 $bin_ver,源码是 $src_ver"

# 确实是零优化的调试构建。
./python -c '
import sys, sysconfig
assert hasattr(sys, "gettotalrefcount"), "不是 Py_DEBUG 构建"
opt = sysconfig.get_config_var("OPT")
assert opt == "-g -O0 -Wall", f"OPT 是 {opt!r}"
' || die "构建配置不对"

# 扩展模块编不出来时 make 照样返回 0,所以把依赖外部库的那些实际 import 一遍。
./python -c 'import ssl, _hashlib, sqlite3, _decimal, lzma, bz2, zlib, ctypes, dbm.gnu, dbm.ndbm, tkinter, pyexpat, readline, curses, _uuid' \
    || die "有扩展模块没编出来,在 build/build.log 里搜对应的模块名"

echo
./python -VV
echo "编译数据库:$n 条"
