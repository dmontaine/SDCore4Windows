#
# mkdoc.py - render documentation Markdown to single-file HTML
#
# command line: python3 gplbld/mkdoc.py --in DIR|FILE... --out DIR
# eg  python gplbld/mkdoc.py --in docs/sample --out docs/sample
#
# NOTHING CALLS THIS YET, DELIBERATELY.  It is not wired into stage.py or
# sd.iss, because naming a .md in either of those files is what makes
# assert-current watch it (the $shipsAs valve, assert-current.ps1:484), and
# from that moment every documentation edit demands a full cycle before any
# verifier will run.  That is correct once the documentation ships; it is a
# toll nobody should pay while the format is still being judged.  See
# HISTORY.md, "20 Aug 2026 - assert-current demanded a full cycle for a
# markdown file".
#
# WHY HTML AT ALL, AND WHY ONE FILE.  Every Windows machine has a browser, so
# there is nothing to install and no format to explain.  Embedding the CSS
# means there is no asset folder to break, no relative path to get wrong when
# the file is copied off the machine, and nothing to fetch - which matters
# because SD installs on machines that are not on the internet.  The user
# prints to PDF from the browser, so no PDF ships, which the no-binaries rule
# in CLAUDE.md forbids anyway.
#
# WHY A LIBRARY RATHER THAN A HAND-ROLLED CONVERTER.  Markdown looks trivial
# until the first nested list inside a table cell.  python-markdown is pure
# Python, so it installs with pip and adds no binary dependency - which is why
# pandoc was rejected despite being the better converter.
#
# THE CSS IS THE POINT OF THIS SCRIPT, not the conversion.  What makes
# technical documentation look like documentation rather than a rendered
# README is a short list, and it is all here: a measure capped near 72
# characters, a system font stack with no web fonts to fetch or license, real
# table and code-block styling, a table of contents with anchors, and a print
# stylesheet so browser-to-PDF comes out clean.
#

import argparse
import html
import os
import sys

try:
    import markdown
except ImportError:
    sys.stderr.write(
        'mkdoc: the python-markdown library is not installed.\n'
        '       pip install markdown\n'
        '       (setup-devbox.ps1 does not install it yet - the documentation\n'
        '        format has not been ruled on, so nothing depends on it.)\n')
    sys.exit(2)


# ---------------------------------------------------------------------------
# The stylesheet.  Shared by every page; written once, here.
#
# THE MEASURE IS SPLIT ON PURPOSE.  Paragraphs stop at 72 characters because
# that is the readable line length; tables and code blocks are allowed the
# full column, because a keyword table squeezed into prose width wraps in
# every cell and a syntax line that wraps stops being a syntax line.  A single
# max-width for both is the commonest way documentation ends up looking
# amateur in one direction or the other.
# ---------------------------------------------------------------------------

