# Design

The pages in this folder are the only design source for the app. Open `released/index.html` in a
browser: it lists every screen, in dark and light.

| Folder | Holds | Matches |
|---|---|---|
| `released/` | screens as they ship | the app on `main` |
| `next/` | approved changes not yet built | nothing yet; a page is here from the merge that approves it until the merge that builds it |

A change to what a person sees goes in two steps:

1. A pull request changes the page in `next/`. Its merge to `main` is the owner's approval.
2. A second pull request changes the Swift code and moves that page from `next/` to `released/`.

0 colours, sizes, wording or layouts are decided in Swift, in `Docs/`, in an artifact, in another
folder or in a sibling repository. Where a page and the code disagree, the page is right and the
code is fixed.

The mood images are the app's own, in `Sources/Uttrflow/Resources/Mood/`; the pages link to them
and never hold a copy. `uttrflow.icns`, `uttrflow.iconset/` and `uttrflow-logo-original.png` are
build inputs; `ICON.md` says how the icon is made.
