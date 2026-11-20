"""Convert the site's Manrope font into PDF-embeddable static fonts."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = Path(__file__).resolve().parents[1] / "faculty-portal"
source = root / "node_modules/@fontsource-variable/manrope/files/manrope-latin-wght-normal.woff2"
target = root / "server-assets/commercial"
target.mkdir(parents=True, exist_ok=True)
for name, weight in [("Regular", 400), ("SemiBold", 600), ("Bold", 700)]:
    font = instantiateVariableFont(TTFont(source), {"wght": weight}, inplace=False)
    font.flavor = None
    for name_id, value in [(1, "Manrope"), (2, name), (4, f"Manrope {name}"), (6, f"Manrope-{name}")]:
        font["name"].setName(value, name_id, 3, 1, 0x409)
        font["name"].setName(value, name_id, 1, 0, 0)
    font.save(target / f"Manrope-{name}.ttf")
print("Prepared server-side Manrope fonts")
