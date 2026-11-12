# CPython 3.11 源码学习仓库

CPython 源码的个人 fork,用来**研究 Python 3.11 的实现原理与机制**:读源码、在调试构建上做实验、把结论整理成笔记。不向上游提交代码。

## 回答问题和做研究时

- **以本仓库的源码为准。** 当前版本看 `Include/patchlevel.h`(`v3.11.x`)。帧结构、字节码与内联缓存、自适应特化、异常表都是 3.11 这一版重做的,和 3.10 及更早差别很大,3.12 之后又改了一轮。书、博客和记忆里的说法多半对应别的版本,用之前先对照这里的代码。
- **说法落到源码位置**(`文件:行号` 加函数名)。能验证的就在 `build/python` 上跑实验,给出命令和实际输出;没验证的明确说是推断。
- **默认只读。** 除非明确要求,不改上游源码文件:`study` 分支要跟着上游标签 rebase,改动上游文件会带来冲突。
- 用中文交流和写文档。读者熟悉 C 与 Linux,后端经验主要在 Go:不用解释指针、进程、shell 这类基础,讲机制时适合拿 Go 的对应实现(goroutine 调度、GC、interface)做对照。

## 实验手段

`build/python` 是 `--with-pydebug`、`-O0` 的调试构建,下面这些都可以直接用:

- 字节码与特化结果:`dis.dis(f, adaptive=True, show_caches=True)`。
- 逐指令跟踪:模块里先写 `__lltrace__ = 1`,此后进入的每个帧都会打印执行的指令和求值栈。
- 运行时状态:`sys.gettotalrefcount()`、`sys.getrefcount()`、`sys._debugmallocstats()`、`-X showrefcount`、`gc`、`tracemalloc`。
- 断点:lldb 用批处理模式,一条命令跑完,例如

  ```bash
  lldb -b -s study/scripts/cpython.lldb \
    -o 'breakpoint set -n list_append' \
    -o 'process launch -- -c "[].append(42)"' \
    -o 'pyo object' -o 'pybt' -o 'bt 5' -o 'kill' \
    build/python
  ```

  `pyo <表达式>` 打印一个 `PyObject *`,`pybt` 打印 Python 调用栈。启动用 `process launch --`,不要用 `run`:`run` 会对参数做 shell 展开,代码里有 `[]`、`*` 时会失败。

## 目录

- `study/`:学习笔记和配套脚本,不属于上游代码。笔记用中文,按 `NN. 主题.md` 编号;`00. 编译配置.md` 是构建和编辑器配置的说明。
- `study/scripts/`:`rebuild.sh`(全量重建)、`cpython.lldb`(lldb 辅助命令)。
- `.vscode/`、`.clangd`:编辑器配置。`.vscode/` 被上游 `.gitignore` 忽略,是用 `git add -f` 强制跟踪的;已跟踪文件的改动照常显示,新增文件要再 `git add -f`。
- `build/`:构建产物,不入库。

## 构建

- 全量重建:`study/scripts/rebuild.sh`(configure、clean、编译、生成编译数据库、校验,约 2 分钟)。每一步的原因见 `study/00. 编译配置.md`。
- 增量编译:`make -C build -j8`。
- **rebase 不会更新 `build/python`。** 调试前先比对 `build/python -VV` 和 `Include/patchlevel.h` 里的 `PY_VERSION`,不一致就全量重建,并在文档的「重建记录」里加一行。
- **不要直接跑 `bear -- make`**,它会把 `build/compile_commands.json` 覆盖成空的。要刷新编译数据库就跑重建脚本。

## 分支与远端

- `study` 分支 = 上游 `v3.11.x` 标签 + 自己的提交;上游出新标签时 rebase 上去。
- 远端 `origin` 是自己的 fork(**公开仓库**,不要往里写私密信息),`github` 是上游 `python/cpython`。
