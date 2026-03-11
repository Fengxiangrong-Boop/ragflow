import os
import logging
import shutil
from common.decorator import singleton


@singleton
class LocalFSStorage:
    """
    本地文件系统存储实现，用于替代 MinIO，直接读写 SSD/本地目录。

    初始化参数来源（优先级从高到低）：
      1. 环境变量 LOCAL_FS_PATH
      2. 环境变量 LOCAL_FS_BASE_PATH
      3. 默认值 /ragflow/storage

    **不**依赖 settings.LOCAL_FS，避免 singleton 在 import 阶段
    实例化时（settings.init_settings() 尚未执行）取到空字典的时机问题。

    示例：
      storage = LocalFSStorage()
      storage.put("kb-001", "doc.pdf", b"...")
      data = storage.get("kb-001", "doc.pdf")  # -> bytes
    """

    def __init__(self):
        # 修复 Bug3：直接从环境变量读取，避免 settings.LOCAL_FS 初始化时机问题
        self.base_path = (
            os.environ.get("LOCAL_FS_PATH")
            or os.environ.get("LOCAL_FS_BASE_PATH")
            or "/ragflow/storage"
        )
        logging.info(f"LocalFSStorage base_path: {self.base_path}")
        if not os.path.exists(self.base_path):
            try:
                os.makedirs(self.base_path, exist_ok=True)
                logging.info(f"Created local storage base path: {self.base_path}")
            except Exception as e:
                logging.error(
                    f"Failed to create local storage base path {self.base_path}: {e}"
                )

    def _get_full_path(self, bucket, fnm):
        """将 bucket + 文件名拼成绝对路径。"""
        return os.path.join(self.base_path, bucket, fnm)

    def health(self):
        """检查存储根目录可读写。返回 bool。"""
        return os.path.exists(self.base_path) and os.access(self.base_path, os.W_OK)

    def put(self, bucket, fnm, binary, tenant_id=None):
        """
        写入文件二进制内容。

        Args:
            bucket (str): 存储桶（知识库 id）
            fnm (str): 文件名/相对路径
            binary (bytes): 文件内容

        Raises:
            OSError: 磁盘空间不足或权限不足时抛出，不静默吞掉
        """
        # 修复 Bug1：写入失败时抛出异常，与 MinIO 行为一致，避免上层误判成功
        full_path = self._get_full_path(bucket, fnm)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "wb") as f:
            f.write(binary)

    def get(self, bucket, fnm, tenant_id=None):
        """
        读取文件二进制内容。

        Returns:
            bytes: 文件内容

        Raises:
            FileNotFoundError: 文件不存在时抛出
        """
        full_path = self._get_full_path(bucket, fnm)
        if not os.path.exists(full_path):
            raise FileNotFoundError(f"File not found: {full_path}")
        with open(full_path, "rb") as f:
            return f.read()

    def rm(self, bucket, fnm, tenant_id=None):
        """删除文件，文件不存在时静默忽略（与 MinIO 行为一致）。"""
        full_path = self._get_full_path(bucket, fnm)
        try:
            if os.path.exists(full_path):
                os.remove(full_path)
            return True
        except Exception as e:
            logging.error(f"Failed to remove file {full_path}: {e}")
            return False

    def obj_exist(self, bucket, fnm, tenant_id=None):
        """检查文件是否存在。返回 bool。"""
        full_path = self._get_full_path(bucket, fnm)
        return os.path.exists(full_path)

    def bucket_exists(self, bucket):
        """检查存储桶目录是否存在。返回 bool。"""
        bucket_path = os.path.join(self.base_path, bucket)
        return os.path.exists(bucket_path)

    def remove_bucket(self, bucket):
        """递归删除存储桶目录及其所有内容。"""
        bucket_path = os.path.join(self.base_path, bucket)
        try:
            if os.path.exists(bucket_path):
                shutil.rmtree(bucket_path)
            return True
        except Exception as e:
            logging.error(f"Failed to remove bucket {bucket_path}: {e}")
            return False

    def copy(self, src_bucket, src_path, dest_bucket, dest_path):
        """跨桶复制文件。"""
        src_full = self._get_full_path(src_bucket, src_path)
        dest_full = self._get_full_path(dest_bucket, dest_path)
        try:
            os.makedirs(os.path.dirname(dest_full), exist_ok=True)
            shutil.copy2(src_full, dest_full)
            return True
        except Exception as e:
            logging.error(f"Failed to copy {src_full} to {dest_full}: {e}")
            return False

    def move(self, src_bucket, src_path, dest_bucket, dest_path):
        """跨桶移动文件（原子性重命名或跨设备移动）。"""
        src_full = self._get_full_path(src_bucket, src_path)
        dest_full = self._get_full_path(dest_bucket, dest_path)
        try:
            os.makedirs(os.path.dirname(dest_full), exist_ok=True)
            shutil.move(src_full, dest_full)
            return True
        except Exception as e:
            logging.error(f"Failed to move {src_full} to {dest_full}: {e}")
            return False

    def get_presigned_url(self, bucket, fnm, expires, tenant_id=None):
        """
        本地 FS 不支持预签名 URL（无对外 HTTP 服务）。

        Returns:
            None: 上层调用方需自行处理 None 情况（通过 API 代理下载）。

        非确定性边界：
            若未来配置 nginx 代理 /ragflow/storage，可在此返回 HTTP URL。
        """
        # 修复 Bug2：返回 None 而非无效的 file:// 路径（浏览器无法访问容器内文件）
        logging.warning(
            f"LOCAL_FS does not support presigned URLs: {bucket}/{fnm}. "
            "File preview/direct-link features may be unavailable."
        )
        return None
