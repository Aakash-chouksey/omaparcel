(function () {
  "use strict";

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  var root = document.documentElement;

  /* ============================================================
     header
     ============================================================ */

  var header = document.querySelector("[data-header]");
  var onScroll = function () {
    if (!header) return;
    header.classList.toggle("is-scrolled", window.scrollY > 26);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  var menuBtn = document.querySelector("[data-menu]");
  var menu = document.querySelector("[data-mobile-menu]");
  var setMenu = function (open) {
    if (!menu || !menuBtn) return;
    menu.hidden = !open;
    menu.classList.toggle("is-open", open);
    menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
    menuBtn.querySelector(".sr-only").textContent = open ? "Close menu" : "Open menu";
    document.body.classList.toggle("menu-open", open);
  };
  if (menuBtn && menu) {
    menuBtn.addEventListener("click", function () {
      setMenu(menu.hidden);
    });
    menu.addEventListener("click", function (e) {
      if (e.target.closest("a")) setMenu(false);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !menu.hidden) {
        setMenu(false);
        menuBtn.focus();
      }
    });
    window.addEventListener("resize", function () {
      if (window.innerWidth > 1020 && !menu.hidden) setMenu(false);
    });
  }

  /* ============================================================
     cinematic tunnel
     ============================================================ */

  var hero = document.querySelector(".hero");
  var canvas = document.querySelector("[data-tunnel]");
  var ctx = canvas ? canvas.getContext("2d") : null;

  var tunnel = {
    w: 0, h: 0, dpr: 1,
    cx: 0, cy: 0, maxR: 0, coreR: 0,
    t: 0.24,
    px: 0, py: 0, tx: 0, ty: 0,
    raf: 0, running: false, visible: true,
    last: 0
  };

  var streaks = [];
  var motes = [];
  (function seed() {
    var i;
    for (i = 0; i < 46; i++) {
      streaks.push({
        a: Math.random() * Math.PI * 2,
        off: Math.random(),
        len: 0.35 + Math.random() * 0.9,
        w: 0.5 + Math.random() * 2.4,
        bright: 0.25 + Math.random() * 0.75,
        warm: Math.random() > 0.3
      });
    }
    for (i = 0; i < 64; i++) {
      motes.push({
        a: Math.random() * Math.PI * 2,
        d: Math.pow(Math.random(), 0.7),
        s: 0.4 + Math.random() * 1.5,
        p: Math.random() * 6.28
      });
    }
  })();

  function sizeTunnel() {
    if (!canvas || !hero || !ctx) return;
    var rect = hero.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    tunnel.w = rect.width;
    tunnel.h = rect.height;
    tunnel.dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(rect.width * tunnel.dpr);
    canvas.height = Math.round(rect.height * tunnel.dpr);
    ctx.setTransform(tunnel.dpr, 0, 0, tunnel.dpr, 0, 0);
    var narrow = rect.width < 820;
    tunnel.cx = rect.width * (narrow ? 0.56 : 0.675);
    tunnel.cy = rect.height * (narrow ? 0.385 : 0.455);
    tunnel.maxR = Math.hypot(rect.width, rect.height) * 0.74;
    tunnel.coreR = Math.min(rect.width, rect.height) * (narrow ? 0.032 : 0.028);
    if (reduced.matches) drawTunnel(0);
  }

  function ring(p, maxR, coreR) {
    return coreR + Math.pow(p, 2.15) * (maxR - coreR);
  }

  function drawTunnel(dt) {
    if (!ctx) return;
    var w = tunnel.w, h = tunnel.h;
    var cx = tunnel.cx + tunnel.px;
    var cy = tunnel.cy + tunnel.py;
    var maxR = tunnel.maxR;
    var coreR = tunnel.coreR;

    ctx.clearRect(0, 0, w, h);

    var bg = ctx.createLinearGradient(0, 0, w * 0.2, h);
    bg.addColorStop(0, "#04060a");
    bg.addColorStop(0.52, "#07090c");
    bg.addColorStop(1, "#050506");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, w, h);

    var warm = ctx.createRadialGradient(cx, cy, 0, cx, cy, maxR * 0.82);
    warm.addColorStop(0, "rgba(255, 152, 92, 0.20)");
    warm.addColorStop(0.18, "rgba(255, 118, 60, 0.10)");
    warm.addColorStop(0.52, "rgba(168, 74, 40, 0.035)");
    warm.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = warm;
    ctx.fillRect(0, 0, w, h);

    var floor = ctx.createRadialGradient(cx, cy + maxR * 0.34, 0, cx, cy + maxR * 0.34, maxR * 0.78);
    floor.addColorStop(0, "rgba(255, 120, 60, 0.10)");
    floor.addColorStop(0.5, "rgba(255, 100, 45, 0.035)");
    floor.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.save();
    ctx.translate(0, h * 0.12);
    ctx.fillStyle = floor;
    ctx.fillRect(0, -h * 0.12, w, h * 1.12);
    ctx.restore();

    var t = reduced.matches ? 0.3 : tunnel.t;

    ctx.save();
    ctx.globalCompositeOperation = "lighter";

    /* speed streaks */
    for (var i = 0; i < streaks.length; i++) {
      var s = streaks[i];
      var p = (t * 0.8 + s.off) % 1;
      var d = coreR * 1.5 + p * p * maxR * 1.25;
      var head = (26 + 300 * s.len) * (0.28 + p);
      var a = Math.sin(Math.min(1, p * 1.12) * Math.PI) * 0.46 * s.bright;
      if (a < 0.01) continue;
      var dx = Math.cos(s.a);
      var dy = Math.sin(s.a) * 0.66;
      var x0 = cx + dx * d;
      var y0 = cy + dy * d;
      var x1 = x0 + dx * head;
      var y1 = y0 + dy * head;
      var grad = ctx.createLinearGradient(x0, y0, x1, y1);
      grad.addColorStop(0, "rgba(255, 224, 194, 0)");
      grad.addColorStop(0.3, s.warm ? "rgba(255, 170, 118, " + a.toFixed(3) + ")" : "rgba(255, 240, 220, " + a.toFixed(3) + ")");
      grad.addColorStop(1, "rgba(255, 236, 214, 0)");
      ctx.strokeStyle = grad;
      ctx.lineWidth = s.w * (0.45 + p * 1.7);
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();

      ctx.fillStyle = s.warm ? "rgba(255, 220, 190, " + (a * 1.2).toFixed(3) + ")" : "rgba(255, 248, 238, " + (a * 1.2).toFixed(3) + ")";
      ctx.beginPath();
      ctx.arc(x0, y0, 0.7 + p * 1.7, 0, Math.PI * 2);
      ctx.fill();
    }

    /* anamorphic flare through the core */
    var flareW = maxR * 0.95;
    var fl = ctx.createLinearGradient(cx - flareW, cy, cx + flareW, cy);
    fl.addColorStop(0, "rgba(255, 200, 160, 0)");
    fl.addColorStop(0.4, "rgba(255, 205, 168, 0.07)");
    fl.addColorStop(0.485, "rgba(255, 247, 236, 0.36)");
    fl.addColorStop(0.5, "rgba(255, 252, 246, 0.5)");
    fl.addColorStop(0.515, "rgba(255, 247, 236, 0.36)");
    fl.addColorStop(0.6, "rgba(255, 205, 168, 0.07)");
    fl.addColorStop(1, "rgba(255, 200, 160, 0)");
    ctx.fillStyle = fl;
    ctx.fillRect(cx - flareW, cy - 0.8, flareW * 2, 1.6);

    var flSoft = ctx.createLinearGradient(cx - flareW * 0.6, cy, cx + flareW * 0.6, cy);
    flSoft.addColorStop(0, "rgba(255, 140, 80, 0)");
    flSoft.addColorStop(0.5, "rgba(255, 160, 100, 0.1)");
    flSoft.addColorStop(1, "rgba(255, 140, 80, 0)");
    ctx.fillStyle = flSoft;
    ctx.fillRect(cx - flareW * 0.6, cy - 10, flareW * 1.2, 20);

    ctx.restore();

    /* rings */
    var rings = 36;
    var AR = 1.36;
    var tilt = -0.075;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(tilt);
    for (var j = 0; j < rings; j++) {
      var pr = (j / rings + t * 0.42) % 1;
      var r = ring(pr, maxR, coreR);
      if (r < 1.5) continue;
      var alpha = Math.min(1, Math.max(0, (pr / 0.05))) * Math.pow(1 - pr, 1.35) * 0.62;
      if (alpha < 0.01) continue;
      var major = j % 5 === 0;
      ctx.beginPath();
      ctx.ellipse(0, 0, r * AR, r, 0, 0, Math.PI * 2);
      ctx.strokeStyle = "rgba(247, 236, 218, " + (alpha * (major ? 0.62 : 0.3)).toFixed(3) + ")";
      ctx.lineWidth = 0.55 + 1.6 * pr;
      ctx.stroke();

      if (major) {
        var spin = t * 0.4;
        ctx.beginPath();
        ctx.ellipse(0, 0, r * AR, r, 0, -1.15 + spin, 0.5 + spin);
        ctx.strokeStyle = "rgba(255, 208, 168, " + Math.min(0.55, alpha * 0.9).toFixed(3) + ")";
        ctx.lineWidth = 0.9 + 2 * pr;
        ctx.stroke();

        ctx.beginPath();
        ctx.ellipse(0, 0, r * AR, r, 0, 1.85 + spin, 3.1 + spin);
        ctx.strokeStyle = "rgba(255, 118, 62, " + Math.min(0.4, alpha * 0.74).toFixed(3) + ")";
        ctx.lineWidth = 0.8 + 1.6 * pr;
        ctx.stroke();
      }
    }
    ctx.restore();

    /* dust */
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    for (var k = 0; k < motes.length; k++) {
      var m = motes[k];
      var md = (m.d + t * 0.09) % 1;
      var mr = coreR + Math.pow(md, 1.8) * maxR * 0.95;
      var ma = Math.sin(md * Math.PI) * (0.14 + 0.2 * Math.abs(Math.sin(t * 1.4 + m.p)));
      var mx = cx + Math.cos(m.a) * mr * 1.3;
      var my = cy + Math.sin(m.a) * mr * 0.72;
      ctx.fillStyle = "rgba(255, 226, 198, " + ma.toFixed(3) + ")";
      ctx.beginPath();
      ctx.arc(mx, my, m.s * (0.6 + md * 1.8), 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    /* core bloom */
    var pulse = 1 + Math.sin(t * 1.5) * 0.018;
    var bloom = ctx.createRadialGradient(cx, cy, 0, cx, cy, coreR * 7 * pulse);
    bloom.addColorStop(0, "rgba(255, 252, 244, 0.95)");
    bloom.addColorStop(0.08, "rgba(255, 238, 216, 0.9)");
    bloom.addColorStop(0.24, "rgba(255, 184, 126, 0.38)");
    bloom.addColorStop(0.55, "rgba(255, 120, 60, 0.1)");
    bloom.addColorStop(1, "rgba(255, 100, 40, 0)");
    ctx.fillStyle = bloom;
    ctx.beginPath();
    ctx.arc(cx, cy, coreR * 7 * pulse, 0, Math.PI * 2);
    ctx.fill();

    var core = ctx.createRadialGradient(cx, cy, 0, cx, cy, coreR * 1.9 * pulse);
    core.addColorStop(0, "rgba(255, 255, 253, 1)");
    core.addColorStop(0.35, "rgba(255, 248, 233, 0.98)");
    core.addColorStop(0.72, "rgba(255, 220, 183, 0.7)");
    core.addColorStop(1, "rgba(255, 180, 130, 0)");
    ctx.fillStyle = core;
    ctx.beginPath();
    ctx.arc(cx, cy, coreR * 1.9 * pulse, 0, Math.PI * 2);
    ctx.fill();

    /* lensing arc */
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(tilt);
    ctx.strokeStyle = "rgba(255, 244, 228, 0.5)";
    ctx.lineWidth = 1.1;
    ctx.beginPath();
    ctx.ellipse(0, 0, coreR * 2.1, coreR * 1.55, 0, 0.2, 2.1);
    ctx.stroke();
    ctx.strokeStyle = "rgba(255, 138, 78, 0.4)";
    ctx.beginPath();
    ctx.ellipse(0, 0, coreR * 2.35, coreR * 1.74, 0, 3.4, 4.9);
    ctx.stroke();
    ctx.restore();

    if (!reduced.matches) {
      tunnel.t += dt * 0.25;
      tunnel.px += (tunnel.tx - tunnel.px) * 0.045;
      tunnel.py += (tunnel.ty - tunnel.py) * 0.045;
    }
  }

  function loop(now) {
    if (!tunnel.running) return;
    var dt = Math.min(0.05, (now - (tunnel.last || now)) / 1000);
    tunnel.last = now;
    drawTunnel(dt);
    tunnel.raf = requestAnimationFrame(loop);
  }

  function startTunnel() {
    if (!ctx || tunnel.running) return;
    if (reduced.matches) {
      drawTunnel(0);
      return;
    }
    tunnel.running = true;
    tunnel.last = 0;
    tunnel.raf = requestAnimationFrame(loop);
  }

  function stopTunnel() {
    tunnel.running = false;
    cancelAnimationFrame(tunnel.raf);
  }

  if (canvas && ctx) {
    sizeTunnel();
    drawTunnel(0);
    var resizeTimer;
    window.addEventListener("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        sizeTunnel();
        drawTunnel(0);
      }, 120);
    });
    window.addEventListener("pointermove", function (e) {
      if (reduced.matches) return;
      var nx = (e.clientX / window.innerWidth) * 2 - 1;
      var ny = (e.clientY / window.innerHeight) * 2 - 1;
      tunnel.tx = nx * 14;
      tunnel.ty = ny * 10;
    }, { passive: true });

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        tunnel.visible = entries[0].isIntersecting;
        if (tunnel.visible) startTunnel();
        else stopTunnel();
      }, { threshold: 0.02 }).observe(hero);
    } else {
      startTunnel();
    }
    document.addEventListener("visibilitychange", function () {
      if (document.hidden) stopTunnel();
      else if (tunnel.visible) startTunnel();
    });
    var heroFade = document.querySelector(".hero");
    if (heroFade) {
      heroFade.style.setProperty("--hero-in", "1");
    }
    startTunnel();
  }

  /* ============================================================
     copy buttons
     ============================================================ */

  function copyText(text, done) {
    var settle = function (ok) {
      if (!ok) {
        var area = document.createElement("textarea");
        area.value = text;
        area.setAttribute("readonly", "");
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.appendChild(area);
        area.select();
        var okFallback = false;
        try { okFallback = document.execCommand("copy"); } catch (err) { okFallback = false; }
        area.remove();
        done(okFallback);
        return;
      }
      done(true);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { settle(true); }, function () { settle(false); });
    } else {
      settle(false);
    }
  }

  document.addEventListener("click", function (e) {
    var btn = e.target.closest("[data-copy]");
    if (!btn) return;
    var text = btn.getAttribute("data-copy") || "";
    if (!text) {
      var link = btn.closest(".linkbox");
      var cmd = btn.closest(".cmd");
      if (link) text = (link.querySelector("[data-link]") || {}).textContent || "";
      else if (cmd) text = (cmd.querySelector("code") || {}).textContent || "";
      else text = btn.getAttribute("data-copy-text") || "";
    }
    text = (text || "").trim();
    if (!text) return;
    var idle = btn.textContent;
    copyText(text, function (ok) {
      btn.textContent = ok ? (btn.getAttribute("data-copied-label") || "Copied") : "Copy failed";
      btn.classList.toggle("is-done", ok);
      setTimeout(function () {
        btn.textContent = idle;
        btn.classList.remove("is-done");
      }, 1700);
    });
  });

  /* ============================================================
     console demo
     ============================================================ */

  var modes = {
    folder: {
      command: "tsctl share ~/Pictures/Riverside_2026 --hours 24",
      link: "https://tall-river-4821.trycloudflare.com/s/9f3a2c71e04b",
      meta: "12 files · 3.2 GB · expires in 24 h",
      label: "folder · 12 files",
      progressLabel: "Serving from disk",
      progressValue: "1.4 GB / 3.2 GB",
      progress: 44,
      more: "+ 8 more files",
      moreNote: "No account",
      pin: false,
      files: [
        ["MOV", "A001_0342.MOV", "1.4 GB", "streaming"],
        ["MOV", "A001_0343.MOV", "1.1 GB", "queued"],
        ["MOV", "A001_0344.MOV", "620 MB", "queued"],
        ["PDF", "shot_list.pdf", "1.8 MB", "ready"]
      ]
    },
    file: {
      command: "tsctl share ./keynote-final.mp4 --hours 2 --pin 4821",
      link: "https://quiet-forest-0932.trycloudflare.com/s/2b7d1e99a3c4",
      meta: "1 file · 4.8 GB · expires in 2 h · PIN on",
      label: "one file · 4.8 GB",
      progressLabel: "Serving from disk",
      progressValue: "2.9 GB / 4.8 GB",
      progress: 61,
      more: "1 file",
      moreNote: "PIN required",
      pin: true,
      files: [
        ["MP4", "keynote-final.mp4", "4.8 GB", "streaming"]
      ]
    },
    code: {
      command: 'tsctl share . --hours 72 --note "review"',
      link: "https://silent-harbor-7740.trycloudflare.com/s/c41a8e03f7d2",
      meta: "86 files · 48 MB · expires in 72 h",
      label: "code · 86 files",
      progressLabel: "Serving from disk",
      progressValue: "47 MB / 48 MB",
      progress: 97,
      more: "+ 83 more files",
      moreNote: "No account",
      pin: false,
      files: [
        ["GZ", "build.tar.gz", "41 MB", "streaming"],
        ["ZIP", "screenshots.zip", "6.2 MB", "queued"],
        ["MD", "README.md", "12 KB", "ready"]
      ]
    }
  };

  var consoleEl = document.getElementById("console-demo");
  var consoleTabs = Array.prototype.slice.call(document.querySelectorAll("[data-mode]"));
  var commandEl = document.querySelector("[data-command]");
  var linkEl = document.querySelector("[data-link]");
  var metaEl = document.querySelector("[data-meta]");
  var filesEl = document.querySelector("[data-files]");
  var progressEl = document.querySelector("[data-progress]");
  var progressValueEl = document.querySelector("[data-progress-value]");
  var progressLabelEl = document.querySelector("[data-progress-label]");
  var modeLabelEl = document.querySelector("[data-mode-label]");
  var pinEl = document.querySelector("[data-pin]");
  var pauseBtn = document.querySelector("[data-pause]");

  var demo = {
    mode: "folder",
    paused: false,
    typing: 0,
    animate: 0,
    started: false
  };

  function escapeText(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function renderFiles(mode) {
    if (!filesEl) return;
    var html = "";
    mode.files.forEach(function (f) {
      html += "<li><span class=\"ftype\">" + escapeText(f[0]) + "</span><span class=\"fname\">" + escapeText(f[1]) +
        "</span><span class=\"fsize\">" + escapeText(f[2]) + "</span><span class=\"fstate\">" + escapeText(f[3]) + "</span></li>";
    });
    html += "<li class=\"file-more\"><span>" + escapeText(mode.more) + "</span><span>" + escapeText(mode.moreNote) + "</span></li>";
    filesEl.innerHTML = html;
  }

  function stopDemoAnim() {
    clearTimeout(demo.typing);
    clearInterval(demo.animate);
  }

  function typeCommand(text) {
    if (!commandEl) return;
    commandEl.textContent = "";
    if (reduced.matches) {
      commandEl.textContent = text;
      return;
    }
    var i = 0;
    (function step() {
      if (demo.paused) return;
      commandEl.textContent = text.slice(0, i);
      i++;
      if (i <= text.length) demo.typing = setTimeout(step, 22 + (i < 8 ? 30 : 0));
    })();
  }

  function animateProgress(mode, keep) {
    if (!progressEl) return;
    var start = keep ? parseFloat(progressEl.style.width) || 0 : 0;
    var target = reduced.matches ? mode.progress : start;
    progressEl.style.width = target + "%";
    if (reduced.matches) return;
    var tick = function () {
      if (demo.paused) return;
      var now = parseFloat(progressEl.style.width) || 0;
      var next = Math.min(mode.progress, now + Math.max(0.6, mode.progress * 0.035));
      progressEl.style.width = next + "%";
      if (next >= mode.progress) clearInterval(demo.animate);
    };
    demo.animate = setInterval(tick, 90);
  }

  function setMode(name, userInitiated) {
    var mode = modes[name];
    if (!mode || !consoleEl) return;
    demo.mode = name;
    demo.paused = false;
    if (pauseBtn) {
      pauseBtn.textContent = "Pause";
      pauseBtn.setAttribute("aria-pressed", "false");
    }
    stopDemoAnim();

    consoleTabs.forEach(function (tab) {
      var on = tab.getAttribute("data-mode") === name;
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", on ? "true" : "false");
    });

    if (modeLabelEl) modeLabelEl.textContent = mode.label;
    if (linkEl) linkEl.textContent = mode.link;
    if (metaEl) metaEl.textContent = mode.meta;
    if (progressValueEl) progressValueEl.textContent = mode.progressValue;
    if (progressLabelEl) progressLabelEl.textContent = mode.progressLabel;
    if (pinEl) pinEl.hidden = !mode.pin;
    renderFiles(mode);
    typeCommand(mode.command);
    animateProgress(mode);

    if (progressEl) {
      progressEl.parentElement.setAttribute("aria-label", mode.progress + " percent of this share has been served");
    }
    if (userInitiated) {
      demo.started = true;
    }
  }

  if (consoleEl) {
    consoleTabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        setMode(tab.getAttribute("data-mode"), true);
      });
      tab.addEventListener("keydown", function (e) {
        var idx = consoleTabs.indexOf(tab);
        var next = null;
        if (e.key === "ArrowRight") next = consoleTabs[(idx + 1) % consoleTabs.length];
        if (e.key === "ArrowLeft") next = consoleTabs[(idx - 1 + consoleTabs.length) % consoleTabs.length];
        if (next) {
          e.preventDefault();
          next.focus();
          setMode(next.getAttribute("data-mode"), true);
        }
      });
    });

    if (pauseBtn) {
      pauseBtn.addEventListener("click", function () {
        demo.paused = !demo.paused;
        pauseBtn.textContent = demo.paused ? "Resume" : "Pause";
        pauseBtn.setAttribute("aria-pressed", demo.paused ? "true" : "false");
        if (!demo.paused) {
          if (commandEl) commandEl.textContent = modes[demo.mode].command;
          demo.started = true;
          animateProgress(modes[demo.mode], true);
        } else {
          stopDemoAnim();
        }
      });
    }

    renderFiles(modes.folder);
    if (!reduced.matches) {
      var seen = false;
      if ("IntersectionObserver" in window) {
        new IntersectionObserver(function (entries) {
          if (entries[0].isIntersecting && !seen) {
            seen = true;
            setMode(demo.mode, false);
          }
        }, { threshold: 0.2 }).observe(consoleEl);
      } else {
        setTimeout(function () { setMode(demo.mode, false); }, 800);
      }
    }
  }

  /* ============================================================
     use cases
     ============================================================ */

  var uses = {
    client: {
      kicker: "Client handoff · The brief",
      title: "Send the raw footage without a cloud round trip.",
      quote: "“The client needs the 14 GB ProRes folder today. I’m not waiting two hours for an upload, and I’m not paying for another terabyte.”",
      sources: [
        ["DIR", "Riverside_2026", "14.2 GB"],
        ["PDF", "shot_list.pdf", "1.8 MB"],
        ["TXT", "delivery_note.txt", "2 KB"]
      ],
      path: "Riverside_2026",
      exp: "Expires in 23 h",
      title2: "Riverside_2026",
      meta: "12 files · 14.2 GB",
      rows: [
        ["MOV", "A001_C002_0714RP.mov", "4.1 GB"],
        ["MOV", "A002_C008_0812RP.mov", "3.6 GB"],
        ["MOV", "A003_C011_0930RP.mov", "5.2 GB"],
        ["PDF", "shot_list.pdf", "1.8 MB"],
        ["TXT", "delivery_note.txt", "2 KB"]
      ],
      foot: "Served from the sender’s disk · No account needed",
      download: "Download all"
    },
    family: {
      kicker: "Family · The brief",
      title: "Send the trip to the group chat.",
      quote: "“3,100 photos from the coast. I want one link, a QR code, and nothing for my parents to install.”",
      sources: [
        ["DIR", "Coast_2026", "9.4 GB"],
        ["TXT", "print_list.txt", "4 KB"],
        ["PDF", "coast_map.pdf", "2.4 MB"]
      ],
      path: "Coast_2026",
      exp: "Expires in 7 days",
      title2: "Coast_2026",
      meta: "3,104 items · 9.4 GB",
      rows: [
        ["HEIC", "IMG_4402.HEIC", "4.2 MB"],
        ["HEIC", "IMG_4418.HEIC", "5.1 MB"],
        ["HEIC", "IMG_4521.HEIC", "3.8 MB"],
        ["PDF", "coast_map.pdf", "2.4 MB"],
        ["TXT", "print_list.txt", "4 KB"]
      ],
      foot: "PIN 4821 · Photos and one PDF · No app",
      download: "Open album"
    },
    code: {
      kicker: "Code review · The brief",
      title: "Hand over a build without a repo invite.",
      quote: "“A tarball, three screenshots, and a note. The link dies in two hours and needs a code.”",
      sources: [
        ["GZ", "build.tar.gz", "41 MB"],
        ["ZIP", "screenshots.zip", "6.2 MB"],
        ["MD", "README.md", "12 KB"]
      ],
      path: "build-check",
      exp: "Expires in 2 h",
      title2: "build-check",
      meta: "3 files · 47 MB",
      rows: [
        ["GZ", "build.tar.gz", "41 MB"],
        ["ZIP", "screenshots.zip", "6.2 MB"],
        ["MD", "README.md", "12 KB"]
      ],
      foot: "PIN 4821 · No account · Link dies in two hours",
      download: "Download 47 MB"
    },
    media: {
      kicker: "Big media · The brief",
      title: "Send a 40 GB master, once.",
      quote: "“The festival needs the master by Friday. One link, resumable, and it closes when I say so.”",
      sources: [
        ["MOV", "feature_master_v7.mov", "40 GB"],
        ["PDF", "delivery_spec.pdf", "820 KB"]
      ],
      path: "Festival_master",
      exp: "Expires in 48 h",
      title2: "Festival_master",
      meta: "2 files · 40 GB",
      rows: [
        ["MOV", "feature_master_v7.mov", "40 GB"],
        ["PDF", "delivery_spec.pdf", "820 KB"]
      ],
      foot: "Resumable range requests · No size cap · No account",
      download: "Download 40 GB"
    }
  };

  var useTabs = Array.prototype.slice.call(document.querySelectorAll("[data-use]"));
  var briefKicker = document.querySelector("[data-brief-kicker]");
  var briefTitle = document.querySelector("[data-brief-title]");
  var briefQuote = document.querySelector("[data-brief-quote]");
  var sourceList = document.querySelector("[data-source-list]");
  var previewPath = document.querySelector("[data-preview-path]");
  var previewExp = document.querySelector("[data-preview-exp]");
  var previewTitle = document.querySelector("[data-preview-title]");
  var previewMeta = document.querySelector("[data-preview-meta]");
  var previewRows = document.querySelector("[data-preview-rows]");
  var previewFoot = document.querySelector("[data-preview-foot]");
  var previewDownload = document.querySelector("[data-preview-download]");

  function renderUse(name) {
    var u = uses[name];
    if (!u) return;
    useTabs.forEach(function (tab) {
      var on = tab.getAttribute("data-use") === name;
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", on ? "true" : "false");
    });
    if (briefKicker) briefKicker.textContent = u.kicker;
    if (briefTitle) briefTitle.textContent = u.title;
    if (briefQuote) briefQuote.textContent = u.quote;
    if (sourceList) {
      sourceList.innerHTML = u.sources.map(function (f) {
        return "<li><span class=\"ftype\">" + escapeText(f[0]) + "</span><span>" + escapeText(f[1]) + "</span><span>" + escapeText(f[2]) + "</span></li>";
      }).join("");
    }
    if (previewPath) previewPath.textContent = u.path;
    if (previewExp) previewExp.textContent = u.exp;
    if (previewTitle) previewTitle.textContent = u.title2;
    if (previewMeta) previewMeta.textContent = u.meta;
    if (previewFoot) previewFoot.textContent = u.foot;
    if (previewDownload) previewDownload.textContent = u.download;
    if (previewRows) {
      previewRows.innerHTML = u.rows.map(function (f) {
        return "<li><span class=\"ftype\">" + escapeText(f[0]) + "</span><span class=\"pname\">" + escapeText(f[1]) +
          "</span><span class=\"psize\">" + escapeText(f[2]) + "</span><span class=\"pdown\" aria-hidden=\"true\">↓</span></li>";
      }).join("");
    }
  }

  useTabs.forEach(function (tab) {
    tab.addEventListener("click", function () {
      renderUse(tab.getAttribute("data-use"));
    });
    tab.addEventListener("keydown", function (e) {
      var idx = useTabs.indexOf(tab);
      var next = null;
      if (e.key === "ArrowRight") next = useTabs[(idx + 1) % useTabs.length];
      if (e.key === "ArrowLeft") next = useTabs[(idx - 1 + useTabs.length) % useTabs.length];
      if (next) {
        e.preventDefault();
        next.focus();
        renderUse(next.getAttribute("data-use"));
      }
    });
  });

  /* ============================================================
     reveal + meters
     ============================================================ */

  if (!reduced.matches) {
    var revealEls = Array.prototype.slice.call(document.querySelectorAll("[data-reveal]"));
    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          }
        });
      }, { threshold: 0.08, rootMargin: "0px 0px -40px 0px" });
      revealEls.forEach(function (el) { io.observe(el); });

      var meterRows = Array.prototype.slice.call(document.querySelectorAll(".meter-row"));
      var mIo = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            mIo.unobserve(entry.target);
          }
        });
      }, { threshold: 0.35 });
      meterRows.forEach(function (el) { mIo.observe(el); });
    } else {
      revealEls.forEach(function (el) { el.classList.add("is-in"); });
    }
  }

  /* receipt links open the disclosure before jumping */
  var receipt = document.querySelector(".receipt");
  if (receipt) {
    Array.prototype.forEach.call(document.querySelectorAll('a[href="#receipt"]'), function (a) {
      a.addEventListener("click", function () { receipt.open = true; });
    });
    if (window.location.hash === "#receipt") receipt.open = true;
  }

  var year = document.querySelector("[data-year]");
  if (year) year.textContent = String(new Date().getFullYear());
})();
