from dataclasses import dataclass

@dataclass
class GeoServerContext:
    version: str  # e.g. 2.27.2

    @property
    def series(self) -> str:
        # 2.27.2 → 2.27
        return ".".join(self.version.split(".")[:2])

    @property
    def community_version(self) -> str:
        # 2.27 → 2.27-SNAPSHOT
        return f"{self.series}-SNAPSHOT"


class PluginResolver:
    BASE_COMMUNITY = "https://build.geoserver.org/geoserver"
    BASE_OFFICIAL = "https://sourceforge.net/projects/geoserver/files/GeoServer"

    def __init__(self, ctx: GeoServerContext):
        self.ctx = ctx

    def community(self, plugin: str) -> str:
        return (
            f"{self.BASE_COMMUNITY}/"
            f"{self.ctx.series}.x/community-latest/"
            f"geoserver-{self.ctx.community_version}-{plugin}-plugin.zip"
        )

    def official(self, plugin: str) -> str:
        return (
            f"{self.BASE_OFFICIAL}/"
            f"{self.ctx.version}/extensions/"
            f"geoserver-{self.ctx.version}-{plugin}-plugin.zip/download"
        )