CSS = '''
:root {
  --ink:        #1a1c1f;
  --ink-soft:   #555c66;
  --ink-faint:  #767d87;
  --bg:         #ffffff;
  --panel:      #f5f7f9;
  --rule:       #dde1e6;
  --rule-firm:  #b9c0c8;
  --accent:     #1a5fa8;
  --accent-bg:  #eef4fb;
}

@media (prefers-color-scheme: dark) {
  :root {
    --ink:       #dfe3e8;
    --ink-soft:  #aab2bd;
    --ink-faint: #868f9b;
    --bg:        #16181c;
    --panel:     #1e2127;
    --rule:      #2c3038;
    --rule-firm: #3d434d;
    --accent:    #6fa8e0;
    --accent-bg: #1b2530;
  }
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font-family: "Segoe UI", -apple-system, "Helvetica Neue", Arial, sans-serif;
  font-size: 16px;
  line-height: 1.62;
  -webkit-text-size-adjust: 100%;
}

.masthead {
  border-bottom: 1px solid var(--rule);
  background: var(--panel);
}
.masthead div {
  max-width: 66rem;
  margin: 0 auto;
  padding: 0.7rem 1.5rem;
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: 1rem;
  font-size: 0.85rem;
  color: var(--ink-soft);
}
.masthead strong { color: var(--ink); font-weight: 600; }

.page {
  max-width: 66rem;
  margin: 0 auto;
  padding: 2.5rem 1.5rem 4rem;
  display: grid;
  grid-template-columns: 14rem minmax(0, 1fr);
  gap: 3rem;
}
@media (max-width: 60rem) {
  .page { grid-template-columns: minmax(0, 1fr); gap: 2rem; padding-top: 1.5rem; }
}

/* --- table of contents ------------------------------------------------- */

nav.toc {
  position: sticky;
  top: 1.5rem;
  align-self: start;
  font-size: 0.875rem;
  line-height: 1.45;
  border-left: 2px solid var(--rule);
  padding-left: 1rem;
}
nav.toc p {
  margin: 0 0 0.6rem;
  font-size: 0.72rem;
  letter-spacing: 0.09em;
  text-transform: uppercase;
  color: var(--ink-faint);
}
nav.toc ul { list-style: none; margin: 0; padding: 0; }
nav.toc ul ul { padding-left: 0.9rem; }
nav.toc li { margin: 0.28rem 0; }
nav.toc a { color: var(--ink-soft); text-decoration: none; }
nav.toc a:hover { color: var(--accent); text-decoration: underline; }
@media (max-width: 60rem) {
  nav.toc {
    position: static;
    border-left: 0;
    border: 1px solid var(--rule);
    border-radius: 4px;
    padding: 1rem 1.25rem;
    background: var(--panel);
  }
}

/* --- the prose column -------------------------------------------------- */

main { max-width: 46rem; }
main > p, main > ul, main > ol, main > blockquote { max-width: 72ch; }

h1, h2, h3, h4 { line-height: 1.25; font-weight: 600; }
h1 {
  font-size: 2rem;
  margin: 0 0 0.35rem;
  letter-spacing: -0.01em;
}
.subtitle {
  margin: 0 0 2rem;
  padding-bottom: 1.5rem;
  border-bottom: 1px solid var(--rule);
  color: var(--ink-soft);
  font-size: 1.05rem;
}
h2 {
  font-size: 1.4rem;
  margin: 2.75rem 0 0.9rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--rule);
}
h3 {
  font-size: 1.02rem;
  margin: 2rem 0 0.6rem;
  color: var(--ink-soft);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  font-size: 0.8rem;
}
h4 { font-size: 1rem; margin: 1.5rem 0 0.4rem; }

p { margin: 0 0 1rem; }
ul, ol { margin: 0 0 1rem; padding-left: 1.4rem; }
li { margin: 0.25rem 0; }

a { color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 2px; }

.headerlink {
  margin-left: 0.4rem;
  color: var(--ink-faint);
  text-decoration: none;
  opacity: 0;
  font-weight: 400;
}
h2:hover .headerlink, h3:hover .headerlink { opacity: 1; }

/* --- code -------------------------------------------------------------- */

code, pre, kbd {
  font-family: Consolas, "Cascadia Mono", "DejaVu Sans Mono", monospace;
}
code {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-radius: 3px;
  padding: 0.05em 0.3em;
  font-size: 0.88em;
}
pre {
  background: var(--panel);
  border: 1px solid var(--rule);
  border-left: 3px solid var(--rule-firm);
  border-radius: 3px;
  padding: 0.85rem 1.1rem;
  margin: 0 0 1.25rem;
  overflow-x: auto;
  font-size: 0.875rem;
  line-height: 1.5;
}
pre code { background: none; border: 0; padding: 0; font-size: inherit; }

/* --- tables ------------------------------------------------------------ */

table {
  border-collapse: collapse;
  width: 100%;
  margin: 0 0 1.5rem;
  font-size: 0.94rem;
}
th, td {
  text-align: left;
  vertical-align: baseline;
  padding: 0.5rem 0.9rem 0.5rem 0;
  border-bottom: 1px solid var(--rule);
}
th {
  border-bottom: 2px solid var(--rule-firm);
  font-weight: 600;
  font-size: 0.78rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ink-soft);
}
td:first-child { white-space: nowrap; padding-right: 1.5rem; }
td:first-child code { white-space: nowrap; }

/* --- notes ------------------------------------------------------------- */

blockquote {
  margin: 0 0 1.25rem;
  padding: 0.8rem 1.1rem;
  border: 1px solid var(--rule);
  border-left: 3px solid var(--accent);
  border-radius: 3px;
  background: var(--accent-bg);
}
blockquote p:last-child { margin-bottom: 0; }
blockquote code { background: var(--bg); }

footer {
  max-width: 66rem;
  margin: 0 auto;
  padding: 1.5rem;
  border-top: 1px solid var(--rule);
  color: var(--ink-faint);
  font-size: 0.82rem;
}

/* --- print -------------------------------------------------------------
   The browser IS the PDF exporter, so this is not a nicety.  Colours are
   forced back to black on white because a dark-mode machine would otherwise
   print a dark page, and the sidebar goes because a table of contents with
   no clickable anchors is a column of dead text down the side of every
   page. */

@media print {

  /* THE VARIABLES ARE RESET FIRST, AND THAT IS THE WHOLE POINT OF THIS BLOCK.
     Setting body{color:#000} is not enough: on a machine in dark mode the
     palette above is still the dark one, so every rule that reads a variable -
     the subtitle, the section labels, the table headings, the panel behind a
     code block - keeps printing a pale grey on white.  Found by looking at the
     rendered page, not by reading the CSS.  Overriding the two elements that
     happened to be visible would have left the rest. */

  :root {
    --ink: #000;      --ink-soft: #333;   --ink-faint: #555;
    --bg:  #fff;      --panel: #f4f4f4;
    --rule: #999;     --rule-firm: #333;
    --accent: #000;   --accent-bg: #f4f4f4;
  }

  body { background: #fff; color: #000; font-size: 10.5pt; line-height: 1.45; }
  .masthead, nav.toc { display: none; }
  .page { display: block; max-width: none; padding: 0; }
  main { max-width: none; }
  main > p, main > ul, main > ol, main > blockquote { max-width: none; }
  a { color: #000; text-decoration: none; }
  h2 { break-after: avoid; page-break-after: avoid; }
  h3, h4 { break-after: avoid; page-break-after: avoid; }
  pre, table, blockquote { break-inside: avoid; page-break-inside: avoid; }
  pre, code { border-color: #ccc; }
  th { border-bottom: 1.5pt solid #000; }
  td, th { border-bottom: 0.5pt solid #999; }
  footer { border-top: 0.5pt solid #999; padding: 0.5rem 0; }
}
'''


