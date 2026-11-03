// Animated background: a field of dots. Waves move out through it like sound,
// from the hero and from the pointer. It pauses when the tab is hidden.
// If the reader asks for reduced motion, it draws the dots once, with no waves.
(function () {
  "use strict";
  var cv = document.getElementById("field");
  if (!cv || !cv.getContext) return;
  var ctx = cv.getContext("2d");
  var still = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  var ink = getComputedStyle(document.documentElement).getPropertyValue("--ink").trim() || "#F2F2EE";
  var GAP = 26, SPEED = 0.26, BAND = 70, LIFE = 4200;
  var w = 0, h = 0, dpr = 1, waves = [], lastPointer = 0, lastAuto = -99999;

  function size() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    w = window.innerWidth; h = window.innerHeight;
    cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
  }

  function draw(t) {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = ink;
    var oy = -((window.scrollY * 0.2) % GAP);
    var live = waves.filter(function (wv) { return t - wv.t < LIFE; });
    waves = live;
    for (var y = oy; y < h + GAP; y += GAP) {
      for (var x = GAP / 2; x < w; x += GAP) {
        var a = 0.08, dx = 0, dy = 0;
        for (var i = 0; i < live.length; i++) {
          var wv = live[i], age = t - wv.t;
          var r = age * SPEED, ex = x - wv.x, ey = y - wv.y;
          var d = Math.sqrt(ex * ex + ey * ey);
          var off = (d - r) / BAND;
          if (off > -1.5 && off < 1.5) {
            var k = Math.exp(-off * off * 2.2) * (1 - age / LIFE) * wv.s;
            a += 0.55 * k;
            if (d > 0.01) { dx += (ex / d) * 4 * k; dy += (ey / d) * 4 * k; }
          }
        }
        ctx.globalAlpha = Math.min(0.6, a);
        ctx.fillRect(x + dx - 0.9, y + dy - 0.9, 1.8, 1.8);
      }
    }
    ctx.globalAlpha = 1;
  }

  function autoWave(t) {
    // A slow pulse from the hero headline while the hero is on screen.
    if (t - lastAuto < 3200) return;
    var h1 = document.getElementById("hero-title");
    if (!h1) return;
    var r = h1.getBoundingClientRect();
    if (r.bottom < 0) return;
    lastAuto = t;
    waves.push({ x: r.left + r.width * 0.15, y: r.top + r.height * 0.5, t: t, s: 1 });
  }

  var raf = 0, running = false;
  function loop(t) { autoWave(t); draw(t); if (running) raf = requestAnimationFrame(loop); }
  function start() { if (!running && !still) { running = true; raf = requestAnimationFrame(loop); } }
  function stop() { running = false; cancelAnimationFrame(raf); }

  size(); draw(0);
  window.addEventListener("resize", function () { size(); draw(performance.now()); });
  if (still) { window.addEventListener("scroll", function () { draw(0); }, { passive: true }); return; }

  window.addEventListener("pointermove", function (e) {
    var t = performance.now();
    if (t - lastPointer < 450 || waves.length > 7) return;
    lastPointer = t;
    waves.push({ x: e.clientX, y: e.clientY, t: t, s: 0.55 });
  }, { passive: true });
  window.addEventListener("pointerdown", function (e) {
    waves.push({ x: e.clientX, y: e.clientY, t: performance.now(), s: 1 });
  }, { passive: true });
  document.addEventListener("visibilitychange", function () { if (document.hidden) stop(); else start(); });
  start();
})();
