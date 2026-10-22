(function () {
  "use strict";

  var root = document.documentElement;
  var hero = document.querySelector(".hero");
  var canvas = document.querySelector("[data-tunnel]");
  var chip = document.querySelector(".chip-text");
  var cost = document.getElementById("cost");
  var note = document.getElementById("note");
  var src = document.getElementById("src");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");

  var plans = {
    tunnelshare: {
      cost: "$0",
      note: "No transfer cap, no toll gates, no storage. The bytes never leave your disk.",
      href: "#how",
      label: "How it works",
      tolls: 0,
      speed: 1
    },
    wetransfer: {
      cost: "$144",
      note: "Three gates and a warehouse. 200 GB per transfer, 1 TB of storage, and every byte sits on their servers.",
      href: "https://wetransfer.com/pricing",
      label: "WeTransfer pricing",
      tolls: 3,
      speed: 0.62
    },
    ngrok: {
      cost: "$96",
      note: "Two gates and a meter. 5 GB a month included, then $0.10 per GB.",
      href: "https://ngrok.com/pricing",
      label: "ngrok pricing",
      tolls: 2,
      speed: 0.8
    },
    tailscale: {
      cost: "$0",
      note: "No tolls, one catch. The sender installs Tailscale and turns on Funnel.",
      href: "https://tailscale.com/pricing",
      label: "Tailscale pricing",
      tolls: 0,
      speed: 1
    }
  };

  function smoothstep(a, b, x) {
    var t = Math.max(0, Math.min(1, (x - a) / (b - a)));
    return t * t * (3 - 2 * t);
  }

  var state = {
    w: 0,
    h: 0,
    cx: 0,
    cy: 0,
    maxR: 0,
    time: 0.18,
    tolls: 0,
    tollsShown: 0,
    speed: 1,
    speedShown: 1,
    flash: 0,
    px: 0,
    py: 0,
    tx: 0,
    ty: 0,
    last: 0,
    raf: 0,
    running: false
  };

  var ctx = canvas ? canvas.getContext("2d") : null;

  function resize() {
    if (!canvas || !hero) return;
    var rect = hero.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    state.w = rect.width;
    state.h = rect.height;
    canvas.width = Math.round(rect.width * dpr);
    canvas.height = Math.round(rect.height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    var narrow = rect.width < 760;
    state.cx = state.w * (narrow ? 0.5 : 0.66);
    state.cy = state.h * (narrow ? 0.7 : 0.47);
    state.maxR = Math.hypot(state.w, state.h) * 0.62;
    if (reduce.matches) draw();
  }

  function draw() {
    if (!ctx) return;
    var w = state.w;
    var h = state.h;
    var cx = state.cx + state.px;
    var cy = state.cy + state.py;
    ctx.clearRect(0, 0, w, h);

    var core = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.min(w, h) * 0.72);
    core.addColorStop(0, "rgba(255, 250, 240, " + (0.82 + state.flash * 0.14).toFixed(3) + ")");
    core.addColorStop(0.025, "rgba(255, 246, 232, " + (0.5 + state.flash * 0.12).toFixed(3) + ")");
    core.addColorStop(0.09, "rgba(240, 178, 138, " + (0.2 + state.flash * 0.06).toFixed(3) + ")");
    core.addColorStop(0.32, "rgba(224, 112, 79, 0.06)");
    core.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = core;
    ctx.fillRect(0, 0, w, h);

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(-0.055);

    var AR = 1.42;
    var rings = 38;
    for (var i = 0; i < rings; i++) {
      var p = (i / rings + state.time) % 1;
      var r = state.maxR * Math.pow(p, 2.35) * 1.15;
      if (r < 1.5) continue;
      var a = smoothstep(0, 0.03, p) * (1 - smoothstep(0.72, 1, p));
      var major = i % 4 === 0;

      ctx.beginPath();
      ctx.ellipse(0, 0, r * AR, r, 0, 0, Math.PI * 2);
      ctx.strokeStyle = "rgba(246, 240, 228, " + (a * (major ? 0.32 : 0.13)).toFixed(3) + ")";
      ctx.lineWidth = 0.5 + 1.5 * p;
      ctx.stroke();

      if (major) {
        var spin = state.time * 0.5;
        ctx.beginPath();
        ctx.ellipse(0, 0, r * AR, r, 0, -1.1 + spin, 0.25 + spin);
        ctx.strokeStyle = "rgba(255, 249, 238, " + Math.min(0.6, a * 0.55).toFixed(3) + ")";
        ctx.lineWidth = 0.8 + 2 * p;
        ctx.stroke();

        ctx.beginPath();
        ctx.ellipse(0, 0, r * AR, r, 0, 1.9 + spin, 3.0 + spin);
        ctx.strokeStyle = "rgba(224, 112, 79, " + Math.min(0.45, a * 0.36).toFixed(3) + ")";
        ctx.lineWidth = 0.6 + 1.4 * p;
        ctx.stroke();

        ctx.beginPath();
        ctx.ellipse(0, 0, r * AR, r, 0, 0.7 - spin, 1.5 - spin);
        ctx.strokeStyle = "rgba(159, 195, 204, " + Math.min(0.2, a * 0.18).toFixed(3) + ")";
        ctx.lineWidth = 0.5 + 1.1 * p;
        ctx.stroke();
      }
    }

    var pulse = 1 + Math.sin(state.time * 2.1) * 0.018;
    var throat = state.maxR * 0.075 * pulse;
    ctx.beginPath();
    ctx.ellipse(0, 0, throat * AR, throat, 0, 0, Math.PI * 2);
    ctx.strokeStyle = "rgba(255, 250, 240, 0.55)";
    ctx.lineWidth = 1.2;
    ctx.stroke();

    var gates = Math.round(state.tollsShown);
    for (var g = 0; g < gates; g++) {
      var gp = (g / gates + state.time * 0.55 + 0.12) % 1;
      var gr = state.maxR * Math.pow(gp, 2.5) * 1.15;
      if (gr < 2) continue;
      var ga = smoothstep(0, 0.04, gp) * (1 - smoothstep(0.62, 1, gp));
      ctx.save();
      ctx.beginPath();
      ctx.ellipse(0, 0, gr * 1.34, gr, 0, 0, Math.PI * 2);
      ctx.strokeStyle = "rgba(224, 112, 79, " + (ga * 0.16).toFixed(3) + ")";
      ctx.lineWidth = 5 + 8 * gp;
      ctx.stroke();
      ctx.setLineDash([Math.max(3, 6 + 16 * gp), Math.max(4, 10 + 18 * gp)]);
      ctx.beginPath();
      ctx.ellipse(0, 0, gr * 1.34, gr, 0, 0, Math.PI * 2);
      ctx.strokeStyle = "rgba(224, 112, 79, " + (ga * 0.85).toFixed(3) + ")";
      ctx.lineWidth = 1.8 + 2.6 * gp;
      ctx.stroke();
      ctx.restore();
    }

    for (var s = 0; s < 18; s++) {
      var sp = (s * 0.057 + state.time * 2.4) % 1;
      var sr = state.maxR * Math.pow(sp, 2.2);
      var sa = smoothstep(0.12, 0.4, sp) * (1 - smoothstep(0.78, 1, sp));
      if (sa <= 0) continue;
      var sang = s * 2.399 + state.time * 0.4;
      ctx.beginPath();
      ctx.moveTo(Math.cos(sang) * sr * AR, Math.sin(sang) * sr);
      ctx.lineTo(Math.cos(sang) * sr * AR * 0.86, Math.sin(sang) * sr * 0.86);
      ctx.strokeStyle = "rgba(255, 247, 235, " + (sa * 0.24).toFixed(3) + ")";
      ctx.lineWidth = 0.5 + sp;
      ctx.stroke();
    }

    ctx.restore();

    for (var d = 0; d < 44; d++) {
      var dp = (d * 0.041 + state.time * 1.6) % 1;
      var dr = state.maxR * Math.pow(dp, 2.4);
      var ang = d * 2.399 + state.time * 0.35;
      var da = smoothstep(0.05, 0.3, dp) * (1 - smoothstep(0.8, 1, dp)) * 0.36;
      if (da <= 0) continue;
      ctx.fillStyle = "rgba(246, 240, 228, " + da.toFixed(3) + ")";
      ctx.beginPath();
      ctx.arc(cx + Math.cos(ang) * dr * 1.34, cy + Math.sin(ang) * dr, 0.7 + dp * 0.8, 0, Math.PI * 2);
      ctx.fill();
    }

    var vg = ctx.createRadialGradient(cx, cy, state.maxR * 0.15, cx, cy, state.maxR * 1.15);
    vg.addColorStop(0, "rgba(7, 8, 10, 0)");
    vg.addColorStop(0.62, "rgba(7, 8, 10, 0)");
    vg.addColorStop(1, "rgba(7, 8, 10, 0.7)");
    ctx.fillStyle = vg;
    ctx.fillRect(0, 0, w, h);
  }

  function tick(ts) {
    if (!state.last) state.last = ts;
    var dt = Math.min(0.05, (ts - state.last) / 1000);
    state.last = ts;

    state.time += dt * state.speedShown * 0.11;
    state.speedShown += (state.speed - state.speedShown) * Math.min(1, dt * 3.4);
    state.tollsShown += (state.tolls - state.tollsShown) * Math.min(1, dt * 4.2);
    state.px += (state.tx - state.px) * Math.min(1, dt * 2.6);
    state.py += (state.ty - state.py) * Math.min(1, dt * 2.6);
    state.flash *= Math.pow(0.05, dt);

    draw();
    state.raf = requestAnimationFrame(tick);
  }

  var inView = true;

  function start() {
    if (state.running || reduce.matches || !ctx) return;
    state.running = true;
    state.last = 0;
    state.raf = requestAnimationFrame(tick);
  }

  function stop() {
    state.running = false;
    cancelAnimationFrame(state.raf);
  }

  function sync() {
    if (!reduce.matches && !document.hidden && inView) start();
    else stop();
  }

  function select(id) {
    var plan = plans[id];
    if (!plan) return;
    root.dataset.plan = id;
    state.tolls = plan.tolls;
    state.speed = plan.speed;
    state.flash = 1;
    if (cost) cost.textContent = plan.cost;
    if (note) note.textContent = plan.note;
    if (src) {
      src.href = plan.href;
      src.textContent = plan.label;
    }
    if (chip) {
      chip.textContent = plan.tolls === 0
        ? "No tolls on this route"
        : plan.tolls + (plan.tolls === 1 ? " toll on this route" : " tolls on this route");
    }
    if (reduce.matches) {
      state.tollsShown = plan.tolls;
      state.speedShown = plan.speed;
      draw();
    }
  }

  if (canvas && hero) {
    resize();
    if (reduce.matches) draw();
    else sync();

    if ("ResizeObserver" in window) {
      new ResizeObserver(resize).observe(hero);
    } else {
      window.addEventListener("resize", resize);
    }

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        inView = entries[0].isIntersecting;
        sync();
      }, { threshold: 0 }).observe(hero);
    }

    document.addEventListener("visibilitychange", sync);

    if (reduce.addEventListener) {
      reduce.addEventListener("change", function () {
        if (reduce.matches) {
          stop();
          draw();
        } else {
          sync();
        }
      });
    }

    hero.addEventListener("pointermove", function (event) {
      if (reduce.matches || event.pointerType === "touch") return;
      var rect = hero.getBoundingClientRect();
      state.tx = ((event.clientX - rect.left) / rect.width - 0.5) * 20;
      state.ty = ((event.clientY - rect.top) / rect.height - 0.5) * 14;
    });
    hero.addEventListener("pointerleave", function () {
      state.tx = 0;
      state.ty = 0;
    });
  }

  var radios = document.querySelectorAll('input[name="plan"]');
  for (var i = 0; i < radios.length; i++) {
    radios[i].addEventListener("change", function (event) {
      if (event.target.checked) select(event.target.value);
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
