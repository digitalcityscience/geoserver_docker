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

    def _download(self, url: str, target: Path) -> None:
        try:
            print(f"   URL: {url}")
            
            # Add User-Agent to avoid bot blocking
            req = urllib.request.Request(
                url,
                headers={'User-Agent': 'GeoServer-Plugin-Manager/1.0'}
            )
            
            with urllib.request.urlopen(req) as response:
                with open(target, 'wb') as f:
                    f.write(response.read())
            
            print(f"   ✓ Downloaded to {target}")
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"HTTP {e.code} error downloading {url}: {e.reason}") from e
        except urllib.error.URLError as e:
            raise RuntimeError(f"URL error downloading {url}: {e.reason}") from e
        except Exception as e:
            raise RuntimeError(f"Failed to download {url}: {str(e)}") from e

    def _extract(self, zip_path: Path) -> None:
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(self.geoserver_lib)