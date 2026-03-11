# 故障排查与修复方案：TypeError 及文件预览失败

## 问题现象
1. Web 界面恢复，但点击已迁移的文件预览时报错：`TypeError: 'The response value returned by the view function cannot be None'`。
2. 背景错误：`Failed to get file /data/xfeng/ragflow-storage/...: No such file or directory`。

## 根本原因分析
1. **路径不一致（Path Mismatch）**：
   - 宿主机物理路径：`/data/xfeng/ragflow-storage`
   - Docker 挂载映射：`/data/xfeng/ragflow-storage:/ragflow/storage`
   - 环境变量设置：`LOCAL_FS_PATH=/data/xfeng/ragflow-storage`
   - **结果**：容器内部代码尝试访问 `/data/xfeng/ragflow-storage`，但该路径在容器内并不存在（内容实际在 `/ragflow/storage`）。

2. **异常处理不当**：
   - `LocalFSStorage.get` 在文件不存在时返回 `None`。
   - Quart 的 `make_response(None)` 可能在特定环境下返回 `None` 或导致视图函数最终返回 `None`，触发框架报错。

## 修复步骤
1. **修正路径环境变量**：将容器内的 `LOCAL_FS_PATH` 设置为挂载后的内部路径 `/ragflow/storage`。
2. **增强存储类健壮性**：修改 `LocalFSStorage.get`，使其在找不到文件时抛出异常，以便被 `server_error_response` 正确捕获并返回 JSON 错误而非崩溃。
3. **验证挂载点权限**：确保容器用户有权读取 `/ragflow/storage`。
