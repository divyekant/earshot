// Page motion: the hero entrance, section reveals, the privacy wave and the
// phrase retype. Content is visible at rest. If the reader asks for reduced
// motion, this file does nothing.
(function () {
  "use strict";
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  var root = document.documentElement;

  // 1. Hero entrance: the headline lines rise out of a mask, then the film.
  var h1 = document.getElementById("hero-title");
  if (h1 && window.scrollY < 40) {
    var words = h1.textContent.replace(/ /g, " ").trim().split(" ");
    var lines = [words.slice(0, 2).join(" "), words.slice(2, 4).join(" "), words.slice(4).join(" ")];
    h1.textContent = "";
    lines.forEach(function (t) {
      var l = document.createElement("span"); l.className = "hl-line";
      var s = document.createElement("span"); s.textContent = t; l.appendChild(s); h1.appendChild(l);
    });
    h1.setAttribute("aria-label", words.join(" "));
    document.querySelector(".hero").classList.add("intro");
  }

  // 2. Reveals: only for elements below the first screen at load.
  var revealSel = "section h2, .section-lede, .race, .table-wrap, .warning, .term, .start-grid > div:first-child";
  var staggerSel = ".shifts, .scenes, .facts, .rules, .needs";
  var marks = [];
  Array.prototype.forEach.call(document.querySelectorAll(revealSel), function (el) {
    if (el.closest(".hero")) return; el.setAttribute("data-reveal", ""); marks.push(el);
  });
  Array.prototype.forEach.call(document.querySelectorAll(staggerSel), function (el) {
    el.setAttribute("data-stagger", "");
    Array.prototype.forEach.call(el.children, function (c, i) { c.style.setProperty("--i", String(i)); });
    marks.push(el);
  });
  if (window.IntersectionObserver) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.remove("pre"); io.unobserve(e.target); } });
    }, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
    marks.forEach(function (el) {
      if (el.getBoundingClientRect().top > window.innerHeight) { el.classList.add("pre"); io.observe(el); }
    });
  }

  // 3. Privacy wave: loud as the section enters, flat as the headline settles.
  var cv = document.getElementById("inwave");
  if (cv && cv.getContext) {
    var ctx = cv.getContext("2d"), w = 0, h = 0, dpr = 1, seed = [];
    for (var k = 0; k < 400; k++) seed.push(Math.random());
    var ink = getComputedStyle(root).getPropertyValue("--ink").trim() || "#141414";
    var size = function () {
      dpr = Math.min(2, window.devicePixelRatio || 1);
      w = cv.clientWidth; h = cv.clientHeight;
      cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
    };
    var draw = function (t) {
      var r = cv.getBoundingClientRect(), vh = window.innerHeight;
      // p = 0 when the wave enters at the bottom, 1 when it is a third down the screen.
      var p = Math.min(1, Math.max(0, (vh - r.top) / (vh * 0.66)));
      var amp = Math.pow(1 - p, 1.6);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = ink;
      var step = w < 600 ? 5 : 6, n = Math.floor(w / step), mid = h / 2;
      for (var i = 0; i < n; i++) {
        var env = Math.sin((i / n) * Math.PI);
        var v = Math.abs(Math.sin(t / 420 + i * 0.31) * Math.cos(t / 690 + i * 0.13)) * 0.7 + seed[i % 400] * 0.3;
        var bh = Math.max(1.5, amp * env * v * (h - 4));
        ctx.fillRect(i * step, mid - bh / 2, 2, bh);
      }
    };
    var on = false, raf = 0;
    var loop = function (t) { draw(t); if (on) raf = requestAnimationFrame(loop); };
    size(); draw(0);
    window.addEventListener("resize", function () { size(); draw(performance.now()); });
    if (window.IntersectionObserver) new IntersectionObserver(function (es) {
      on = es[0].isIntersecting; cancelAnimationFrame(raf); if (on) raf = requestAnimationFrame(loop);
    }).observe(cv);
  }

  // 4. Phrases: point at a phrase and it is "said" again.
  Array.prototype.forEach.call(document.querySelectorAll(".phrases li"), function (li) {
    var q = li.querySelector("q"); if (!q) return;
    var full = q.textContent, timer = null;
    li.addEventListener("mouseenter", function () {
      clearInterval(timer); var i = 0; q.classList.add("retype"); q.textContent = "";
      timer = setInterval(function () {
        i++; q.textContent = full.slice(0, i);
        if (i >= full.length) { clearInterval(timer); setTimeout(function () { q.classList.remove("retype"); }, 500); }
      }, 32);
    });
  });
})();
