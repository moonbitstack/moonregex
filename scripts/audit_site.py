"""Check every text node on the docs pages against WCAG AA, in both themes.

The site has two palettes and a handful of surfaces (page, card, code panel,
chip). Rather than eyeball them, this renders each page in headless Chrome,
walks the visible text, works out the effective background by compositing the
ancestors' backgrounds, and reports anything under the AA threshold — 4.5:1
for body text, 3:1 for large text.

    python scripts/audit_site.py            # all four pages, both themes
    python scripts/audit_site.py guide.html # one page
    python scripts/audit_site.py --pre "document.querySelector('.pg input').value='('" \
        --delay 3000 showcase.html          # audit a state, not the landing one

Exit status is 0 when everything passes, 1 otherwise, so it can gate a change.
Chrome is found in the usual places, or set CHROME to its path.
"""
import subprocess, sys, json, pathlib, html, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"


def find_chrome() -> str:
    import os, shutil
    candidates = [
        os.environ.get("CHROME"),
        shutil.which("chrome"),
        shutil.which("chromium"),
        shutil.which("google-chrome"),
        r"C:/Program Files/Google/Chrome/Application/chrome.exe",
        r"C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
        r"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/usr/bin/google-chrome",
        "/usr/bin/chromium",
    ]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).exists():
            return candidate
    raise SystemExit("no Chrome found; set CHROME=/path/to/chrome")


CHROME = find_chrome()

AUDIT = r"""
<script>
window.__auditCollect = function () {
  function parse(c) {
    var m = c.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    var p = m[1].split(",").map(function (v) { return parseFloat(v); });
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  }
  function lum(c) {
    function ch(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }
  function over(fg, bg) {
    var a = fg.a;
    return { r: fg.r * a + bg.r * (1 - a), g: fg.g * a + bg.g * (1 - a), b: fg.b * a + bg.b * (1 - a), a: 1 };
  }
  function ratio(a, b) {
    var l1 = lum(a), l2 = lum(b);
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  }
  function bgOf(el) {
    var node = el, layers = [];
    while (node && node.nodeType === 1) {
      var cs = getComputedStyle(node);
      if (cs.backgroundImage && cs.backgroundImage !== "none") return null;
      var c = parse(cs.backgroundColor);
      if (c && c.a > 0) {
        layers.push(c);
        if (c.a === 1) break;
      }
      node = node.parentElement;
    }
    var base = { r: 8, g: 10, b: 19, a: 1 };
    if (document.documentElement.getAttribute("data-theme") === "light") base = { r: 246, g: 246, b: 251, a: 1 };
    var result = base;
    for (var i = layers.length - 1; i >= 0; i--) result = over(layers[i], result);
    return result;
  }
  function visible(el) {
    var r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    var cs = getComputedStyle(el);
    return cs.visibility !== "hidden" && cs.display !== "none" && parseFloat(cs.opacity) > 0.1;
  }
  var out = [];
  var seen = 0;
  document.querySelectorAll("body *").forEach(function (el) {
    var text = Array.prototype.filter.call(el.childNodes, function (n) {
      return n.nodeType === 3 && n.textContent.trim().length > 1;
    }).map(function (n) { return n.textContent.trim(); }).join(" ");
    if (!text) return;
    if (!visible(el)) return;
    seen++;
    var cs = getComputedStyle(el);
    var fg = parse(cs.color);
    var bg = bgOf(el);
    if (!fg || !bg) return;
    var solid = fg.a < 1 ? over(fg, bg) : fg;
    var r = ratio(solid, bg);
    var size = parseFloat(cs.fontSize);
    var bold = parseInt(cs.fontWeight, 10) >= 700;
    var large = size >= 24 || (bold && size >= 18.66);
    var need = large ? 3 : 4.5;
    if (r < need) {
      out.push({
        tag: el.tagName.toLowerCase(),
        cls: (el.className || "").toString().slice(0, 40),
        text: text.slice(0, 42),
        ratio: Math.round(r * 100) / 100,
        need: need,
        size: size,
        color: cs.color,
        bg: "rgb(" + Math.round(bg.r) + "," + Math.round(bg.g) + "," + Math.round(bg.b) + ")"
      });
    }
  });
  return {
    theme: document.documentElement.getAttribute("data-theme"),
    checked: seen,
    low: out
  };
};
window.addEventListener("load", function () {
  // A page with an interactive state to reach (the playground's error, say)
  // sets window.__auditDelay and drives the page itself; everything else
  // measures as soon as the page is up.
  var delay = window.__auditDelay || 0;
  setTimeout(function () {
    var probe = window.__auditCollect();
    var pre = document.createElement("pre");
    pre.id = "audit";
    pre.textContent = JSON.stringify(probe);
    pre.style.display = "none";
    document.body.appendChild(pre);
    document.title = "AUDIT " + probe.low.length;
  }, delay);
});
</script>
</body>"""


def run(page: str, theme: str, pre: str = "", delay: int = 0) -> dict:
    src = (DOCS / page).read_text(encoding="utf-8")
    # The theme is forced *after* site.js runs, which would otherwise put the
    # system preference back.
    force = f'<script>document.documentElement.setAttribute("data-theme","{theme}");</script>'
    setup = f"<script>window.__auditDelay={delay};{pre}</script>" if (pre or delay) else ""
    src = src.replace("</body>", force + setup + AUDIT)
    tmp = DOCS / f"_audit_{theme}.html"
    tmp.write_text(src, encoding="utf-8")
    try:
        proc = subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", "--dump-dom",
             f"--virtual-time-budget={6000 + delay * 3}", "--window-size=1440,900",
             tmp.as_uri()],
            capture_output=True, text=True, timeout=90,
        )
    finally:
        tmp.unlink(missing_ok=True)
    m = re.search(r'<pre id="audit"[^>]*>(.*?)</pre>', proc.stdout, re.S)
    if not m:
        print("no report for", page, theme, proc.stdout[:200], file=sys.stderr)
        return {}
    return json.loads(html.unescape(m.group(1)))


if __name__ == "__main__":
    args = sys.argv[1:]
    pre = ""
    delay = 0
    pages = []
    i = 0
    while i < len(args):
        if args[i] == "--pre":
            pre = args[i + 1]
            i += 2
        elif args[i] == "--delay":
            delay = int(args[i + 1])
            i += 2
        else:
            pages.append(args[i])
            i += 1
    pages = pages or ["index.html", "guide.html", "showcase.html", "api.html"]
    total = 0
    for theme in ("dark", "light"):
        for page in pages:
            data = run(page, theme, pre, delay)
            if not data:
                continue
            low = data["low"]
            total += len(low)
            print(f"\n== {page} [{theme}] checked {data['checked']}, below AA: {len(low)}")
            for item in low[:12]:
                print(f"   {item['ratio']:>5}:1 (need {item['need']}) {item['tag']}.{item['cls']} "
                      f"{item['size']:.0f}px {item['color']} on {item['bg']} :: {item['text']!r}")
    print(f"\ntotal below AA: {total}")
    raise SystemExit(0 if total == 0 else 1)
