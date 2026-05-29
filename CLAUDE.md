# CLAUDE.md

本仓库是 CPython 3.11 源码(分支 `study-3.11`),用于本地编译、调试与**源码学习研究**。

## study/ 目录

`study/` 是我们的**学习研究文档目录**,存放学习 CPython 内部实现过程中的笔记、配置记录、源码分析等 Markdown 文档。

- 文档用中文撰写,按主题编号命名(例如 `01. 编译配置.md`)。
- 该目录下是学习笔记,不属于 CPython 上游代码。

## 构建

调试构建配置过程见 `study/01. 编译配置.md`。简言之:树外构建在 `build/` 目录,`--with-pydebug`,解释器为 `build/python`,编译数据库 `build/compile_commands.json` 已软链到仓库根供 clangd 使用。
