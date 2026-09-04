# Tutor visual system

One look for every explainer, so a set of them reads as one family instead of a new palette per
page. Paper-grey ground, white cards, ink-black type, four muted accents that always mean the
same thing.

## Hard rules

- **One theme, light.** Never `@media (prefers-color-scheme:dark)`, never `:root[data-theme="dark"]`.
  The token block below pins all three selectors on purpose.
- **Accents carry meaning, not decoration.** `--tpl` blue = the system / the machine.
  `--dsl` green = good, done, the after. `--alert` red = broken, slow, the before.
  `--signal` amber = attention, the label, the thing to notice.
- **Never shrink an SVG to fit.** Each drawing declares its true `width`/`height` and the `.pic`
  frame scrolls. `max-width:100%` on a diagram is what makes the text unreadable.
- **Re-skinning an existing page = touch only the `<style>` block.** Then diff the tag-stripped
  text to prove not one word of content moved.

## 1. Head (standalone file)

```html
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>The one big claim</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;600;800&family=JetBrains+Mono:wght@400;700&display=swap">
```

Inside an Artifact there is no `<head>` to write into — put the font import as the first line of
your `<style>` instead:

```css
@import url('https://fonts.googleapis.com/css2?family=Archivo:wght@400;600;800&family=JetBrains+Mono:wght@400;700&display=swap');
```

## 2. Tokens and components — copy verbatim

