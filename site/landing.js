(function () {
  var root = document.documentElement;
  var cost = document.getElementById("cost");
  var note = document.getElementById("note");
  var src = document.getElementById("src");
  var chip = document.querySelector(".chip-text");

  var plans = {
    tunnelshare: {
      name: "TunnelShare",
      cost: "$0",
      note: "No transfer cap. Folder manifest, expiry, and an optional code. The bytes never leave your disk.",
      href: "#how",
      label: "How it works",
      ships: 0,
      tone: 0
    },
    wetransfer: {
      name: "WeTransfer",
      cost: "$144",
      note: "200 GB per transfer, 1 TB of storage, and every byte waits on their servers.",
      href: "https://wetransfer.com/pricing",
      label: "WeTransfer pricing",
      ships: 3,
      tone: 2
    },
    ngrok: {
      name: "ngrok",
      cost: "$96",
      note: "Annual billing. 5 GB a month included, then $0.10 per GB. The link passes through ngrok.",
      href: "https://ngrok.com/pricing",
      label: "ngrok pricing",
      ships: 2,
      tone: 1
    },
    tailscale: {
      name: "Tailscale",
      cost: "$0",
      note: "Personal plan. The sender installs Tailscale and turns on Funnel. The recipient needs nothing.",
      href: "https://tailscale.com/pricing",
      label: "Tailscale pricing",
      ships: 0,
      tone: 0
    }
  };

  function apply(id) {
    var plan = plans[id];
    if (!plan) return;
    root.dataset.plan = id;
    root.dataset.tone = String(plan.tone);
    root.dataset.ships = String(plan.ships);
    if (cost) cost.textContent = plan.cost;
    if (note) note.textContent = plan.note;
    if (src) {
      src.href = plan.href;
      src.textContent = plan.label;
    }
    if (chip) {
      chip.textContent = plan.name + " / " + plan.cost + " a year";
    }
  }

  var radios = document.querySelectorAll('input[name="plan"]');
  for (var i = 0; i < radios.length; i++) {
    radios[i].addEventListener("change", function (event) {
      if (event.target.checked) apply(event.target.value);
    });
  }

  var buttons = document.querySelectorAll("[data-copy]");
  for (var j = 0; j < buttons.length; j++) {
    (function (button) {
      var idle = button.textContent;
      var timer;

      function finish(message) {
        button.textContent = message;
        clearTimeout(timer);
        timer = setTimeout(function () { button.textContent = idle; }, 1600);
      }

      function fallback() {
        var area = document.createElement("textarea");
        area.value = button.getAttribute("data-copy") || "";
        area.setAttribute("readonly", "");
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.appendChild(area);
        area.select();
        var ok = false;
        try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
        area.remove();
        finish(ok ? "Copied" : "Press Ctrl C");
      }

      button.addEventListener("click", function () {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(button.getAttribute("data-copy") || "").then(
            function () { finish("Copied"); },
            fallback
          );
        } else {
          fallback();
        }
      });
    })(buttons[j]);
  }
})();
