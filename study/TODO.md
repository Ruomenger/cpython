# CPython 3.11 底层原理 · 研究学习计划（TODO）

> 目标：深入理解 CPython 3.11 的对象系统、求值引擎、内存管理与运行时机制。
> 方式：以**周**为单位布置研究任务，边读源码边做实验，每周产出一篇 `study/NN. 主题.md` 笔记。
> 基础：已具备 C/Linux 基础与后端经验，计划直接深入 C 源码与运行时，不在基础概念上停留。

## 如何使用

- 每周聚焦一个主题，完成 **研究任务** 里的勾选项。
- 每周末产出一篇编号笔记（接着 `00. 编译配置.md` 往后排），记录：读懂了什么、做了哪些实验、踩了哪些坑、与 Go 的对比。
- 带 ★ 的是 3.11 的标志性特性或与你 Go 背景最有共鸣的对比点，重点投入。

## 通用工具 / 方法

- **调试版解释器**：`build/python`（`--with-pydebug`，可断点、带 `sys.gettotalrefcount`）。
- **lldb**：`lldb build/python`，在 C 函数下断点单步（如 `b _PyEval_EvalFrameDefault`）。
- **字节码**：`dis` 模块（`dis.dis(f)`、`dis.dis(f, adaptive=True)`）、`Lib/opcode.py`、`Include/opcode.h`。
- **运行时探查**：`sys`（`getrefcount`/`getsizeof`/`_debugmallocstats`/`gettotalrefcount`）、`gc`、`tracemalloc`。
- **读源码**：`build/compile_commands.json` + clangd 做跳转；核心目录 `Objects/`、`Python/`、`Parser/`、`Include/internal/`。

---

## 阶段一：执行模型与对象系统（第 1–4 周）

### 第 1 周 · 源码全景 & 执行流水线总览
- 目标：建立源码地图；搞清一行 Python 代码从源码到执行的完整链路。
- 关键源码：`Programs/python.c`、`Modules/main.c`、`Python/pythonrun.c`、`Lib/dis.py`、`Include/opcode.h`
- 研究任务：
  - [ ] 梳理并画出 `源码 → tokenize → parse(PEG) → AST → 符号表 → compile → code object → ceval` 流水线。
  - [ ] 用 `dis.dis` 反汇编 3~5 个小函数，认识常见字节码。
  - [ ] `lldb` 在 `main`、`pymain_run_python` 下断点，单步走到解释器入口，记录调用栈。
- 产出：`01. 执行流水线总览.md`
- Go 对比：Go 是 AOT 编到机器码；Python 编到字节码再解释执行——编译期/运行期边界的差异。

### 第 2 周 · 对象模型与引用计数
- 目标：理解“万物皆对象”：`PyObject` / `PyVarObject` / `PyTypeObject`，以及引用计数。
- 关键源码：`Include/object.h`、`Objects/object.c`、`Include/internal/pycore_object.h`
- 研究任务：
  - [ ] 读 `PyObject` 结构（`ob_refcnt`、`ob_type`），理解 `Py_INCREF/Py_DECREF` 与 `_Py_Dealloc`。
  - [ ] 用 `sys.getrefcount`、`id()` 做实验；调试版用 `sys.gettotalrefcount` 观察总引用数变化。
  - [ ] `lldb` 中打印对象内存布局：`p *(PyObject*)<addr>`。
- 产出：`02. 对象模型与引用计数.md`
- Go 对比：Go 用 tracing GC、无引用计数——两种内存管理哲学的取舍。

### 第 3 周 · 类型系统：PyTypeObject 与协议
- 目标：类型对象如何工作；`tp_*` 槽位、属性查找、MRO、鸭子类型的底层。
- 关键源码：`Objects/typeobject.c`、`Include/cpython/object.h`
- 研究任务：
  - [ ] 读 `PyTypeObject` 的 `tp_*` 槽位；理清 `type`/`object`/元类关系（`type(type) is type`）。
  - [ ] 研究 MRO 的 C3 线性化实现。
  - [ ] 实验：自定义类，用 `dis`/`lldb` 看 `LOAD_ATTR` 如何走 `tp_getattro`。
  - [ ] 理解 number/sequence/mapping 协议槽位如何映射到运算符。
- 产出：`03. 类型系统与协议.md`
- Go 对比：Go interface（隐式实现）vs Python 鸭子类型 + 类型槽位分发。

### 第 4 周 · 核心内置类型：int / str / list / tuple / dict
- 目标：常用类型的内部表示与性能特性。
- 关键源码：`Objects/longobject.c`、`unicodeobject.c`、`listobject.c`、`tupleobject.c`、`dictobject.c`
- 研究任务：
  - [ ] int：任意精度整数存储（`ob_digit`）、小整数缓存 `[-5, 256]`（实验验证）。
  - [ ] str：PEP 393 紧凑 Unicode（1/2/4 字节 kind）、字符串驻留 interning。
  - [ ] list：动态数组的 over-allocation 扩容策略（`sys.getsizeof` 观察）。
  - [ ] dict：★紧凑字典 + 索引数组、key-sharing、开放寻址解决冲突。
  - [ ] tuple / 小对象的 freelist。
