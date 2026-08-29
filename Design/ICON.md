# Where the app icon comes from

`uttrflow.icns` and `uttrflow.iconset/` are **not generated from anything in this
folder**. They are produced by the identity kit, which owns the mark, the wordmark
and the palette, and exports every size the app and the website need from a single
definition.

    <identity kit>/build/build.py   ->   macos/uttrflow.icns
                                         macos/uttrflow.iconset/
                                         macos/menubar/MenuBarIconTemplate*.png

To change the icon, change it there and copy the results in — do not hand-edit the
`.icns`, and do not add a baker here. There used to be one (`_gen_mark.py`), and the
trap it set was that running it silently rebuilt the *previous* icon over the current
one.

The in-app copies live at `Sources/Uttrflow/Resources/`:

- `uttrflow-logo.png` — the mark as a flat alpha shape, tinted at the point of use.
- `MenuBarIconTemplate.png` / `@2x` — the menu bar slot at rest.

`uttrflow-logo-original.png` is kept only as heritage: it is the hand-drawn खि that
the app carried before this mark, and nothing builds from it.
