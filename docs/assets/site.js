// moonregex site — shared behaviour: theme, live matcher, tabs, scrollspy,
// copy buttons, reveal-on-scroll, and the showcase demos.
(function () {
  "use strict";

  var root = document.documentElement;
  var THEME_KEY = "moonregex-theme";

  // Reveal-on-scroll needs the class to be present before the styles apply;
  // without this script the CSS leaves everything visible.
  root.classList.add("js");

  // ---- theme -------------------------------------------------------------
  function stored() {
    try { return localStorage.getItem(THEME_KEY); } catch (e) { return null; }
  }
  function systemPrefersLight() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches;
  }
  function apply(theme) {
    root.setAttribute("data-theme", theme);
    var btn = document.querySelector(".theme-toggle");
    if (btn) {
      var label = theme === "light" ? "Switch to the night theme" : "Switch to the day theme";
      btn.setAttribute("aria-label", label);
      btn.setAttribute("title", label);
      btn.setAttribute("aria-pressed", theme === "light" ? "true" : "false");
    }
  }
  apply(stored() || (systemPrefersLight() ? "light" : "dark"));

  document.addEventListener("click", function (event) {
    var btn = event.target.closest(".theme-toggle");
    if (!btn) return;
    var next = root.getAttribute("data-theme") === "light" ? "dark" : "light";
    apply(next);
    try { localStorage.setItem(THEME_KEY, next); } catch (e) {}
  });

  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: light)").addEventListener("change", function (event) {
      if (!stored()) apply(event.matches ? "light" : "dark");
    });
  }

  // ---- live matcher ------------------------------------------------------
  var SAMPLE = "the moonregex matcher scans moonbit and moonlight for every moon-shaped word in the text";
  var patEl = document.getElementById("pat");
  if (patEl) {
    var textEl = document.getElementById("text");
    var statEl = document.getElementById("stat");
    var fi = document.getElementById("fi");
    var fg = document.getElementById("fg");
    var flags = { i: false, g: true };

    var escapeHtml = function (s) {
      return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    };

    var highlight = function (s, spans) {
      if (!spans.length) return escapeHtml(s);
      spans.sort(function (a, b) { return a[0] - b[0]; });
      var html = "", cur = 0;
      for (var i = 0; i < spans.length; i++) {
        var start = spans[i][0], end = start + spans[i][1];
        if (start < cur) continue;
        html += escapeHtml(s.slice(cur, start));
        html += "<mark>" + escapeHtml(s.slice(start, end)) + "</mark>";
        cur = end;
      }
      return html + escapeHtml(s.slice(cur));
    };

    var render = function () {
      var raw = patEl.value;
      var fl = (flags.i ? "i" : "") + (flags.g ? "g" : "");
      var re;
      try { re = new RegExp(raw, fl); }
      catch (e) { textEl.innerHTML = escapeHtml(SAMPLE); statEl.innerHTML = "invalid pattern"; return; }
      if (!re.global) {
        var m = re.exec(SAMPLE);
        if (!m) { textEl.innerHTML = escapeHtml(SAMPLE); statEl.innerHTML = "<b>0</b> matches"; return; }
        textEl.innerHTML = highlight(SAMPLE, [[m.index, m[0].length]]);
        statEl.innerHTML = "<b>1</b> match";
        return;
      }
      var spans = [], mm;
      while ((mm = re.exec(SAMPLE)) !== null) {
        spans.push([mm.index, mm[0].length]);
        if (mm.index === re.lastIndex) re.lastIndex++;
      }
      textEl.innerHTML = highlight(SAMPLE, spans);
      statEl.innerHTML = "<b>" + spans.length + "</b> match" + (spans.length === 1 ? "" : "es");
    };

    patEl.addEventListener("input", render);
    fi.addEventListener("click", function () { flags.i = !flags.i; fi.classList.toggle("active"); render(); });
    fg.addEventListener("click", function () { flags.g = !flags.g; fg.classList.toggle("active"); render(); });
    render();
  }

  // ---- code tabs ---------------------------------------------------------
  var tabs = document.getElementById("tabs");
  var codeEl = document.getElementById("codeblock");
  if (tabs && codeEl && window.MOONREGEX_CODE) {
    var setCode = function (key) { codeEl.innerHTML = window.MOONREGEX_CODE[key] || ""; };
    tabs.addEventListener("click", function (event) {
      var btn = event.target.closest("button[data-k]");
      if (!btn) return;
      Array.prototype.forEach.call(tabs.children, function (b) { b.classList.remove("active"); });
      btn.classList.add("active");
      setCode(btn.getAttribute("data-k"));
    });
    setCode(tabs.querySelector("button.active").getAttribute("data-k"));
  }

  // ---- scrollspy ---------------------------------------------------------
  var sideLinks = [].slice.call(document.querySelectorAll('.side a[href^="#"]'));
  if (sideLinks.length) {
    var heads = sideLinks.map(function (a) { return document.getElementById(a.getAttribute("href").slice(1)); });
    var mark = function () {
      var at = 0;
      for (var i = 0; i < heads.length; i++) {
        if (heads[i] && heads[i].getBoundingClientRect().top < 150) at = i;
      }
      sideLinks.forEach(function (a, i) { a.classList.toggle("on", i === at); });
    };
    document.addEventListener("scroll", mark, { passive: true });
    mark();
  }

  // ---- copy buttons ------------------------------------------------------
  document.addEventListener("click", function (event) {
    var btn = event.target.closest(".copy");
    if (!btn) return;
    var target = document.querySelector(btn.getAttribute("data-copy"));
    if (!target) return;
    var text = target.textContent.trim();
    var done = function () {
      var old = btn.textContent;
      btn.textContent = "copied";
      setTimeout(function () { btn.textContent = old; }, 1400);
    };
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () {});
    else done();
  });

  // ---- reveal ------------------------------------------------------------
  var reveal = [].slice.call(document.querySelectorAll(".reveal"));
  var showAll = function () { reveal.forEach(function (el) { el.classList.add("in"); }); };
  if (reveal.length && "IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveal.forEach(function (el) { io.observe(el); });
    // Safety net: if the observer never fires (a hidden tab, an odd browser),
    // the page still shows its content.
    setTimeout(showAll, 1600);
  } else {
    showAll();
  }
})();
