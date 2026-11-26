import os
import shutil
import time
import urllib.request
import urllib.error
import zipfile
from pathlib import Path
from typing import Iterable


class PluginInstaller:
    def __init__(
        self,
        geoserver_lib: Path = Path(
            "/usr/local/tomcat/webapps/geoserver/WEB-INF/lib"
        ),
        tmp_dir: Path = Path("/tmp/geoserver-plugins"),
    ):
        self.geoserver_lib = geoserver_lib
        self.tmp_dir = tmp_dir
        self.tmp_dir.mkdir(parents=True, exist_ok=True)

    def is_installed(self, plugin: str) -> bool:
        """
        Check if a plugin is already installed in the GeoServer lib directory.
        Look for JAR files containing the plugin name followed by a version.
        """
        if not self.geoserver_lib.exists():
            return False
            
        for jar_file in self.geoserver_lib.glob("*.jar"):
            # Check if the jar file name contains the plugin name
            # Common patterns: gt-{plugin}-*, gs-{plugin}-*, geoserver-{plugin}-*
            jar_name = jar_file.name.lower()
            plugin_lower = plugin.lower()
            
            # Look for plugin name in jar file name
            if (f"gt-{plugin_lower}-" in jar_name or 
                f"gs-{plugin_lower}-" in jar_name or 
                f"geoserver-{plugin_lower}-" in jar_name or
                f"{plugin_lower}-" in jar_name):
                print(f"✅ {plugin} appears to be installed (found {jar_file.name})")
                return True
                
        return False

    def install(self, plugin: str, url: str) -> None:
        if self.is_installed(plugin):
            print(f"✅ {plugin} already installed")
            return

        zip_name = url.split("/")[-1]
        # SourceForge URL'lerinde /download kısmını temizle
        if zip_name == "download":
            zip_name = url.split("/")[-2]
        
        zip_path = self.tmp_dir / zip_name

        print(f"⬇️  Downloading {plugin} from {url}")
        self._download(url, zip_path)

        print(f"📦  Extracting {zip_name}")
        self._extract(zip_path)

    def install_many(self, plugins: Iterable[str], url_fn) -> None:
        """
        url_fn(plugin) -> resolved URL
        """
        for plugin in plugins:
            plugin = plugin.strip()
            if not plugin:
                continue
            url = url_fn(plugin)
            self.install(plugin, url)

    # Download mirrors (SourceForge especially) sometimes time out or answer
    # with an error page; a later attempt usually gets another mirror.
    ATTEMPTS = int(os.getenv("PLUGIN_DOWNLOAD_ATTEMPTS", "5"))
    TIMEOUT = float(os.getenv("PLUGIN_DOWNLOAD_TIMEOUT", "120"))
    BACKOFF = float(os.getenv("PLUGIN_DOWNLOAD_BACKOFF", "10"))

    def _download(self, url: str, target: Path) -> None:
        print(f"   URL: {url}")
        last_error = None
        for attempt in range(1, self.ATTEMPTS + 1):
            try:
                self._download_once(url, target)
                print(f"   ✓ Downloaded to {target}")
                return
            except urllib.error.HTTPError as e:
                # 4xx other than 408/429 will not change on retry (e.g. 404).
                if 400 <= e.code < 500 and e.code not in (408, 429):
                    raise RuntimeError(f"HTTP {e.code} error downloading {url}: {e.reason}") from e
                last_error = f"HTTP {e.code}: {e.reason}"
            except urllib.error.URLError as e:
                last_error = f"URL error: {e.reason}"
            except (OSError, zipfile.BadZipFile) as e:
                last_error = str(e)
            if attempt < self.ATTEMPTS:
                wait = self.BACKOFF * attempt
                print(f"   ! Attempt {attempt}/{self.ATTEMPTS} failed ({last_error}); retrying in {wait:.0f}s")
                time.sleep(wait)
        raise RuntimeError(f"Failed to download {url} after {self.ATTEMPTS} attempts: {last_error}")

    def _download_once(self, url: str, target: Path) -> None:
        # Add User-Agent to avoid bot blocking
        req = urllib.request.Request(
            url,
            headers={'User-Agent': 'GeoServer-Plugin-Manager/1.0'}
        )
        partial = target.with_name(target.name + ".part")
        try:
            with urllib.request.urlopen(req, timeout=self.TIMEOUT) as response:
                with open(partial, 'wb') as f:
                    shutil.copyfileobj(response, f)
            # A mirror's HTML error page is not a plugin.
            if not zipfile.is_zipfile(partial):
                raise zipfile.BadZipFile(f"{url} did not return a zip file")
            partial.replace(target)
        finally:
            partial.unlink(missing_ok=True)

    def _extract(self, zip_path: Path) -> None:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(self.geoserver_lib)