```css
:root, :root[data-theme="dark"], :root[data-theme="light"]{
  color-scheme:light;
  --ground:#ECEEF1; --surface:#FFFFFF; --surface-2:#F3F5F8; --sunk:#E0E4EA;
  --ink:#12151A; --ink-2:#5A6573; --ink-3:#8B95A2;
  --line:#CFD6DE; --line-strong:#A9B3BF;
  --signal:#9C6A05; --signal-soft:#F7E9C9;
  --tpl:#1F5A87;   --tpl-soft:#DBE9F3;
  --dsl:#456E22;   --dsl-soft:#E0EDD2;
  --alert:#8E2F1C; --alert-soft:#F8DFD8;
}
html{background:var(--ground); color:var(--ink); scroll-behavior:smooth}
*{box-sizing:border-box}
html body{
  margin:0; background:var(--ground); color:var(--ink);
  font-family:Archivo,"Helvetica Neue",Arial,sans-serif;
  font-size:18px; line-height:1.5; -webkit-font-smoothing:antialiased;
}
.wrap{max-width:1120px; margin:0 auto; padding:0 22px 110px}

.hero{padding:86px 0 46px; text-align:center}
.kicker{
  font-family:"JetBrains Mono",monospace; font-size:11px; letter-spacing:.2em;
  text-transform:uppercase; color:var(--signal); margin:0 0 22px;
}
h1{
  font-weight:800; font-size:clamp(44px,9vw,86px); line-height:.96;
  letter-spacing:-.035em; margin:0 0 24px; text-wrap:balance;
}
.hero p.sub{
  font-size:clamp(19px,2.6vw,24px); color:var(--ink-2); max-width:30ch;
  margin:0 auto; line-height:1.35; text-wrap:balance;
}

.card{margin:0 0 26px; background:var(--surface); border:1px solid var(--line); border-radius:10px; overflow:hidden}
.card > .top{padding:34px 34px 4px}
.q{
  font-family:"JetBrains Mono",monospace; font-size:11px; letter-spacing:.18em;
  text-transform:uppercase; color:var(--signal); margin:0 0 14px;
}
h2{font-weight:800; font-size:clamp(26px,4.4vw,38px); line-height:1.06; letter-spacing:-.025em; margin:0 0 18px; text-wrap:balance}
h3{font-weight:800; font-size:20px; line-height:1.15; letter-spacing:-.015em; margin:0 0 10px}
.say{font-size:19px; color:var(--ink-2); margin:0 0 16px; max-width:64ch}
.say strong{color:var(--ink); font-weight:600}
.say code, .mono{font-family:"JetBrains Mono",monospace; font-size:.84em; background:var(--sunk); padding:1px 6px; border-radius:4px; color:var(--ink)}

/* Drawing frame. Each SVG keeps its natural size; the frame scrolls. */
.pic{position:relative; overflow:auto; padding:46px 34px 30px; background:var(--surface)}
.pic svg{display:block; max-width:none; height:auto; margin:0 auto}
.zoom{
  position:absolute; top:12px; right:34px; z-index:2;
  font-family:"JetBrains Mono",monospace; font-size:10px; letter-spacing:.12em;
  text-transform:uppercase; cursor:pointer; color:var(--ink-2);
  background:var(--surface); border:1px solid var(--line); border-radius:999px; padding:7px 13px;
}
.zoom:hover{border-color:var(--line-strong); color:var(--ink)}
.zoom:focus-visible{outline:2px solid var(--signal); outline-offset:2px}
.pic:fullscreen{background:var(--surface); display:flex; align-items:center; justify-content:center; padding:44px}
.pic:fullscreen svg{max-width:100%; max-height:100%; width:auto; height:auto}
.cap{padding:14px 34px 30px; margin:0; font-size:15px; color:var(--ink-2); max-width:80ch; line-height:1.5}
.cap strong{color:var(--ink); font-weight:600}
.paso{
  display:inline-flex; align-items:center; justify-content:center;
  width:22px; height:22px; border-radius:50%; background:var(--tpl); color:#fff;
  font-family:"JetBrains Mono",monospace; font-size:11px; font-weight:700;
  vertical-align:middle; margin-right:6px;
}
.hint{font-family:"JetBrains Mono",monospace; font-size:10px; letter-spacing:.12em; text-transform:uppercase; color:var(--ink-3)}

/* SVG drawing classes — identical across every diagram */
.b{fill:var(--surface-2); stroke:var(--line-strong); stroke-width:1.5}
.b-t{fill:var(--tpl-soft); stroke:var(--tpl); stroke-width:2}
.b-d{fill:var(--dsl-soft); stroke:var(--dsl); stroke-width:2}
.b-a{fill:var(--signal-soft); stroke:var(--signal); stroke-width:2}
.b-s{fill:var(--alert-soft); stroke:var(--alert); stroke-width:2}
.b-ghost{fill:none; stroke:var(--line-strong); stroke-width:1.5; stroke-dasharray:5 4}

.t{font-family:Archivo,sans-serif; font-size:14px; fill:var(--ink); font-weight:600}
.t-b{font-family:Archivo,sans-serif; font-size:17px; fill:var(--ink); font-weight:800}
.t-s{font-family:Archivo,sans-serif; font-size:12px; fill:var(--ink-2); font-weight:400}
.t-lab{font-family:"JetBrains Mono",monospace; font-size:10px; fill:var(--ink-3); letter-spacing:.1em}
.t-arrow{font-family:"JetBrains Mono",monospace; font-size:10px; fill:var(--ink-3); letter-spacing:.06em}
.t-box{font-family:Archivo,sans-serif; font-size:13px; fill:var(--ink); font-weight:400}
.t-big{font-family:Archivo,sans-serif; font-size:30px; font-weight:800; fill:var(--ink)}
.t-clock{font-family:"JetBrains Mono",monospace; font-size:22px; font-weight:700}
.ico{font-size:22px}
.ico-s{font-size:16px}

.ln{stroke:var(--line-strong); stroke-width:2; fill:none}
.ln-t{stroke:var(--tpl); stroke-width:2.5; fill:none}
.ln-d{stroke:var(--dsl); stroke-width:2.5; fill:none}
.ln-a{stroke:var(--signal); stroke-width:2.5; fill:none}
.ln-s{stroke:var(--alert); stroke-width:2.5; fill:none; stroke-dasharray:6 4}

.grid{display:grid; grid-template-columns:1fr 1fr; gap:16px; padding:10px 34px 34px}
.grid.g3{grid-template-columns:repeat(3,1fr)}
.grid.g4{grid-template-columns:repeat(4,1fr)}
@media (max-width:760px){
  .grid, .grid.g3, .grid.g4{grid-template-columns:1fr}
  .card > .top{padding:26px 22px 4px} .pic{padding:14px 18px 26px}
  .grid{padding:8px 22px 26px} .cap{padding:0 22px 26px}
}
.v{border-radius:8px; padding:18px 20px; border:1px solid var(--line); background:var(--surface-2)}
.v h4{margin:0 0 8px; font-size:16px; font-weight:800; letter-spacing:-.01em}
.v p{margin:0; font-size:15px; color:var(--ink-2); line-height:1.45}
.v.yes{background:var(--dsl-soft); border-color:var(--dsl)} .v.yes h4{color:var(--dsl)}
.v.no{background:var(--alert-soft); border-color:var(--alert)} .v.no h4{color:var(--alert)}
.v.warn{background:var(--signal-soft); border-color:var(--signal)} .v.warn h4{color:var(--signal)}
.v.info{background:var(--tpl-soft); border-color:var(--tpl)} .v.info h4{color:var(--tpl)}
.v .n{font-family:"JetBrains Mono",monospace; font-size:30px; font-weight:700; letter-spacing:-.03em; display:block; margin:0 0 4px}

table{width:100%; border-collapse:collapse; font-size:15px}
.tablewrap{overflow-x:auto; padding:6px 34px 34px}
th{font-family:"JetBrains Mono",monospace; font-size:10px; letter-spacing:.12em; text-transform:uppercase; color:var(--ink-3); text-align:left; padding:0 12px 10px 0; font-weight:400; border-bottom:1px solid var(--line)}
td{padding:11px 12px 11px 0; border-bottom:1px solid var(--line); color:var(--ink-2); vertical-align:top}
td strong{color:var(--ink); font-weight:600}
td.num{font-variant-numeric:tabular-nums; font-family:"JetBrains Mono",monospace; font-size:14px; white-space:nowrap}
tr.win td{background:var(--dsl-soft)} tr.win td strong{color:var(--dsl)}
tr.bad td{background:var(--alert-soft)} tr.bad td strong{color:var(--alert)}

.steps{counter-reset:s; list-style:none; margin:0; padding:6px 34px 34px}
.steps li{counter-increment:s; position:relative; padding:0 0 18px 44px; color:var(--ink-2); font-size:16px; line-height:1.45}
.steps li::before{
  content:counter(s); position:absolute; left:0; top:-1px;
  font-family:"JetBrains Mono",monospace; font-size:12px; font-weight:700;
  width:28px; height:28px; border-radius:50%; background:var(--sunk); color:var(--ink);
  display:flex; align-items:center; justify-content:center;
}
.steps li strong{color:var(--ink); font-weight:600}

.plain{margin:0; padding:6px 34px 34px 56px; color:var(--ink-2)}
.plain li{font-size:16px; line-height:1.5; margin-bottom:9px}
.plain li strong{color:var(--ink); font-weight:600}

.tabs{
  display:flex; gap:8px; justify-content:center; flex-wrap:wrap;
  padding:14px 0 34px; position:sticky; top:0; z-index:5; background:var(--ground);
}
.tabs button{
  font-family:"JetBrains Mono",monospace; font-size:11px; letter-spacing:.14em;
  text-transform:uppercase; cursor:pointer;
  background:var(--surface); color:var(--ink-2);
  border:1px solid var(--line); border-radius:999px;
  padding:11px 20px; transition:background .12s, color .12s, border-color .12s;
}
.tabs button:hover{border-color:var(--line-strong); color:var(--ink)}
.tabs button:focus-visible{outline:2px solid var(--signal); outline-offset:2px}
.tabs button[aria-selected="true"]{background:var(--ink); color:var(--surface); border-color:var(--ink)}
.panel[hidden]{display:none}
@media (max-width:760px){ .tabs{padding-bottom:24px} .tabs button{padding:9px 14px; font-size:10px} }

footer{
  font-family:"JetBrains Mono",monospace; font-size:11px; color:var(--ink-3);
  text-align:center; padding:30px 0 0; letter-spacing:.08em; line-height:2;
}
@media (prefers-reduced-motion:reduce){ *{transition:none!important; scroll-behavior:auto!important} }
```

