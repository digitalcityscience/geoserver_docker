import os
import argparse

from resolver import GeoServerContext, PluginResolver
from installer import PluginInstaller


def parse_list(value: str):
    if not value:
        return []
    return [v.strip() for v in value.split(",") if v.strip()]


def main():
    parser = argparse.ArgumentParser(
        description="GeoServer plugin manager"
    )

    parser.add_argument("--version", help="GeoServer version (e.g. 2.28.3)")
    parser.add_argument("--community", help="Community plugins (comma-separated)")
    parser.add_argument("--official", help="Official plugins (comma-separated)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--test-lib-dir", help="Test lib directory for plugin installation")

    args = parser.parse_args()

    # Environment fallback for Docker builds and runtime plugin installation.
    version = args.version or os.getenv("GEOSERVER_VERSION")
    community_raw = args.community or os.getenv("COMMUNITY_PLUGINS", "")
    official_raw = args.official or os.getenv("OFFICIAL_PLUGINS", "")

    if not version:
        raise SystemExit("GEOSERVER_VERSION is required")

    community = parse_list(community_raw)
    official = parse_list(official_raw)

    ctx = GeoServerContext(version=version)

    resolver = PluginResolver(ctx)

    if args.test_lib_dir:
        from pathlib import Path
        installer = PluginInstaller(
            geoserver_lib=Path(args.test_lib_dir),
            tmp_dir=Path("/tmp/geoserver-plugins-test")
        )
    else:
        installer = PluginInstaller()

    if args.dry_run:
        print("🔎 Dry run")
        for p in community:
            print("COMMUNITY:", resolver.community(p))
        for p in official:
            print("OFFICIAL:", resolver.official(p))
        return

    if community:
        installer.install_many(
            community,
            resolver.community
        )

    if official:
        installer.install_many(
            official,
            resolver.official
        )

    print("Plugin setup complete")


if __name__ == "__main__":
    main()
