// The hold-to-talk key in the hero. It is a simulation: no microphone, no network.
// Hold the key (pointer, Space, Enter or Option) to "say" the next command.
// Release it to see what earshot does. The first command shows without any motion.
(function () {
  var commands = [
    { say: "Slack Ravi, running late", log: [["App", "Slack"], ["Target", "Conversation with Ravi"], ["Action", "Focus the message box, type “running late”"], ["Send", "No. earshot waits for you to say “send”."]] },
    { say: "Open hn.com", log: [["App", "Your default browser"], ["Target", "hn.com"], ["Action", "Open the web address"]] },
    { say: "Click Send", log: [["App", "The front window"], ["Target", "Button with the label “Send”"], ["Action", "Click it. You named Send, so earshot presses it."]] },
    { say: "WhatsApp Mom", log: [["App", "WhatsApp"], ["Target", "Chat with Mom"], ["Action", "Focus the message box. Then you dictate."]] },
    { say: "Show numbers", log: [["App", "The front window"], ["Target", "Each item that you can click"], ["Action", "Show a number on each. Then say “click 4”."]] }
  ];

  var key = document.getElementById("talk");
  var wave = document.getElementById("wave");
  var caption = document.getElementById("caption");
  var log = document.getElementById("log");
  if (!key || !wave || !caption || !log) return;

  var still = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var BARS = Math.max(24, Math.min(140, Math.floor((wave.clientWidth || 600) / 6)));
  var bars = [];
  for (var b = 0; b < BARS; b++) { var i = document.createElement("i"); wave.appendChild(i); bars.push(i); }

  var index = 0;        // command now on screen
  var held = false;
  var typeTimer = null;
  var waveTimer = null;
  var chars = 0;

  function renderLog(rows) {
    log.textContent = "";
    rows.forEach(function (r) {
      var row = document.createElement("div");
      var dt = document.createElement("dt"); dt.textContent = r[0];
      var dd = document.createElement("dd"); dd.textContent = r[1];
      row.appendChild(dt); row.appendChild(dd); log.appendChild(row);
    });
  }

  function animateWave() {
    var t = Date.now() / 140;
    for (var k = 0; k < BARS; k++) {
      var env = Math.sin((k / BARS) * Math.PI);
      var h = 4 + env * (10 + 26 * Math.abs(Math.sin(t + k * 0.55) * Math.cos(t * 0.6 + k * 0.21))) * (0.6 + Math.random() * 0.4);
      bars[k].style.height = h.toFixed(1) + "px";
    }
  }
  function flatWave() { bars.forEach(function (x) { x.style.height = "2px"; }); }

  function press() {
    if (held) return;
    held = true;
    index = (index + 1) % commands.length;
    var cmd = commands[index];
    key.setAttribute("aria-pressed", "true");
    log.classList.add("hidden");
    caption.textContent = "";
    caption.classList.add("typing");
    chars = 0;
    if (still) {
      caption.textContent = "“" + cmd.say + "”";
    } else {
      wave.classList.add("on");
      waveTimer = setInterval(animateWave, 70);
      typeTimer = setInterval(function () {
        if (chars < cmd.say.length) { chars++; caption.textContent = "“" + cmd.say.slice(0, chars); }
      }, 55);
    }
  }

  function release() {
    if (!held) return;
    held = false;
    clearInterval(typeTimer); clearInterval(waveTimer);
    var cmd = commands[index];
    key.setAttribute("aria-pressed", "false");
    wave.classList.remove("on");
    flatWave();
    caption.classList.remove("typing");
    caption.textContent = "“" + cmd.say + "”";
    renderLog(cmd.log);
    log.classList.remove("hidden");
  }

  key.setAttribute("aria-pressed", "false");
  key.addEventListener("pointerdown", function (e) { e.preventDefault(); key.setPointerCapture && key.setPointerCapture(e.pointerId); press(); });
  key.addEventListener("pointerup", release);
  key.addEventListener("pointercancel", release);
  key.addEventListener("lostpointercapture", release);
  key.addEventListener("contextmenu", function (e) { e.preventDefault(); });
  key.addEventListener("keydown", function (e) {
    if (e.key === " " || e.key === "Enter") { e.preventDefault(); if (!e.repeat) press(); }
  });
  key.addEventListener("keyup", function (e) { if (e.key === " " || e.key === "Enter") { e.preventDefault(); release(); } });
  key.addEventListener("blur", release);

  // The right Option key works anywhere on the page, like in the app.
  document.addEventListener("keydown", function (e) {
    if (e.key === "Alt" && e.location === 2 && !e.repeat) { e.preventDefault(); press(); }
  });
  document.addEventListener("keyup", function (e) { if (e.key === "Alt") release(); });
})();
