---
name: artifact-visual-system
description: A ready-made visual system for Claude Artifacts — design tokens, component recipes, mermaid workarounds and a zoomable diagram viewer. Use BEFORE writing or re-skinning artifact HTML (briefings, design docs, dashboards, reviews, reports), when asked to "apply the house styles" or to restyle an existing artifact, or whenever an artifact needs diagrams that stay readable. Complements the built-in artifact-design skill: that one calibrates how much design a request warrants, this one fixes the palette, typography and the runtime traps.
---

# Artifact visual system

One visual system for every artifact, so a set of documents reads as one family instead of a
new palette per page. Violet accent, light ground, sans-serif, soft rounded cards.

Use it as-is, or swap the accent hue once at the top and keep everything else — the point is that
the choice is made once, not per document.

## 1. Tokens — copy verbatim

```css
:root{
  color-scheme:light;
  --primary:#8b5cf6; --primary-700:#5b21b6; --primary-50:#f5f3ff; --primary-200:#ddd6fe;
  --fg:#252525; --soft-fg:#3f3f43; --muted-fg:#8e8e8e;
  --bg:#ffffff; --surface:#f7f7f7; --border:#e5e7eb;
  --green-700:#15803d; --green-200:#bbf7d0; --green-50:#f0fdf4;
  --amber-700:#b45309; --amber-200:#fde68a; --amber-50:#fffbeb;
  --red-700:#b91c1c;  --red-200:#fecaca;  --red-50:#fef2f2;
  --sans:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
  --mono:'SF Mono',source-code-pro,Menlo,Monaco,Consolas,monospace;
}
*{box-sizing:border-box;}
body{font-family:var(--sans); color:var(--fg); font-size:15px; line-height:1.55; margin:0;
  -webkit-font-smoothing:antialiased;
  background:radial-gradient(1200px 600px at 85% -10%, rgba(139,92,246,.07), transparent 60%),
             radial-gradient(900px 500px at 0% 5%, rgba(22,163,74,.05), transparent 55%),#fbfbfc;}
```

The two radial washes are the signature: a violet bloom top-right, a faint green one bottom-left,
over an off-white ground. Never a flat `#fff` page.

## 2. Hard rules

- **One theme, light.** No `@media (prefers-color-scheme:dark)`, no `:root[data-theme="dark"]`.
  This is a deliberate commitment to a single visual world, so the page looks identical whatever
  theme the reader runs. It overrides the usual "design both themes" default.
- **Sans-serif body.** Mono only for code, `file:line` refs, eyebrows, data cells and technical
  captions. No editorial serif (Iowan / Palatino / Georgia).
- **No heavy black rules.** `2px solid var(--fg)` → always `1px solid var(--border)`.
- **Semantic color is separate from the accent.** Violet = thesis / verdict / the thing itself.
  Green = confirmed, present, works. Amber = caveat, nuance, gate. Red = correction, missing, broken.
  Don't spend violet on "good" or green on "primary action".
- **Emoji sparingly.** One occasionally, never one per section.
- **Stable favicon** across redeploys of the same artifact — readers find the tab by its icon.
  Change it only on a hard pivot in what the page is about.

## 3. Component recipes

