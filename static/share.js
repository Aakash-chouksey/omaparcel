(function () {
  var MIN = 60000;

  var stamp = document.body.getAttribute("data-expires");
  var out = document.querySelector("[data-exp]");
  if (stamp && out) {
    var until = Number(stamp) * 1000;
    var tick = function () {
      var left = until - Date.now();
      var text;
      if (left <= 0) {
        text = "now";
      } else if (left < 60 * MIN) {
        text = "in " + Math.max(1, Math.floor(left / MIN)) + " min";
      } else if (left < 48 * 60 * MIN) {
        var hours = Math.max(1, Math.round(left / (60 * MIN)));
        text = "in " + hours + (hours === 1 ? " hour" : " hours");
      } else {
        var days = Math.max(1, Math.round(left / (24 * 60 * MIN)));
        text = "in " + days + (days === 1 ? " day" : " days");
      }
      out.textContent = text;
      out.classList.toggle("soon", left > 0 && left < 60 * MIN);
    };
    tick();
    setInterval(tick, MIN);
  }

  var copy = document.querySelector(".copy");
  if (copy) {
    var label = copy.querySelector(".t");
    var idle = label ? label.textContent : "";
    var reset = function () {
      setTimeout(function () { if (label) label.textContent = idle; }, 1600);
    };
    var url = copy.getAttribute("data-copy") || location.href;
    if (location.protocol === "https:" && url.indexOf("http:") === 0) url = location.href;

    var finish = function (message) {
      if (!label) return;
      label.textContent = message;
      reset();
    };

    var fallback = function () {
      var area = document.createElement("textarea");
      area.value = url;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      area.remove();
      finish(ok ? "Copied" : "Copy failed");
    };

    copy.addEventListener("click", function () {
      var settled = false;
      var once = function (message) {
        if (settled) return;
        settled = true;
        finish(message);
      };
      setTimeout(function () { if (!settled) { settled = true; fallback(); } }, 1000);
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(function () { once("Copied"); }, function () {
          if (!settled) { settled = true; fallback(); }
        });
      } else {
        if (!settled) { settled = true; fallback(); }
      }
    });
  }

  var form = document.querySelector(".unlock");
  if (form) {
    var input = form.querySelector(".code-input");
    var submit = form.querySelector(".btn .t");
    if (input) {
      input.addEventListener("input", function () {
        var clean = input.value.replace(/\D/g, "").slice(0, 8);
        if (clean !== input.value) input.value = clean;
      });
    }
    form.addEventListener("submit", function () {
      if (submit) submit.textContent = "Checking";
    });
    window.addEventListener("pageshow", function () {
      if (submit) submit.textContent = "Unlock";
    });
  }
})();
