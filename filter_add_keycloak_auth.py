#!/usr/bin/env python3
# change.py
#
# Input : geoserver_docker/test_filter_config.xml
# Output: geoserver_docker/test_filter_changed.xml
#
# Features:
# - Auto-fixes missing closing </security>.
# - Ensures `keycloak-auth` is ALWAYS the FIRST filter in target chains (web/rest/default).
# - Ensures `anonymous` exists and is ALWAYS the LAST filter in target chains.
# - Optionally removes `form` and/or `rememberme` in "web" chain; optionally removes `basic` in "default" chain.
# - Writes backups to a dedicated "_backup/" folder (timestamps), keeping the source directory clean.
# - Idempotent (safe to run repeatedly).
# - Stdlib only.

import os
import sys
import datetime
import xml.etree.ElementTree as ET

# --- Paths (override via ENV if you want) ---
INPUT_PATH  = os.environ.get("FILTER_CONFIG_IN",  "/Users/hsadmin/Desktop/coding/geoserver_docker/test_filter_config.xml")
OUTPUT_PATH = os.environ.get("FILTER_CONFIG_OUT", "/Users/hsadmin/Desktop/coding/geoserver_docker/test_filter_changed.xml")

# --- Behavior toggles ---
REMOVE_FORM_FROM_WEB   = False
REMOVE_REMEMBERME_WEB  = True
REMOVE_BASIC_DEFAULT   = False
ENSURE_ANONYMOUS_LAST  = True

# Target chains to modify
TARGET_CHAINS = {"web", "rest", "default"}


def read_xml_text(path: str) -> str:
    if not os.path.exists(path):
        print(f"[ERROR] Input not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def ensure_closed_security(txt: str) -> str:
    """If closing </security> is missing (truncated files), append it to allow parsing."""
    if "</security>" not in txt:
        txt = txt.rstrip() + "\n</security>\n"
        print("[fix] appended missing </security> closing tag")
    return txt


def parse_tree_from_text(xml_text: str) -> ET.ElementTree:
    try:
        return ET.ElementTree(ET.fromstring(xml_text))
    except ET.ParseError as e:
        print(f"[ERROR] XML parse error: {e}", file=sys.stderr)
        sys.exit(2)


def backup(path: str):
    """Safe backup into a sibling '_backup' directory with timestamped filename."""
    try:
        ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        bkpdir = os.path.join(os.path.dirname(path), "_backup")
        os.makedirs(bkpdir, exist_ok=True)
        bkp = os.path.join(bkpdir, os.path.basename(path) + f".{ts}.bak")
        with open(path, "rb") as src, open(bkp, "wb") as dst:
            dst.write(src.read())
        print(f"[backup] Saved backup: {bkp}")
    except Exception as e:
        print(f"[WARN] Backup failed: {e}")


def get_filter_chain(root: ET.Element) -> ET.Element:
    fc = root.find("./filterChain")
    if fc is None:
        print("[ERROR] <filterChain> not found", file=sys.stderr)
        sys.exit(3)
    return fc


def find_filters(chain_el: ET.Element):
    """Return list of <filter> children."""
    return [f for f in chain_el.findall("./filter")]


def ensure_or_move_to_top(chain_el: ET.Element, name: str) -> bool:
    """
    Ensure a filter named `name` exists and is the FIRST element of the chain.
    - If not present, create it and insert at position 0.
    - If present but not first, move it to position 0.
    - If already first, do nothing.
    """
    changed = False
    filters = find_filters(chain_el)
    target = None
    for f in filters:
        if (f.text or "").strip() == name:
            target = f
            break

    if target is None:
        newf = ET.Element("filter")
        newf.text = name
        chain_el.insert(0, newf)
        return True

    # Already present; if not first, move it to the top
    if filters and filters[0] is not target:
        chain_el.remove(target)
        chain_el.insert(0, target)
        changed = True

    return changed


def remove_filter(chain_el: ET.Element, name: str) -> bool:
    """Remove all occurrences of a named filter."""
    changed = False
    for f in list(find_filters(chain_el)):
        if (f.text or "").strip() == name:
            chain_el.remove(f)
            changed = True
    return changed


def ensure_anonymous_last(chain_el: ET.Element) -> bool:
    """
    Ensure there is exactly one 'anonymous' filter and it is the LAST element.
    - If missing, append one.
    - If multiple, keep only one and ensure it is last.
    """
    changed = False
    filters = find_filters(chain_el)
    anon_list = [f for f in filters if (f.text or "").strip() == "anonymous"]

    if not anon_list:
        # Add missing anonymous at the end
        f = ET.Element("filter")
        f.text = "anonymous"
        chain_el.append(f)
        return True

    # If multiple anonymous, remove all but the last occurrence
    if len(anon_list) > 1:
        for f in anon_list[:-1]:
            chain_el.remove(f)
            changed = True
        filters = find_filters(chain_el)
        anon_list = [f for f in filters if (f.text or "").strip() == "anonymous"]

    anon = anon_list[0]
    filters = find_filters(chain_el)
    if not filters or filters[-1] is anon:
        return changed  # already last

    # Move anonymous to the end
    chain_el.remove(anon)
    chain_el.append(anon)
    return True


def pretty_write(root: ET.Element, out_path: str):
    ET.indent(root, space="  ")
    tree = ET.ElementTree(root)
    tree.write(out_path, encoding="utf-8", xml_declaration=True)


def modify(tree: ET.ElementTree) -> bool:
    root = tree.getroot()
    fc = get_filter_chain(root)
    changed = False

    for chain in fc.findall("./filters"):
        name = chain.get("name")
        if name not in TARGET_CHAINS:
            continue

        # 1) keycloak-auth must ALWAYS be the first filter
        changed |= ensure_or_move_to_top(chain, "keycloak-auth")

        # 2) Optional removals per chain
        if name == "web":
            if REMOVE_FORM_FROM_WEB:
                changed |= remove_filter(chain, "form")
            if REMOVE_REMEMBERME_WEB:
                changed |= remove_filter(chain, "rememberme")

        if name == "default" and REMOVE_BASIC_DEFAULT:
            changed |= remove_filter(chain, "basic")

        # 3) Ensure 'anonymous' is the last filter
        if ENSURE_ANONYMOUS_LAST:
            changed |= ensure_anonymous_last(chain)
        else:
            # If not enforced, at least ensure it exists (append if missing)
            if not any((f.text or "").strip() == "anonymous" for f in find_filters(chain)):
                f = ET.Element("filter")
                f.text = "anonymous"
                chain.append(f)
                changed = True

    return changed


def main():
    print(f"[info] Input : {os.path.abspath(INPUT_PATH)}")
    print(f"[info] Output: {os.path.abspath(OUTPUT_PATH)}")

    # Backup the original input file to _backup/
    backup(INPUT_PATH)

    # Load + harden input
    xml_text = read_xml_text(INPUT_PATH)
    xml_text = ensure_closed_security(xml_text)
    tree = parse_tree_from_text(xml_text)

    # Modify in-memory tree
    changed = modify(tree)
    print("[info] Changes applied." if changed else "[info] No changes needed (idempotent).")

    # Write output
    try:
        pretty_write(tree.getroot(), OUTPUT_PATH)
        print(f"[ok] Wrote: {OUTPUT_PATH}")
    except Exception as e:
        print(f"[ERROR] Failed to write output: {e}", file=sys.stderr)
        sys.exit(4)


if __name__ == "__main__":
    main()