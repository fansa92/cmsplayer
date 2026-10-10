#!/usr/bin/env bash
#
# 把 `flutter build linux` 产出的 bundle 做成免依赖发行版。
#
#   用法: bundle-linux.sh <bundle目录>
#   例:   bundle-linux.sh build/linux/x64/release/bundle
#
# 做法：
#   1. 用 ldd 递归收集 bundle 内所有 ELF 的依赖，剔除 glibc / 动态加载器后
#      拷进 bundle/lib/（与 libflutter_linux_gtk.so 同级）；
#   2. 给所有 ELF 改写 RPATH 为 $ORIGIN:$ORIGIN/lib，让它们优先加载同目录下的
#      那份库，而不是系统的。
#
# 结果：目标机器不需要装 libgtk-3 / libcairo / libpango 等，只要 glibc 够新即可。
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "用法: $0 <bundle目录>" >&2
  exit 2
fi

BUNDLE_DIR="$(cd "$1" && pwd)"
BIN="$(find "$BUNDLE_DIR" -maxdepth 1 -type f -executable | head -n 1)"

if [[ -z "$BIN" ]]; then
  echo "错误: 在 $BUNDLE_DIR 下找不到可执行文件" >&2
  exit 1
fi

LIB_DIR="$BUNDLE_DIR/lib"
mkdir -p "$LIB_DIR"

# glibc 与动态加载器必须用目标系统的，打包进去会导致段错误。
# NSS 模块也由系统提供（会读 /etc/nsswitch.conf）。
skip() {
  case "$1" in
    libc.so* | libm.so* | libdl.so* | libpthread.so* | librt.so* | \
    libresolv.so* | libutil.so* | libanl.so* | libthread_db.so* | \
    libnss_*.so* | ld-linux* | linux-vdso*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# 递归收集某个 ELF 的动态依赖。
collect() {
  local obj="$1"
  local deps dep name dest
  deps="$(ldd "$obj" 2>/dev/null | awk '/=> \// {print $3} /^\// {print $1}' || true)"
  for dep in $deps; do
    name="$(basename "$dep")"
    skip "$name" && continue
    dest="$LIB_DIR/$name"
    # 已存在则跳过：既是幂等保证，也避免把 bundle 内部的文件复制到自身。
    [[ -f "$dest" ]] && continue
    cp -L "$dep" "$dest"
    collect "$dest"
  done
}

echo "==> 收集动态库到 lib/"
collect "$BIN"
echo "    $(find "$LIB_DIR" -maxdepth 1 -name '*.so*' | wc -l) 个库"

echo "==> 改写 RPATH"
# 主程序与 lib/ 下的每个 ELF 都指向 $ORIGIN 和 $ORIGIN/lib：
#   - 主程序靠 $ORIGIN/lib 找到 Flutter 引擎与我们收集的系统库；
#   - lib/ 内的库靠 $ORIGIN 找到同目录的兄弟库（RUNPATH 不会传递给子进程，
#     所以每个 .so 都必须自带，否则 libgtk-3 之类会加载不到）。
count=0
while IFS= read -r -d '' f; do
  if head -c 4 "$f" | grep -q $'\x7fELF'; then
    if patchelf --set-rpath '$ORIGIN:$ORIGIN/lib' "$f" 2>/dev/null; then
      count=$((count + 1))
    fi
  fi
done < <(find "$BUNDLE_DIR" -type f -print0)
echo "    $count 个 ELF 已处理"

echo "==> 校验"
if command -v ldd >/dev/null 2>&1; then
  missing="$(ldd "$BIN" 2>&1 | grep 'not found' || true)"
  if [[ -n "$missing" ]]; then
    echo "错误: 仍有未解析的依赖：" >&2
    echo "$missing" >&2
    exit 1
  fi
fi
echo "    依赖全部可解析"
echo "==> 完成: $BUNDLE_DIR"
