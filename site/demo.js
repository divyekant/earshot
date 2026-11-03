// The hero film: spoken commands and what earshot does, on a drawn Mac screen.
// It is a simulation. It uses no microphone and no network.
// The film plays only while it is on screen. If the reader asks for reduced
// motion, it shows each scene in its final state and moves on only on a click.
(function () {
  "use strict";

  var $ = function (id) { return document.getElementById(id); };
  var film = $("film"), screen = $("screen"), stage = $("stage");
  if (!film || !screen || !stage) return;

  var still = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  var key = $("talk"), wave = $("wave"), caption = $("caption"), chapters = $("chapters");
  var pointer = $("pointer"), ring = $("ring"), ripple = $("ripple"), note = $("note"), noteText = $("note-text");
  var mbarApp = $("mbar-app"), glyph = $("mbar-glyph");

  // Scale the 1200 x 720 stage to the width of the screen.
  var scale = 1;
  function fit() {
    scale = screen.clientWidth / 1200;
    stage.style.transform = "scale(" + scale + ")";
    screen.style.height = Math.round(720 * scale) + "px";
  }
  fit();
  if (window.ResizeObserver) new ResizeObserver(fit).observe(screen); else window.addEventListener("resize", fit);

  // Voice wave
  var bars = [];
  (function () {
    var n = Math.max(30, Math.min(120, Math.floor((wave.clientWidth || 500) / 5)));
    for (var i = 0; i < n; i++) { var b = document.createElement("i"); wave.appendChild(b); bars.push(b); }
  })();
  var waveTimer = null;
  function waveOn(on) {
    clearInterval(waveTimer);
    wave.classList.toggle("on", on);
    glyph.classList.toggle("live", on);
    key.classList.toggle("down", on);
    if (!on || still) { bars.forEach(function (b) { b.style.height = "2px"; }); return; }
    waveTimer = setInterval(function () {
      var t = Date.now() / 130, n = bars.length;
      for (var k = 0; k < n; k++) {
        var env = Math.sin((k / n) * Math.PI);
        bars[k].style.height = (3 + env * (6 + 14 * Math.abs(Math.sin(t + k * 0.5) * Math.cos(t * 0.7 + k * 0.23))) * (0.55 + Math.random() * 0.45)).toFixed(1) + "px";
      }
    }, 70);
  }

  // Run control: a new run cancels the old one.
  var STOP = {};
  var runId = 0;
  function sleep(ms, id) {
    return new Promise(function (resolve, reject) {
      setTimeout(function () { if (id !== runId) reject(STOP); else resolve(); }, still ? 0 : ms);
    });
  }

  // Geometry in stage units
  function box(el) {
    var r = el.getBoundingClientRect(), s = stage.getBoundingClientRect();
    return { x: (r.left - s.left) / scale, y: (r.top - s.top) / scale, w: r.width / scale, h: r.height / scale };
  }
  function pointTo(el, fx, fy) {
    var b = box(el);
    var x = b.x + b.w * (fx == null ? 0.5 : fx), y = b.y + b.h * (fy == null ? 0.5 : fy);
    pointer.style.transform = "translate(" + x.toFixed(1) + "px," + y.toFixed(1) + "px)";
    return { x: x, y: y };
  }
  function ringOn(el) {
    var b = box(el);
    ring.style.transform = "translate(" + (b.x - 5).toFixed(1) + "px," + (b.y - 5).toFixed(1) + "px)";
    ring.style.width = (b.w + 10).toFixed(1) + "px";
    ring.style.height = (b.h + 10).toFixed(1) + "px";
    ring.classList.add("show");
  }
  function ringOff() { ring.classList.remove("show"); }
  function click(p) {
    ripple.style.left = p.x + "px"; ripple.style.top = p.y + "px";
    ripple.classList.remove("go"); void ripple.offsetWidth; ripple.classList.add("go");
  }
  function showNote(text) { noteText.textContent = text; note.classList.add("show"); }
  function hideNote() { note.classList.remove("show"); }

  async function typeInto(el, text, ms, id) {
    el.classList.add("caret");
    if (still) { el.textContent = text; return; }
    for (var i = 1; i <= text.length; i++) { el.textContent = text.slice(0, i); await sleep(ms, id); }
  }
  async function say(text, id) {
    caption.textContent = "";
    caption.classList.add("typing");
    waveOn(true);
    await sleep(260, id);
    if (still) caption.textContent = "“" + text + "”";
    else for (var i = 1; i <= text.length; i++) { caption.textContent = "“" + text.slice(0, i); await sleep(46, id); }
    caption.textContent = "“" + text + "”";
    await sleep(380, id);
    caption.classList.remove("typing");
    waveOn(false);
    await sleep(160, id);
  }

  // Scenes
  var wins = {};
  Array.prototype.forEach.call(stage.querySelectorAll(".win"), function (w) { wins[w.getAttribute("data-scene")] = w; });

  var scenes = [
    {
      name: "chat", app: "Slack",
      reset: function () {
        $("c-ravi").classList.remove("on");
        $("c-head").textContent = "General";
        $("c-ph").textContent = "Message #general"; $("c-ph").hidden = false;
        $("c-typed").textContent = ""; $("c-typed").classList.remove("caret");
        $("c-chip").classList.remove("show");
        $("c-msgs").innerHTML = '<p class="msg"><b>Priya</b>Standup moved to 10:30.</p><p class="msg"><b>Sam</b>Deck is in the shared folder.</p>';
      },
      run: async function (id) {
        await say("Slack Ravi, running late", id);
        pointTo($("c-ravi"), 0.3, 0.6);
        await sleep(420, id);
        $("c-ravi").classList.add("on");
        $("c-head").textContent = "Ravi";
        $("c-msgs").innerHTML = '<p class="msg"><b>Ravi</b>Table for four at 8. Are you close?</p>';
        $("c-ph").textContent = "Message Ravi";
        await sleep(260, id);
        ringOn($("c-box"));
        $("c-ph").hidden = true;
        await typeInto($("c-typed"), "running late", 38, id);
        $("c-chip").classList.add("show");
        showNote("Slack · Ravi · typed, not sent");
        await sleep(1900, id);
        hideNote();
        await say("Send", id);
        ringOff(); $("c-chip").classList.remove("show");
        var m = document.createElement("p"); m.className = "msg mine";
        var b = document.createElement("b"); b.textContent = "You"; m.appendChild(b); m.appendChild(document.createTextNode("running late"));
        $("c-msgs").appendChild(m);
        $("c-typed").textContent = ""; $("c-typed").classList.remove("caret");
        $("c-ph").hidden = false;
        showNote("Sent, because you said “send”");
        await sleep(2000, id);
      }
    },
    {
      name: "web", app: "Chrome",
      reset: function () {
        $("w-typed").textContent = ""; $("w-typed").classList.remove("caret"); $("w-ph").hidden = false;
        $("w-list").classList.remove("show"); $("w-two").classList.remove("hit");
        $("w-results").classList.remove("gone"); $("w-article").classList.remove("come");
      },
      run: async function (id) {
        await say("Search for trains to Lisbon", id);
        ringOn($("w-search")); $("w-ph").hidden = true;
        await typeInto($("w-typed"), "trains to Lisbon", 34, id);
        await sleep(300, id);
        $("w-list").classList.add("show");
        showNote("Chrome · typed in the search field");
        await sleep(1400, id);
        hideNote(); ringOff();
        await say("Open the second result", id);
        var p = pointTo($("w-two").querySelector("b"), 0.2, 0.6);
        await sleep(560, id);
        $("w-two").classList.add("hit"); click(p);
        await sleep(320, id);
        $("w-results").classList.add("gone"); $("w-article").classList.add("come");
        showNote("Chrome · clicked result 2");
        await sleep(2000, id);
      }
    },
    {
      name: "menu", app: "Notes",
      reset: function () {
        $("d-doc").classList.remove("selected");
        $("m-edit").classList.remove("open"); $("menu-edit").classList.remove("open"); $("m-selectall").classList.remove("hit");
      },
      run: async function (id) {
        await say("Select all", id);
        $("m-edit").classList.add("open"); $("menu-edit").classList.add("open");
        await sleep(360, id);
        $("m-selectall").classList.add("hit");
        await sleep(420, id);
        $("m-edit").classList.remove("open"); $("menu-edit").classList.remove("open"); $("m-selectall").classList.remove("hit");
        $("d-doc").classList.add("selected");
        showNote("Notes · Edit › Select All");
        await sleep(2200, id);
      }
    },
    {
      name: "numbers", app: "Photos",
      reset: function () {
        Array.prototype.forEach.call(stage.querySelectorAll(".badge"), function (b) { b.remove(); });
        Array.prototype.forEach.call($("n-grid").children, function (c) { c.classList.remove("picked"); });
      },
      run: async function (id) {
        await say("Show numbers", id);
        var targets = Array.prototype.slice.call($("n-tools").children).concat(Array.prototype.slice.call($("n-grid").children));
        var badges = targets.map(function (t, i) { var b = document.createElement("span"); b.className = "badge"; b.textContent = String(i + 1); t.appendChild(b); return b; });
        for (var i = 0; i < badges.length; i++) { badges[i].classList.add("show"); await sleep(45, id); }
        showNote("Photos · " + badges.length + " items");
        await sleep(1100, id);
        hideNote();
        await say("Click 7", id);
        var seven = badges[6];
        seven.classList.add("hit");
        var p = pointTo(seven, 0.5, 0.5);
        await sleep(560, id);
        click(p);
        targets[6].classList.add("picked");
        badges.forEach(function (b) { if (b !== seven) b.classList.remove("show"); });
        await sleep(300, id);
        seven.classList.remove("show");
        showNote("Photos · clicked item 7");
        await sleep(2000, id);
      }
    },
    {
      name: "dictate", app: "Mail",
      reset: function () { $("m-typed").textContent = ""; $("m-typed").classList.remove("caret"); },
      run: async function (id) {
        var text = "Hi Sam, the deck is ready. I moved the demo to Thursday at ten.";
        ringOn($("m-body"));
        await say(text, id);
        await typeInto($("m-typed"), text, 14, id);
        showNote("Mail · typed 13 words, no Return");
        await sleep(2400, id);
      }
    }
  ];

  // Chapter marks
  scenes.forEach(function (s) { var li = document.createElement("li"); li.setAttribute("aria-hidden", "true"); chapters.appendChild(li); });

  var index = -1;
  var playing = false;

  function enter(i) {
    var s = scenes[i];
    Object.keys(wins).forEach(function (k) { wins[k].classList.toggle("show", k === s.name); });
    scenes.forEach(function (o) { o.reset(); });
    hideNote(); ringOff();
    mbarApp.textContent = s.app;
    Array.prototype.forEach.call(chapters.children, function (li, k) {
      li.classList.toggle("done", k < i); li.classList.toggle("now", k === i);
    });
  }

  async function play(from) {
    var id = ++runId;
    playing = true;
    var i = from;
    try {
      for (;;) {
        index = i % scenes.length;
        enter(index);
        await sleep(650, id);
        await scenes[index].run(id);
        if (still) { playing = false; return; }
        i++;
      }
    } catch (e) {
      if (e !== STOP) throw e;
    }
  }

  function stop() { runId++; playing = false; waveOn(false); caption.classList.remove("typing"); }

  // The key skips to the next command.
  key.addEventListener("click", function () { stop(); play(index + 1); });

  // Play only while the film is on screen and the tab is visible.
  var visible = true;
  function update() {
    var shouldPlay = visible && !document.hidden;
    if (still) { if (index < 0) { play(0); } return; }
    if (shouldPlay && !playing) play(index < 0 ? 0 : index);
    else if (!shouldPlay && playing) stop();
  }
  if (window.IntersectionObserver) {
    new IntersectionObserver(function (es) { visible = es[0].isIntersecting; update(); }, { threshold: 0.25 }).observe(film);
  }
  document.addEventListener("visibilitychange", update);
  update();

  // Timing chart: run once when it comes into view.
  var race = $("race");
  if (race) {
    if (!window.IntersectionObserver || still) race.classList.add("run");
    else new IntersectionObserver(function (es, o) {
      if (es[0].isIntersecting) { race.classList.add("run"); o.disconnect(); }
    }, { threshold: 0.4 }).observe(race);
  }
})();
