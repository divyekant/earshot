// Plays the example commands in the hero window.
// If the reader asks for reduced motion, the first example stays still.
(function () {
  var examples = [
    ["Slack Ravi, running late", "→ Slack · Ravi · types \"running late\""],
    ["Open hn.com", "→ Browser · hn.com"],
    ["Click Send", "→ Clicks \"Send\" in the front window"],
    ["WhatsApp Mom", "→ WhatsApp · Mom · message box has the focus"],
    ["Show numbers", "→ Numbers on 12 items. Say \"click 4\"."]
  ];
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  var key = document.getElementById("demo-key");
  var bars = document.getElementById("demo-bars");
  var text = document.getElementById("demo-text");
  var result = document.getElementById("demo-result");
  if (!key || !bars || !text || !result) return;

  var i = 0;
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  async function play() {
    for (;;) {
      var ex = examples[i % examples.length];
      result.classList.add("hide");
      text.textContent = "";
      await wait(700);
      key.classList.add("down");
      bars.classList.add("on");
      await wait(350);
      for (var c = 1; c <= ex[0].length; c++) {
        text.textContent = ex[0].slice(0, c);
        await wait(45 + Math.random() * 45);
      }
      await wait(450);
      key.classList.remove("down");
      bars.classList.remove("on");
      await wait(250);
      result.textContent = ex[1];
      result.classList.remove("hide");
      await wait(2600);
      i++;
    }
  }
  play();
})();