PAGE = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@TITLE@ - @PRODUCT@</title>
<style>@CSS@</style>
</head>
<body>
<div class="masthead"><div><strong>@PRODUCT@</strong><span>@VERSION@</span></div></div>
<div class="page">
@TOC@<main>
<h1>@TITLE@</h1>
@SUBTITLE@
@BODY@
</main>
</div>
<footer>@PRODUCT@ @VERSION@. Generated from @SOURCE@.</footer>
</body>
</html>
'''


def render(src, product, version):
    """Markdown text -> (title, subtitle, toc html, body html)."""
    md = markdown.Markdown(extensions=['extra', 'meta', 'sane_lists',
                                       'toc'],
                           extension_configs={'toc': {'permalink': '#',
                                                      'toc_depth': '2-3'}})
    body = md.convert(src)
    meta = getattr(md, 'Meta', {}) or {}
    title = ' '.join(meta.get('title', [])) or '(untitled)'
    subtitle = ' '.join(meta.get('subtitle', []))
    return title, subtitle, md.toc, body


def build(path, out_dir, product, version):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()

    # An editor that saves UTF-8 with a BOM leaves it as the first character
    # of the first heading, where it renders as a stray glyph rather than an
    # error.  It is written as chr() rather than as the character itself so that
    # a byte-scan of THIS file does not report a BOM of its own - it did.
    if src[:1] == chr(0xFEFF):
        src = src[1:]
        sys.stdout.write('  note: stripped a UTF-8 BOM from %s\n'
                         % os.path.basename(path))

    title, subtitle, toc, body = render(src, product, version)

    if not body.strip():
        raise RuntimeError('%s rendered to an empty document' % path)

    toc_html = ''
    if toc.count('<a ') >= 3:
        toc_html = ('<nav class="toc"><p>On this page</p>%s</nav>\n'
                    % toc.replace('<div class="toc">', '').replace('</div>', ''))

    sub_html = ''
    if subtitle:
        sub_html = '<p class="subtitle">%s</p>' % html.escape(subtitle)

    page = (PAGE
            .replace('@CSS@', CSS)
            .replace('@PRODUCT@', html.escape(product))
            .replace('@VERSION@', html.escape(version))
            .replace('@TITLE@', html.escape(title))
            .replace('@SUBTITLE@', sub_html)
            .replace('@TOC@', toc_html)
            .replace('@BODY@', body)
            .replace('@SOURCE@', html.escape(os.path.basename(path))))

    stem = os.path.splitext(os.path.basename(path))[0]
    out = os.path.join(out_dir, stem + '.html')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(page)
    return out, title, len(page), toc.count('<a ')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--in', dest='inputs', nargs='+', required=True,
                    metavar='PATH', help='.md files, or directories of them')
    ap.add_argument('--out', required=True, metavar='DIR')
    ap.add_argument('--product', default='SD Core for Windows')
    ap.add_argument('--version', default='W1.0-0')
    args = ap.parse_args()

    sources = []
    for item in args.inputs:
        if os.path.isdir(item):
            sources += [os.path.join(item, n) for n in sorted(os.listdir(item))
                        if n.lower().endswith('.md')]
        else:
            sources.append(item)

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    # An instrument prints what it DID (CLAUDE.md).  The resolved paths matter
    # more than they look: --in docs/sample from the wrong directory finds no
    # .md at all, and a converter that cheerfully writes nothing is exactly
    # the "passes because it did nothing" failure the rule exists to stop.
    sys.stdout.write('mkdoc: markdown %s, python %s\n'
                     % (markdown.__version__, sys.version.split()[0]))
    sys.stdout.write('mkdoc: out  %s\n' % out_dir)
    for s in sources:
        sys.stdout.write('mkdoc: in   %s\n' % os.path.abspath(s))

    if not sources:
        sys.stderr.write('mkdoc: no .md files found - nothing rendered.\n')
        return 1

    for s in sources:
        out, title, size, anchors = build(s, out_dir, args.product,
                                          args.version)
        sys.stdout.write('mkdoc: wrote %s  "%s"  %d bytes, %d anchors\n'
                         % (out, title, size, anchors))

    sys.stdout.write('mkdoc: %d page(s).\n' % len(sources))
    return 0


if __name__ == '__main__':
    sys.exit(main())