## 3. Page skeleton

```html
<div class="wrap">

  <div class="hero">
    <p class="kicker">Subject · context</p>
    <h1>The one big claim</h1>
    <p class="sub">One line saying what this page settles.</p>
  </div>

  <!-- tabs only when the topic has 3+ distinct parts -->
  <div class="tabs" role="tablist" aria-label="Sections">
    <button role="tab" id="tab-a" aria-controls="panel-a" aria-selected="true"  data-panel="a">What it is</button>
    <button role="tab" id="tab-b" aria-controls="panel-b" aria-selected="false" data-panel="b">How it runs</button>
  </div>

  <div class="panel" id="panel-a" role="tabpanel" aria-labelledby="tab-a">
    <section class="card">
      <div class="top">
        <p class="q">The question this card answers</p>
        <h2>The answer, as a sentence.</h2>
        <p class="say">Two short paragraphs, max. <strong>Bold the noun that matters.</strong></p>
      </div>

      <div class="pic">
        <svg viewBox="0 0 700 320" width="700" height="320" role="img" aria-label="Say in words what the drawing shows">
          <text x="20" y="26" class="t-lab">BEFORE</text>
          <rect x="20" y="40" width="200" height="76" rx="10" class="b"/>
          <path class="ln" d="M220 78 H 458" marker-end="url(#arrow)"/>
          <rect x="458" y="40" width="222" height="76" rx="10" class="b-d"/>
        </svg>
      </div>
      <p class="cap">What to look at in the drawing, and why it matters.</p>
    </section>
  </div>

</div>
```

