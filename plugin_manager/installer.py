import urllib.request
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
        """
        return any(plugin in f.name for f in self.geoserver_lib.iterdir())

    def install(self, plugin: str, url: str) -> None:
        if self.is_installed(plugin):
            print(f"✅ {plugin} already installed")
            return

        zip_name = url.split("/")[-1]
        zip_path = self.tmp_dir / zip_name

        print(f"⬇️  Downloading {zip_name}")
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

    def _download(self, url: str, target: Path) -> None:
        try:
            urllib.request.urlretrieve(url, target)
        except Exception as e:
            raise RuntimeError(f"Failed to download {url}") from e

    def _extract(self, zip_path: Path) -> None:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(self.geoserver_lib)