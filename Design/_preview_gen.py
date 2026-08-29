"""Standalone render of an artboard, for eyeballing it outside the canvas host.

    python3 _preview_gen.py Identity   # -> _preview.html
"""
import base64, glob, io, re, sys

from PIL import Image

name = sys.argv[1] if len(sys.argv) > 1 else "Identity"
src = open(f"{name}.dc.html").read()
style = re.search(r"<style>(.*?)</style>", src, re.S).group(1)
stage = re.search(r'(<div class="stage.*?)\n</x-dc>', src, re.S).group(1)
html = f'<!doctype html><meta charset="utf-8"><style>{style}</style>{stage}'
for png in glob.glob("*.png"):
    # Thumbnailed, or the inlined artwork outgrows what a preview can carry.
    im = Image.open(png)
    im.thumbnail((256, 256), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG")
    uri = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()
    html = html.replace(f"./{png}", uri).replace(f'src="{png}"', f'src="{uri}"')
open("_preview.html", "w").write(html)
print(f"_preview.html <- {name} ({len(html) // 1024} KB)")
