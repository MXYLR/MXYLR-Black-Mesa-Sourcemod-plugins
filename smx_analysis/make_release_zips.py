"""Build the three drop-in release zips.

Each zip contains a bms/addons/sourcemod/... tree plus a bilingual
README.txt, so the player extracts it straight into the Black Mesa
folder (the one that contains bms/) after installing SourceMod and
MetaMod:Source.

usage: python make_release_zips.py [-o OUT_DIR]
"""

import argparse
import io
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SM = "smx_analysis/src/scripting"

BMAG_FILES = [
    ("plugins/BMAG.smx", "bms/addons/sourcemod/plugins/BMAG.smx"),
    ("plugins/bms_rpgReloadFix.smx",
     "bms/addons/sourcemod/plugins/bms_rpgReloadFix.smx"),
    ("plugins/bms_weapon_tauStuckFix.smx",
     "bms/addons/sourcemod/plugins/bms_weapon_tauStuckFix.smx"),
    ("plugins/is_weaponfx.smx", "bms/addons/sourcemod/plugins/is_weaponfx.smx"),
    ("plugins/is_bms_fix_timelimit.smx",
     "bms/addons/sourcemod/plugins/is_bms_fix_timelimit.smx"),
    (SM + "/gamedata/bms_match.games.txt",
     "bms/addons/sourcemod/gamedata/bms_match.games.txt"),
    (SM + "/translations/bms_match.phrases.txt",
     "bms/addons/sourcemod/translations/bms_match.phrases.txt"),
    (SM + "/translations/fast_spawn.phrases.txt",
     "bms/addons/sourcemod/translations/fast_spawn.phrases.txt"),
    (SM + "/translations/spawn_marker.phrases.txt",
     "bms/addons/sourcemod/translations/spawn_marker.phrases.txt"),
]

TAU_FILES = [
    ("campaign/tau_mp/plugins/tau_mp.smx",
     "bms/addons/sourcemod/plugins/tau_mp.smx"),
    ("campaign/tau_mp/gamedata/tau_mp.games.txt",
     "bms/addons/sourcemod/gamedata/tau_mp.games.txt"),
]

HL1TAU_FILES = [
    ("campaign/hl1tau/plugins/hl1tau.smx",
     "bms/addons/sourcemod/plugins/hl1tau.smx"),
]

PACKS = [
    ("BMAG.zip", "smx_analysis/release/bmag.readme.txt", BMAG_FILES),
    ("tau_mp.zip", "smx_analysis/release/tau_mp.readme.txt", TAU_FILES),
    ("hl1tau.zip", "smx_analysis/release/hl1tau.readme.txt", HL1TAU_FILES),
]


def build(out_dir, name, readme, files):
    out_path = os.path.join(out_dir, name)
    missing = []

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zf:
        with open(os.path.join(REPO, readme), "rb") as f:
            zf.writestr("README.txt", f.read())

        for src_rel, dst in files:
            src = os.path.join(REPO, src_rel)
            if not os.path.isfile(src):
                missing.append(src_rel)
                continue
            with open(src, "rb") as f:
                zf.writestr(dst, f.read())

    return out_path, missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default=os.path.join(REPO, "dist"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    bad = 0
    for name, readme, files in PACKS:
        path, missing = build(args.out, name, readme, files)
        size = os.path.getsize(path)
        print("%-12s %8d bytes  %s" % (name, size, path))
        for m in missing:
            print("  MISSING: %s" % m)
            bad = 1

    return bad


if __name__ == "__main__":
    raise SystemExit(main())