| piece | recipe |
|---|---|
| page width | `max-width:940px` for reading docs; up to 1560px only for a dashboard or tool |
| card | `background:var(--bg)` · `border:1px solid var(--border)` · `border-radius:12–14px` · `box-shadow:0 12px 34px -26px rgba(20,20,30,.25)` |
| semantic card | wash background + its `-200` border, per the color meanings above |
| eyebrow | 10px · `font-weight:700` · `letter-spacing:.06em` · uppercase · `--muted-fg` (or the color's `-700`) |
| chip / pill | 10.5px bold · `border-radius:999px` · wash + `-200` border + `-700` text |
| h1 | 27px · `font-weight:800` · `letter-spacing:-.02em` · `text-wrap:balance` |
| h2 | 19px · 800 · with a mono violet section number beside it |
| table | wrapper with `overflow-x:auto` + rounded border; `th` mono 9.5px uppercase on `#fcfcfe`; `font-variant-numeric:tabular-nums` on numeric columns |
| quote / draft block | `border-left:3px solid var(--primary)`, `border-radius:0 12px 12px 0`, violet eyebrow header |
| ordered list | `li::marker` in mono violet |
| focus | `outline:2px solid var(--primary); outline-offset:3px` on links, buttons, summaries |

Structural devices (numbers, eyebrows, dividers) must encode something true — a real sequence, a
real category. Don't number sections that aren't a sequence.

## 4. Mermaid inside artifacts — four traps

Artifacts render mermaid natively (```mermaid fences in markdown, `<pre class="mermaid">` in HTML).
Each of these costs an iteration if you skip it.

1. **Escape label line breaks as `&lt;br/&gt;`.** Inside `<pre class="mermaid">` a literal `<br/>`
   is parsed by the browser, so mermaid never sees it and the line break is lost.
2. **The runtime ignores `themeVariables` and paints every unclassed node dark.** Always ship
   `classDef default fill:#ffffff,stroke:#e5e7eb,color:#252525;` **and** an explicit class per node:
   ```
   classDef gate  fill:#fffbeb,stroke:#fcd34d,color:#b45309,font-weight:600;
   classDef drop  fill:#fef2f2,stroke:#fecaca,color:#b91c1c;
   classDef ok    fill:#f0fdf4,stroke:#bbf7d0,color:#15803d;
   classDef hi    fill:#f5f3ff,stroke:#8b5cf6,color:#5b21b6,font-weight:600;
   classDef store fill:#f7f7f7,stroke:#e5e7eb,color:#3f3f43;
   ```
3. **What `classDef` can't reach goes through CSS with `!important`** — subgraph titles and edge
   labels otherwise render nearly invisible:
   ```css
   .mermaid .cluster rect{fill:#fcfcfe !important; stroke:#e5e7eb !important;}
   .mermaid .cluster text,.mermaid .cluster-label .nodeLabel{fill:#252525 !important; color:#252525 !important; font-weight:700 !important;}
   .mermaid .edgeLabel,.mermaid .edgeLabel p,.mermaid .edgeLabel span{color:#252525 !important; background:#ffffff !important; fill:#252525 !important;}
   .mermaid .edgeLabel rect,.mermaid .labelBkg{fill:#ffffff !important; opacity:1 !important;}
   .mermaid .flowchart-link{stroke:#9ca3af !important;}
   .mermaid marker path,.mermaid .marker{fill:#9ca3af !important; stroke:#9ca3af !important;}
   ```
4. **Never render mermaid inside a hidden container** (a `display:none` tab): text metrics come out
   wrong and the diagram stays clipped forever. If the page needs tabs, put diagrams in the tab
   that is visible on load, or hand-author the figure in SVG.

Plus the JS trap: **the runtime replaces the `<pre class="mermaid">` element**. Any script that
touches the rendered SVG must re-query it from a container that survives (the wrapper, the
`figure`) — caching the `<pre>` reference means the SVG "doesn't exist" and every control dies
silently.

Diagram type: implicit time axis with actors → **sequence**. Static interconnected components →
**flowchart**.

## 5. Zoomable diagram viewer

Any diagram that doesn't fit one screen gets this wrapper, so the reader can fit, zoom, pan and
go full-screen instead of scrolling a clipped image.

```html
<figure>
  <div class="dgbar">
    <span class="dgttl">Diagram 1 · short title</span>
    <span class="dghint">Esc / scroll = zoom</span>
    <div class="dgbtns">
      <button type="button" data-act="out" aria-label="Zoom out">−</button>
      <button type="button" data-act="in"  aria-label="Zoom in">+</button>
      <button type="button" data-act="fit" aria-label="Fit to screen">⤢</button>
      <button type="button" data-act="max" aria-label="Maximize">⛶</button>
    </div>
  </div>
  <div class="dgview"><div class="dgpan"><pre class="mermaid">…</pre></div></div>
  <figcaption>What the diagram shows.</figcaption>
</figure>
```

```css
figure{margin:0; background:var(--bg); border:1px solid var(--border); border-radius:14px;
       overflow:hidden; box-shadow:0 12px 34px -26px rgba(20,20,30,.25);}
.dgbar{display:flex; align-items:center; gap:10px; padding:9px 12px;
       border-bottom:1px solid var(--border); background:#fcfcfe;}
.dgttl{font-family:var(--mono); font-size:10px; font-weight:700; letter-spacing:.06em;
       text-transform:uppercase; color:var(--muted-fg);}
.dghint{font-family:var(--mono); font-size:10px; color:var(--primary); display:none;}
figure.max .dghint{display:inline;}
.dgbtns{margin-left:auto; display:flex; gap:4px; flex:none;}
.dgbtns button{width:28px; height:28px; display:grid; place-items:center; padding:0; line-height:1;
               font-family:var(--sans); font-size:14px; font-weight:700; cursor:pointer;
               border:1px solid var(--border); background:#fff; color:#4b4b4f; border-radius:8px;}
.dgbtns button:hover{border-color:var(--primary); color:var(--primary);}
.dgview{position:relative; overflow:hidden; height:clamp(320px,62vh,640px);
        background:var(--bg); cursor:grab; touch-action:none;}
.dgview.grabbing{cursor:grabbing;}
.dgview.raw{overflow:auto; cursor:auto; touch-action:auto;}
.dgpan{position:absolute; top:0; left:0; transform-origin:0 0;}
.dgview.raw .dgpan{position:static; transform:none !important;}
.dgpan .mermaid{display:block;}
.dgpan svg{background:transparent;}
figure.max{position:fixed; inset:0; z-index:1000; border:0; border-radius:0; max-width:none;
           display:flex; flex-direction:column;}
figure.max .dgbar{flex:none;}
figure.max .dgview{flex:1 1 auto; height:auto; min-height:0;}
figure.max figcaption{display:none;}
figcaption{font-size:12.5px; color:var(--soft-fg); padding:10px 14px 12px; line-height:1.6;}
```

```html
<script>
(function(){
  var MIN = 0.15, MAX = 6, figs = [];

  function setup(fig){
    var view = fig.querySelector('.dgview'), pan = fig.querySelector('.dgpan');
    if(!view || !pan) return;
    var st = {s:1, x:0, y:0, w:0, h:0, ready:false, touched:false};

    function apply(){ pan.style.transform = 'translate('+st.x+'px,'+st.y+'px) scale('+st.s+')'; }

    function fit(){
      if(!st.ready) return;
      var vw = view.clientWidth, vh = view.clientHeight;
      if(!vw || !vh || !st.w || !st.h) return;
      st.s = Math.min(vw/st.w, vh/st.h, 2);
      st.x = (vw - st.w*st.s)/2; st.y = (vh - st.h*st.s)/2;
      st.touched = false; apply();
    }

    function zoomAt(factor, cx, cy){
      if(!st.ready) return;
      var ns = Math.min(MAX, Math.max(MIN, st.s*factor));
      if(ns === st.s) return;
      var r = view.getBoundingClientRect();
      var px = (cx === undefined ? r.width/2  : cx - r.left);
      var py = (cy === undefined ? r.height/2 : cy - r.top);
      st.x = px - (px - st.x)*(ns/st.s);
      st.y = py - (py - st.y)*(ns/st.s);
      st.s = ns; st.touched = true; apply();
    }

    // the mermaid runtime REPLACES the <pre>, so always re-query from a container that survives
    function measure(){
      var svg = pan.querySelector('svg') || fig.querySelector('svg');
      if(!svg) return false;
      var vb = (svg.getAttribute('viewBox') || '').trim().split(/[\s,]+/);
      var w = parseFloat(vb[2]), h = parseFloat(vb[3]);
      if(!w || !h){ try{ var bx = svg.getBBox(); w = bx.width; h = bx.height; }catch(e){} }
      if(!w || !h){ var bb = svg.getBoundingClientRect(); w = bb.width; h = bb.height; }
      if(!w || !h) return false;
      if(!pan.contains(svg)) pan.appendChild(svg);
      svg.style.maxWidth = 'none'; svg.style.width = w+'px'; svg.style.height = h+'px';
      svg.style.display = 'block';
      st.w = w; st.h = h; st.ready = true;
      view.classList.remove('raw'); fit(); return true;
    }

    if(!measure()){
      var obs = new MutationObserver(function(){ if(measure()) obs.disconnect(); });
      obs.observe(fig, {childList:true, subtree:true, attributes:true});
      var tries = 0, poll = setInterval(function(){
        if(measure()){ clearInterval(poll); obs.disconnect(); return; }
        if(++tries > 80){ clearInterval(poll); obs.disconnect(); view.classList.add('raw'); }
      }, 250);
    }

    fig.querySelectorAll('.dgbtns button').forEach(function(b){
      b.addEventListener('click', function(){
        var a = b.getAttribute('data-act');
        if(a === 'in')  zoomAt(1.25);
        if(a === 'out') zoomAt(0.8);
        if(a === 'fit') fit();
        if(a === 'max') toggleMax(fig);
      });
    });

    var drag = null;
    view.addEventListener('pointerdown', function(e){
      if(!st.ready) return;
      drag = {id:e.pointerId, px:e.clientX, py:e.clientY};
      view.classList.add('grabbing'); view.setPointerCapture(e.pointerId);
    });
    view.addEventListener('pointermove', function(e){
      if(!drag || e.pointerId !== drag.id) return;
      st.x += e.clientX - drag.px; st.y += e.clientY - drag.py;
      drag.px = e.clientX; drag.py = e.clientY; st.touched = true; apply();
    });
    function endDrag(e){
      if(!drag || (e && e.pointerId !== drag.id)) return;
      drag = null; view.classList.remove('grabbing');
    }
    view.addEventListener('pointerup', endDrag);
    view.addEventListener('pointercancel', endDrag);

    // plain wheel keeps scrolling the page; zoom needs full-screen or a modifier
    view.addEventListener('wheel', function(e){
      if(!fig.classList.contains('max') && !e.ctrlKey && !e.metaKey) return;
      e.preventDefault();
      zoomAt(e.deltaY < 0 ? 1.12 : 0.89, e.clientX, e.clientY);
    }, {passive:false});

    view.addEventListener('dblclick', function(){ fit(); });
    figs.push({fig:fig, fit:fit, st:st});
  }

  function toggleMax(fig){
    var on = !fig.classList.contains('max');
    document.querySelectorAll('figure.max').forEach(function(f){ f.classList.remove('max'); });
    if(on) fig.classList.add('max');
    document.documentElement.style.overflow = on ? 'hidden' : '';
    document.querySelectorAll('[data-act="max"]').forEach(function(b){
      var inMax = b.closest('figure').classList.contains('max');
      b.textContent = inMax ? '✕' : '⛶';
      b.setAttribute('aria-label', inMax ? 'Restore' : 'Maximize');
    });
    requestAnimationFrame(function(){
      figs.forEach(function(f){ if(f.fig === fig) f.fit(); });
    });
  }

  document.addEventListener('keydown', function(e){
    if(e.key !== 'Escape') return;
    var open = document.querySelector('figure.max');
    if(open) toggleMax(open);
  });

  var rt = null;
  window.addEventListener('resize', function(){
    clearTimeout(rt);
    rt = setTimeout(function(){
      figs.forEach(function(f){ if(!f.st.touched) f.fit(); });
    }, 150);
  });

  document.querySelectorAll('figure').forEach(setup);
})();
</script>
```

Behavior it gives you: auto-fit on load (scaled from the `viewBox`, capped at 2×), drag to pan,
double-click to re-fit, wheel zoom in full-screen or with `Ctrl`/`⌘`, `Esc` to exit, flexbox
full-screen so the fit math sees the real height, and a graceful `overflow:auto` fallback if the
SVG never appears (~20s).

## 6. Before publishing

- Concise, stable `<title>`; one-sentence description; the same favicon as last time.
- **No external resources** — a strict CSP blocks CDNs, webfonts and remote images. Inline all
  CSS/JS, embed assets as `data:` URIs.
- Wide content (tables, code, diagrams) scrolls inside its own `overflow-x:auto` container; the
  page body never scrolls horizontally.
- **Re-skinning an existing artifact:** change only the `<style>` block, then verify with a
  tag-stripped text diff that not one word of content moved and that any `<script>` blocks are
  byte-identical. Republish with the same URL so the link survives.