- 产出：`04. 内置类型内部表示.md`
- Go 对比：Go slice 扩容 vs list；Go map vs CPython dict 的实现取舍。

---

## 阶段二：求值引擎（第 5–8 周）★3.11 重头戏

### 第 5 周 · code object 与帧（3.11 帧重构）
- 目标：`PyCodeObject` 字段；★3.11 把帧改为 `_PyInterpreterFrame` 并放到数据栈上的重大优化。
- 关键源码：`Objects/codeobject.c`、`Include/internal/pycore_frame.h`、`Include/cpython/code.h`、`Objects/frameobject.c`
- 研究任务：
  - [ ] 读 code object 字段（`co_code`/`co_consts`/`co_names`/`co_varnames`/`co_exceptiontable` 等），用 `f.__code__` 探查。
  - [ ] 理解 `_PyInterpreterFrame`、`localsplus`，以及帧不再总是堆分配带来的提速。
  - [ ] ★理解 3.11 的零开销异常处理：用 `co_exceptiontable` 异常表取代 `SETUP_FINALLY` 字节码。
  - [ ] `lldb` 在函数调用处观察帧的创建。
- 产出：`05. CodeObject与帧.md`

### 第 6 周 · 字节码求值循环 ceval
- 目标：吃透解释器主循环、求值栈、指令分发（computed goto）。
- 关键源码：`Python/ceval.c`、`Python/opcode_targets.h`、`Include/opcode.h`
- 研究任务：
  - [ ] 读 `_PyEval_EvalFrameDefault` 主循环结构，理解 `DISPATCH` / computed goto。
  - [ ] 手动模拟一个表达式的求值栈（`stack_pointer`）变化。
  - [ ] `lldb` 在 `_PyEval_EvalFrameDefault` 下条件断点，观察特定 opcode。
  - [ ] 理解 `CALL` 指令族与 vectorcall 调用协议。
- 产出：`06. ceval求值循环.md`
- Go 对比：解释分发开销 vs 原生执行。

### 第 7 周 · 自适应特化解释器（PEP 659）★3.11 核心特性
- 目标：理解 quickening、inline cache、指令特化（adaptive / specialized opcodes）。
- 关键源码：`Python/specialize.c`、`Include/internal/pycore_code.h`
- 研究任务：
  - [ ] 理解 ADAPTIVE 指令运行时特化（如 `LOAD_ATTR` → `LOAD_ATTR_INSTANCE_VALUE`）。
  - [ ] 理解 inline cache 如何内嵌在 `co_code` 中（cache entry）。
  - [ ] 实验：`dis.dis(f, adaptive=True)`，让函数热起来后查看特化结果。
  - [ ] 找出去特化（deopt）的触发条件。
- 产出：`07. 自适应特化解释器.md`
- Go 对比：运行时特化 vs 静态编译；这是 Python 追性能、为 3.13+ JIT 铺路的关键一步。

### 第 8 周 · 函数、闭包、生成器与协程
- 目标：可调用对象、闭包 cell、生成器/协程如何挂起与恢复。
- 关键源码：`Objects/funcobject.c`、`Objects/genobject.c`、`Objects/cellobject.c`、`Python/ceval.c`
- 研究任务：
  - [ ] 闭包：cell 变量、`LOAD_DEREF`/`STORE_DEREF`（实验闭包捕获）。
  - [ ] 生成器：`gi_frame_state`，`YIELD_VALUE`/`RESUME` 如何保存与恢复帧。
  - [ ] 协程：`async`/`await` 与生成器共享的机制，coroutine vs generator。
  - [ ] `lldb` 观察生成器恢复时帧的复用。
- 产出：`08. 函数闭包生成器协程.md`
- Go 对比：★goroutine（有栈协程 + 调度器，真并行）vs Python 生成器/协程（无栈、基于帧挂起）+ asyncio 事件循环——你 Go 背景最有共鸣的一周。

---

## 阶段三：内存与运行时（第 9–12 周）

### 第 9 周 · 内存分配器 pymalloc
- 目标：分层内存管理 arena/pool/block，小对象分配器。
- 关键源码：`Objects/obmalloc.c`、`Include/internal/pycore_obmalloc.h`
- 研究任务：
  - [ ] 理解 raw/object/mem 三个分配域；pymalloc 对 ≤512B 小对象的 pool/block 管理。
  - [ ] 各类型的 freelist（int/float/tuple/frame 等）。
  - [ ] 实验：`sys._debugmallocstats()`、`tracemalloc`，观察 arena 增长。
  - [ ] 解释“Python 进程内存只增难退还”的常见现象。
