# CV

One source file produces both the web page and the PDF.

## Files

| File | What it is |
| --- | --- |
| `cv.qmd` | The entire CV. This is the only file you edit to add a paper, grant, or student. |
| `preamble.tex` | PDF design: typefaces, colours, the left-hand rail, page furniture. |
| `styles.css` | Web design. Mirrors the PDF layout. |
| `divs.lua` | Tiny filter so `::: {.columns-two}` and `::: {.note}` work in the PDF too. |
| `_quarto.yml` | Sends rendered output to `docs/`, which is what GitHub Pages serves. |
| `docs/` | Generated. Never edit by hand. |

## Rendering

```bash
quarto render
```

That writes `docs/index.html` and `docs/cv.pdf`. In RStudio, opening `cv.qmd`
and pressing Render does the same thing.

The PDF uses XeLaTeX. If you do not have a LaTeX installation:

```bash
quarto install tinytex
```

## Publishing

Repository: `fernandalschumacher/cv`, published at
<https://fernandalschumacher.github.io/cv/>.

Once, in the repository settings on GitHub: Pages → Build and deployment →
Deploy from a branch → `main` / `/docs`.

After that, the loop for every update is:

```bash
quarto render
git add -A && git commit -m "Update CV" && git push
```

Rendering before committing is the one step to remember. Nothing rebuilds
automatically, which is deliberate: what you push is exactly what is served,
and there is no build pipeline to break the week before a deadline.

## Editing the content

Everything in `cv.qmd` is plain markdown.

A dated entry is a definition list. The term becomes the date in the rail:

```markdown
2018–2021
:   **Ph.D. in Statistics.** State University of Campinas (UNICAMP).
    Advisors: Larissa Avila Matos and Victor Hugo Lachos Davila.
```

A publication is a numbered list item, with your own name in `**bold**` and a
student advisee marked `\*`:

```markdown
1. **Schumacher, F. L.**, Matos, L. A. (2026). Title here. *Journal*, 1–20.
```

To set a list in two columns in both outputs, wrap it:

```markdown
::: {.columns-two}
- First item
- Second item
:::
```

## Changing the design

Colours and measurements live at the top of each design file, as tokens.

- Web: the `:root` block in `styles.css` (`--ink`, `--accent`, `--rail`, …).
- PDF: the colour and length definitions near the top of `preamble.tex`.

The PDF uses TeX Gyre Pagella and TeX Gyre Heros because they ship with every
TeX distribution, so the file renders identically anywhere with no font
installation. To switch to something with more character, for example Alegreya,
change the two `\setmainfont` / `\setsansfont` lines in `preamble.tex`; TinyTeX
will fetch the package on the next render.

## Where the links point

`go.osu.edu/schumachercv` points at <https://fernandalschumacher.github.io/cv/>,
and the CV tab of the Google Site points at the same short link. Both are set
once. After that, updating the CV means rendering and pushing, and every link
that already exists in an email signature or grant application resolves to the
new version.

## The date in the PDF header

The PDF stamps "Updated <date>" from the day it was rendered, so it cannot drift
out of sync the way a manually typed date does.