Arrowheads need a `<defs>` marker per color, once per SVG:

```html
<defs>
  <marker id="a-gr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
    <path d="M0,0 L10,5 L0,10 z" fill="#A9B3BF"/>
  </marker>
</defs>
```

`marker` ignores `currentColor` in several engines, so give the marker path a literal hex matching
its line token (`--line-strong` `#A9B3BF`, `--tpl` `#1F5A87`, `--dsl` `#456E22`, `--alert` `#8E2F1C`).

## 4. Behavior — no libraries

```html
<script>
// Fullscreen any drawing, native API only.
(function(){
  if (!document.fullscreenEnabled) return;
  document.querySelectorAll('.pic').forEach(function(pic){
    var b = document.createElement('button');
    b.className = 'zoom'; b.type = 'button'; b.textContent = 'Zoom';
    b.addEventListener('click', function(){
      if (document.fullscreenElement === pic) document.exitFullscreen();
      else pic.requestFullscreen().catch(function(){});
    });
    document.addEventListener('fullscreenchange', function(){
      b.textContent = (document.fullscreenElement === pic) ? 'Close' : 'Zoom';
    });
    pic.appendChild(b);
  });
})();

// Tabs, with arrow-key navigation.
(function(){
  var tabs = Array.prototype.slice.call(document.querySelectorAll('.tabs button'));
  function select(tab){
    tabs.forEach(function(t){
      var on = t === tab;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      document.getElementById('panel-' + t.dataset.panel).hidden = !on;
    });
    window.scrollTo({top:0, behavior:'instant'});
  }
  tabs.forEach(function(t){
    t.addEventListener('click', function(){ select(t); });
    t.addEventListener('keydown', function(e){
      var i = tabs.indexOf(t), n = null;
      if (e.key === 'ArrowRight') n = tabs[(i+1) % tabs.length];
      if (e.key === 'ArrowLeft')  n = tabs[(i-1+tabs.length) % tabs.length];
      if (n){ e.preventDefault(); n.focus(); select(n); }
    });
  });
})();
</script>
```

## 5. Mermaid, when it fits

A plain sequence or flow can be a ```mermaid fence (markdown) or `<pre class="mermaid">` (HTML) —
Artifacts render it natively, never load a library. Everything that needs layout control, icons,
emphasis or a timeline is hand-written SVG instead.