- 产出：`09. 内存分配器.md`
- Go 对比：★Go 的 mcache/mcentral/mheap 分层分配器，结构上与 pymalloc 很像，值得对照。

### 第 10 周 · 垃圾回收：循环 GC
- 目标：引用计数 + 分代循环 GC 的协作。
- 关键源码：`Modules/gcmodule.c`、`Include/internal/pycore_gc.h`
- 研究任务：
  - [ ] 理解三代、阈值、触发时机；mark-and-sweep 找不可达环。
  - [ ] 可追踪对象（`tp_traverse`/`tp_clear`）与 GC header。
  - [ ] 实验：`gc.get_stats()`/`get_objects()`/`set_debug(gc.DEBUG_LEAK)`，构造循环引用观察回收。
  - [ ] 弱引用、`__del__` 终结器对 GC 的影响。
- 产出：`10. 垃圾回收.md`
- Go 对比：★Go 的三色标记并发 GC vs CPython“引用计数为主 + 分代循环回收”——停顿/吞吐取舍。

### 第 11 周 · 导入系统与冻结模块
- 目标：import 机制（C 层 + importlib），★3.11 冻结启动模块加速。
- 关键源码：`Python/import.c`、`Python/frozen.c`、`Python/frozen_modules/`、`Lib/importlib/`
- 研究任务：
  - [ ] 理解 finders/loaders、`sys.modules`、`sys.path` 的查找链。
  - [ ] 看 `frozen_modules`：3.11 把 importlib 等启动模块冻进可执行文件。
  - [ ] 实验：自定义 import hook；观察 `.pyc` 缓存。
- 产出：`11. 导入系统.md`

### 第 12 周 · 运行时状态与 GIL
- 目标：`PyInterpreterState`/`PyThreadState`，GIL 的实现与释放时机。
- 关键源码：`Python/pystate.c`、`Python/ceval_gil.h`、`Include/internal/pycore_runtime.h`、`Include/internal/pycore_interp.h`
- 研究任务：
  - [ ] 理解 runtime → interpreter → thread state 层级。
  - [ ] GIL：获取/释放、`eval_breaker`、切换间隔（`sys.setswitchinterval`）。
  - [ ] 实验：多线程 CPU 密集 vs IO 密集，观察 GIL 影响；`Py_BEGIN_ALLOW_THREADS`。
  - [ ] 了解子解释器与 3.12+ per-interpreter GIL 方向。
- 产出：`12. 运行时与GIL.md`
- Go 对比：★Go 的 M:N 调度真并行 vs Python GIL 串行执行字节码——解释为什么 Python 多线程跑 CPU 密集不快。

---

## 阶段四：实践与综合（第 13 周起 · 进阶）

### 第 13 周 · C 扩展与 C-API
- 目标：亲手写 C 扩展，理解 API/ABI、引用计数纪律、参数解析。
- 关键源码：`Include/Python.h`、`Modules/_testcapimodule.c`、`Doc/extending/`
- 研究任务：
  - [ ] 写一个简单 C 扩展模块，用调试版加载运行。
  - [ ] 故意制造引用计数 bug，用 `sys.gettotalrefcount` 抓出来。
- 产出：`13. C扩展与CAPI.md`

### 第 14 周 · 综合实战（capstone）：改 CPython 自身
- 目标：综合所学，给解释器做一处可观测的改动。
- 研究任务（任选其一）：
  - [ ] 加一个新的内置函数或新字节码，跑通 `dis` 与执行。
  - [ ] 在 ceval 里加指令计数统计，跑基准看热点指令分布。
  - [ ] 给某个类型加方法/做小优化，基准对比前后差异。
- 产出：`14. 综合实战.md` + 你的修改 patch。

---

## 进度

- [x] 第 0 周 · 本地编译调试环境（见 `00. 编译配置.md`）
- [ ] 第 1 周 · 执行流水线总览
- [ ] 第 2 周 · 对象模型与引用计数
- [ ] 第 3 周 · 类型系统与协议
- [ ] 第 4 周 · 内置类型内部表示
- [ ] 第 5 周 · CodeObject 与帧
- [ ] 第 6 周 · ceval 求值循环
- [ ] 第 7 周 · 自适应特化解释器
- [ ] 第 8 周 · 函数闭包生成器协程
- [ ] 第 9 周 · 内存分配器
- [ ] 第 10 周 · 垃圾回收
- [ ] 第 11 周 · 导入系统
- [ ] 第 12 周 · 运行时与 GIL
- [ ] 第 13 周 · C 扩展与 C-API
- [ ] 第 14 周 · 综合实战
