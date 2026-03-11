import os
import logging
import shutil
from common.decorator import singleton
from common import settings

@singleton
class LocalFSStorage:
    def __init__(self):
        self.base_path = settings.LOCAL_FS.get('base_path', '/data/xfeng/ragflow-storage')
        if not os.path.exists(self.base_path):
            try:
                os.makedirs(self.base_path, exist_ok=True)
                logging.info(f"Created local storage base path: {self.base_path}")
            except Exception as e:
                logging.error(f"Failed to create local storage base path {self.base_path}: {e}")

    def _get_full_path(self, bucket, fnm):
        return os.path.join(self.base_path, bucket, fnm)

    def health(self):
        return os.path.exists(self.base_path) and os.access(self.base_path, os.W_OK)

    def put(self, bucket, fnm, binary, tenant_id=None):
        full_path = self._get_full_path(bucket, fnm)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        try:
            with open(full_path, 'wb') as f:
                f.write(binary)
            return True
        except Exception as e:
            logging.error(f"Failed to put file {full_path}: {e}")
            return False

    def get(self, bucket, fnm, tenant_id=None):
        full_path = self._get_full_path(bucket, fnm)
        try:
            with open(full_path, 'rb') as f:
                return f.read()
        except Exception as e:
            logging.error(f"Failed to get file {full_path}: {e}")
            return None

    def rm(self, bucket, fnm, tenant_id=None):
        full_path = self._get_full_path(bucket, fnm)
        try:
            if os.path.exists(full_path):
                os.remove(full_path)
            return True
        except Exception as e:
            logging.error(f"Failed to remove file {full_path}: {e}")
            return False

    def obj_exist(self, bucket, fnm, tenant_id=None):
        full_path = self._get_full_path(bucket, fnm)
        return os.path.exists(full_path)

    def bucket_exists(self, bucket):
        bucket_path = os.path.join(self.base_path, bucket)
        return os.path.exists(bucket_path)

    def remove_bucket(self, bucket):
        bucket_path = os.path.join(self.base_path, bucket)
        try:
            if os.path.exists(bucket_path):
                shutil.rmtree(bucket_path)
            return True
        except Exception as e:
            logging.error(f"Failed to remove bucket {bucket_path}: {e}")
            return False

    def copy(self, src_bucket, src_path, dest_bucket, dest_path):
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
        # Local FS doesn't support presigned URLs in the same way S3 does.
        # Returning a placeholder or local path if needed, but typically not used for local.
        return f"file://{self._get_full_path(bucket, fnm)}"
