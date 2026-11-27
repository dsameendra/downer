(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");

  // The red progress line under the navigation, and its border once the page has moved
  var nav = document.getElementById("nav");
  var bar = document.getElementById("progress");
  var ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      var y = window.scrollY || 0;
      var max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      if (nav) nav.classList.toggle("scrolled", y > 8);
      if (bar) bar.style.transform = "scaleX(" + Math.min(1, y / max).toFixed(4) + ")";
      ticking = false;
    });
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll);
  onScroll();

  // Reveal on scroll (everything is simply visible with Reduce Motion, or without the observer)
  var items = document.querySelectorAll(".reveal");
  if (reduce.matches || !("IntersectionObserver" in window)) {
    items.forEach(function (el) { el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    items.forEach(function (el) { io.observe(el); });
  }

  // Screenshot tabs
  var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
  function show(tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
      t.tabIndex = on ? 0 : -1;
      var p = document.getElementById(t.getAttribute("aria-controls"));
      if (on) { p.hidden = false; p.classList.remove("in"); void p.offsetWidth; p.classList.add("in"); }
      else { p.hidden = true; p.classList.remove("in"); }
    });
    if (focus) tab.focus();
  }
  if (tabs.length) {
    show(tabs[0]);
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { show(t); });
      t.addEventListener("keydown", function (e) {
        var n = null;
        if (e.key === "ArrowRight") n = tabs[(i + 1) % tabs.length];
        else if (e.key === "ArrowLeft") n = tabs[(i - 1 + tabs.length) % tabs.length];
        else if (e.key === "Home") n = tabs[0];
        else if (e.key === "End") n = tabs[tabs.length - 1];
        if (n) { e.preventDefault(); show(n, true); }
      });
    });
  }

  // Copy button for the one Terminal command
  var btn = document.getElementById("copy");
  if (btn) {
    var status = document.getElementById("copy-status");
    var target = document.getElementById(btn.getAttribute("data-target"));
    btn.addEventListener("click", function () {
      var text = target.textContent.trim();
      function done(ok) {
        btn.textContent = ok ? "Copied" : "Press Cmd+C";
        status.textContent = ok ? "Command copied to the clipboard." : "Select the command and copy it.";
        setTimeout(function () { btn.textContent = "Copy"; status.textContent = ""; }, 2000);
      }
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
      } else {
        var r = document.createRange();
        r.selectNodeContents(target);
        var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
        var ok = false; try { ok = document.execCommand("copy"); } catch (e) {}
        done(ok);
      }
    });
  }
})();
