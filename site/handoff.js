// Agent Handoff (SPEC section 16). One payload, read from the page's own prompt text, feeds the
// preview, the clipboard and the manual-copy dialog. No network requests, no storage.
(function () {
  "use strict";

  var root = document.getElementById("handoff");
  var promptEl = document.getElementById("prompt-text");
  var picker = document.getElementById("agent-picker");
  var copyButton = document.getElementById("copy-button");
  var status = document.getElementById("copy-status");
  var dialog = document.getElementById("manual-dialog");
  var manualText = document.getElementById("manual-text");
  var manualClose = document.getElementById("manual-close");
  if (!root || !promptEl || !picker || !copyButton || !status || !dialog || !manualText || !manualClose) return;

  var payload = promptEl.textContent.trim();
  promptEl.textContent = payload;
  manualText.value = payload;

  var choices = Array.prototype.slice.call(picker.querySelectorAll("button[data-agent]"));
  var selected = choices[0];
  var token = 0;
  var timer = 0;

  function label() {
    return "Copy for " + selected.getAttribute("data-agent");
  }

  // Clears the "Copied" label and the status line, and invalidates any copy still in flight.
  function resetFeedback() {
    token += 1;
    window.clearTimeout(timer);
    copyButton.textContent = label();
    status.textContent = "";
  }

  function select(choice) {
    selected = choice;
    choices.forEach(function (c) {
      c.setAttribute("aria-pressed", c === choice ? "true" : "false");
    });
    resetFeedback();
  }

  function openManual() {
    copyButton.textContent = label();
    status.textContent = "Couldn’t access the clipboard.";
    if (!dialog.open) {
      if (typeof dialog.showModal === "function") dialog.showModal();
      else dialog.setAttribute("open", "");
    }
    manualText.focus();
    manualText.select();
  }

  function copy() {
    resetFeedback();
    var mine = token;
    var write;
    try {
      if (!navigator.clipboard || typeof navigator.clipboard.writeText !== "function") {
        throw new Error("clipboard unavailable");
      }
      write = navigator.clipboard.writeText(payload);
    } catch (error) {
      write = Promise.reject(error);
    }
    write.then(
      function () {
        if (mine !== token) return;
        copyButton.textContent = "Copied";
        status.textContent = "Copied. Paste it into " + selected.getAttribute("data-agent") + ".";
        timer = window.setTimeout(function () {
          if (mine !== token) return;
          copyButton.textContent = label();
        }, 1800);
      },
      function () {
        if (mine !== token) return;
        openManual();
      }
    );
  }

  choices.forEach(function (choice) {
    choice.addEventListener("click", function () {
      select(choice);
    });
  });
  copyButton.addEventListener("click", copy);
  manualClose.addEventListener("click", function () {
    dialog.close();
  });
  dialog.addEventListener("close", function () {
    copyButton.focus();
  });

  copyButton.textContent = label();
  picker.hidden = false;
  copyButton.hidden = false;
})();
