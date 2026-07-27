<title>Employee OS — [OWNER] @ [ORG]</title>
<style>
  :root{
    --primary:#8b5cf6; --fg:#252525; --muted-fg:#8e8e8e; --bg:#ffffff; --surface:#f7f7f7; --border:#e5e7eb;
    --green-600:#16a34a; --green-100:#dcfce7; --green-50:#f0fdf4; --green-200:#bbf7d0; --green-700:#15803d;
    --amber-50:#fffbeb; --amber-200:#fde68a; --amber-300:#fcd34d; --amber-700:#b45309;
    --red-50:#fef2f2; --red-200:#fecaca; --red-300:#fca5a5; --red-600:#dc2626; --red-700:#b91c1c;
    --sans:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
    --mono:'SF Mono',source-code-pro,Menlo,Monaco,Consolas,monospace;
  }
  *{box-sizing:border-box;}
  body{font-family:var(--sans); color:var(--fg); margin:0; line-height:1.5; -webkit-font-smoothing:antialiased;
    background:radial-gradient(1200px 600px at 85% -10%, rgba(139,92,246,.07), transparent 60%),radial-gradient(900px 500px at 0% 5%, rgba(22,163,74,.05), transparent 55%),#fbfbfc;}
  .app{max-width:1560px; margin:0 auto; padding:14px 18px 10px; opacity:0; animation:rise .5s ease forwards;}
  @keyframes rise{to{opacity:1;}}

  /* top bar */
  .topbar{display:flex; align-items:center; gap:14px; flex-wrap:wrap; padding:6px 2px 10px;}
  .tb-l{display:flex; align-items:center; gap:10px; flex:none;}
  .tb-logo{font-size:24px;}
  .tb-eyebrow{font-size:10px; font-weight:700; letter-spacing:.04em; color:var(--muted-fg); text-transform:uppercase;}
  .tb-t{font-size:16.5px; font-weight:800; letter-spacing:-.02em;}
  .tb-t em{font-style:normal; color:var(--primary);}
  .tb-s{font-size:10.5px; color:var(--muted-fg); font-family:var(--mono);}
  .tb-search{position:relative; flex:1; min-width:230px; max-width:460px;}
  .tb-search input{width:100%; font-family:var(--sans); font-size:13px; padding:8px 30px 8px 34px; border:1px solid var(--border); border-radius:10px; background:#fff; outline:none; transition:border .15s, box-shadow .15s;}
  .tb-search input:focus{border-color:var(--primary); box-shadow:0 0 0 3px rgba(139,92,246,.15);}
  .tb-search .qi{position:absolute; left:11px; top:8px; font-size:13px; color:var(--muted-fg); pointer-events:none;}
  .tb-search #qClear{position:absolute; right:6px; top:5px; border:0; background:transparent; color:var(--muted-fg); font-size:13px; cursor:pointer; padding:3px 6px; border-radius:6px; display:none;}
  .tb-search #qClear:hover{background:var(--surface); color:var(--fg);}
  #qResults{position:absolute; top:38px; left:0; right:0; background:#fff; border:1px solid var(--border); border-radius:12px; box-shadow:0 18px 50px -18px rgba(20,20,30,.35); z-index:50; max-height:330px; overflow-y:auto; display:none;}
  #qResults .qr{display:flex; align-items:center; gap:9px; padding:8px 12px; font-size:13px; cursor:pointer;}
  #qResults .qr:hover, #qResults .qr.hot{background:#faf8ff;}
  #qResults .qr .gtag{margin-left:auto; font-size:9.5px; font-weight:700; padding:2px 7px; border-radius:999px; flex:none;}
  #qResults .qempty{padding:10px 12px; font-size:12.5px; color:var(--muted-fg);}
  .tb-views{display:flex; gap:6px; flex:none; margin-left:auto;}
  .tb-views button{font-family:var(--sans); font-size:12.5px; font-weight:600; border-radius:10px; padding:7px 13px; border:1px solid var(--border); background:#fff; color:#4b4b4f; cursor:pointer;}
  .tb-views button.on{background:var(--primary); border-color:var(--primary); color:#fff;}

  /* lenses */
  .lens-row{display:flex; align-items:center; gap:12px; flex-wrap:wrap; padding:0 2px 10px;}
  .lens-bar{display:flex; flex-wrap:wrap; gap:7px;}
  .lens{font-family:var(--sans); font-size:12px; font-weight:600; border-radius:999px; padding:5px 12px; border:1px solid var(--border); background:#fff; color:#4b4b4f; cursor:pointer; transition:all .15s;}
  .lens:hover{border-color:var(--primary); color:var(--primary);}
  .lens.on{background:var(--primary); border-color:var(--primary); color:#fff;}
  .lens-note{font-size:12px; color:var(--muted-fg); flex:1; min-width:200px;}

  /* main stage + panel */
  .main{display:flex; gap:14px; align-items:stretch; height:calc(100vh - 205px); min-height:540px; max-height:980px;}
  .main.panelfull .stage{display:none;}
  .main.panelfull #panel{flex:1; width:auto;}
  .stage{flex:1; min-width:0; position:relative; border:1px solid var(--border); border-radius:16px; background:radial-gradient(closest-side at 50% 50%, #ffffff 62%, #fcfcfe 100%); box-shadow:0 24px 60px -32px rgba(20,20,30,.28); overflow:hidden;}
  #graph,#matrix{width:100%; height:100%; display:block; touch-action:none;}
  #graph{cursor:grab;} #graph.panning{cursor:grabbing;}
  #matrix{cursor:grab;} #matrix.panning{cursor:grabbing;}
  .marquee-rect{fill:rgba(139,92,246,.10); stroke:#8b5cf6; stroke-width:1.4; stroke-dasharray:5 4; pointer-events:none; display:none;}
  @keyframes mxpulse{0%{r:7; stroke-width:1.6;}40%{r:16; stroke-width:0.5;}100%{r:7; stroke-width:1.6;}}
  .dot.mx-pulse circle{animation:mxpulse 1.5s ease-out;}
  #graph .node{cursor:pointer; outline:none;}
  #graph .node .core{transition:stroke-width .15s;}
  #graph .node.sel .core{stroke:var(--primary) !important; stroke-width:3;}
  #graph .nlab{font-weight:600; fill:#3f3f43; paint-order:stroke; stroke:#ffffff; stroke-width:3px; stroke-linejoin:round; pointer-events:none;}
  #graph .nsub{font-family:var(--mono); fill:#9a9aa0; paint-order:stroke; stroke:#ffffff; stroke-width:2.5px; pointer-events:none;}
  #graph .edge{fill:none; pointer-events:none;}
  #graph .elab{font-family:var(--mono); font-size:10px; fill:#52525b; paint-order:stroke; stroke:#ffffff; stroke-width:3.5px; opacity:0; pointer-events:none; transition:opacity .2s;}
  #graph .elab.show{opacity:1;}
  #graph .ringlab,#graph .seclab{font-family:var(--mono); pointer-events:none;}
  #graph .node, #graph .edge{transition:opacity .3s;}
  #graph .satlab{opacity:0; transition:opacity .15s; pointer-events:none;}
  #graph .node.sat:hover .satlab, #graph .node.sat.sel .satlab{opacity:1;}
  #graph .satlink{fill:none; pointer-events:none;}
  #clearSel{position:absolute; top:12px; right:12px; z-index:10; display:none; font-family:var(--sans); font-size:12.5px; font-weight:700; border:1px solid var(--border); background:#fff; color:var(--fg); border-radius:999px; padding:7px 14px; cursor:pointer; box-shadow:0 8px 24px -10px rgba(20,20,30,.35);}
  #clearSel:hover{border-color:var(--primary); color:var(--primary);}
  .ov-cluster{position:absolute; left:12px; bottom:12px; z-index:9; display:flex; gap:8px; align-items:flex-end;}
  .ov-item{position:relative;}
  .ov-chip{font-family:var(--sans); font-size:11px; font-weight:700; border:1px solid var(--border); background:rgba(255,255,255,.92); color:#4b4b4f; border-radius:999px; padding:6px 12px; cursor:pointer; backdrop-filter:blur(4px);}
  .ov-chip:hover{border-color:var(--primary); color:var(--primary);}
  .ov-chip.on{background:var(--primary); border-color:var(--primary); color:#fff;}
  .ov-panel{display:none; position:absolute; left:0; bottom:calc(100% + 6px); background:rgba(255,255,255,.96); border:1px solid var(--border); border-radius:12px; padding:9px 12px; backdrop-filter:blur(4px); box-shadow:0 18px 50px -18px rgba(20,20,30,.35);}
  .ov-panel.open{display:block;}
  .ov-x{position:absolute; top:5px; right:5px; border:0; background:transparent; color:var(--muted-fg); font-size:11px; cursor:pointer; padding:3px 6px; border-radius:6px; line-height:1;}
  .ov-x:hover{background:var(--surface); color:var(--fg);}
  .legend-ov{max-width:520px;}
  #legendContent{display:flex; flex-wrap:wrap; gap:4px 12px; font-size:10.5px; color:#5a5a5e;}
  #legendContent .sw{display:inline-block; width:10px; height:10px; border-radius:3px; border:1px solid; vertical-align:-1px; margin-right:4px;}
  #legendContent .ln{display:inline-block; width:16px; height:0; border-top:2px solid; vertical-align:3px; margin-right:4px;}
  #legendContent .ln.dash{border-top-style:dashed;} #legendContent .ln.dot{border-top-style:dotted;}
  .filters-ov{max-width:230px;}
  #filtersContent .fsec{font-size:9.5px; font-weight:700; letter-spacing:.06em; text-transform:uppercase; color:var(--muted-fg); margin:8px 0 5px;}
  #filtersContent .fsec:first-child{margin-top:0;}
  .fchk{display:flex; align-items:center; gap:7px; font-size:12px; padding:4px 4px; border-radius:6px; cursor:pointer;}
  .fchk:hover{background:var(--surface);}
  .fchk input{accent-color:var(--primary); width:13px; height:13px; flex:none;}
  .fmini{font-size:9.5px; font-weight:600; text-transform:none; border:1px solid var(--border); background:transparent; color:var(--muted-fg); border-radius:999px; padding:1px 7px; cursor:pointer; opacity:.55;}
  .fmini:hover{opacity:1; border-color:var(--primary); color:var(--primary);}
  .fsolo{margin-left:auto;}
  .freset{display:block; margin:0 0 8px; width:100%; text-align:center;}
  #filtersContent .fhint{font-size:10.5px; color:var(--muted-fg); line-height:1.5; margin:8px 0 0; padding-top:7px; border-top:1px dashed var(--border);}
  .filters-empty{position:absolute; inset:0; z-index:11; display:none; align-items:center; justify-content:center; background:rgba(255,255,255,.75); backdrop-filter:blur(2px);}
  .fe-box{background:#fff; border:1px solid var(--border); border-radius:14px; padding:20px 24px; text-align:center; box-shadow:0 24px 60px -24px rgba(20,20,30,.35); max-width:270px;}
  .fe-box p{margin:0 0 12px; font-size:13px; font-weight:700; color:#3f3f43;}
  .fe-box button{font-family:var(--sans); font-size:12.5px; font-weight:700; border:1px solid var(--primary); background:var(--primary); color:#fff; border-radius:999px; padding:8px 16px; cursor:pointer;}
  .fe-box button:hover{opacity:.9;}
  .ctrl-toolbar{position:absolute; right:12px; bottom:12px; z-index:9; display:flex; gap:4px;}
  .ctrl-btn{width:27px; height:27px; display:grid; place-items:center; font-family:var(--sans); font-size:14px; font-weight:700; border:1px solid var(--border); background:rgba(255,255,255,.92); color:#4b4b4f; border-radius:8px; cursor:pointer; backdrop-filter:blur(4px); line-height:1; padding:0;}
  .ctrl-btn:hover{border-color:var(--primary); color:var(--primary);}
  .ctrl-btn.on{background:var(--primary); border-color:var(--primary); color:#fff;}
  .stage.maximized{position:fixed; inset:0; z-index:1000; border-radius:0;}

  /* panel */
  #panel{width:400px; flex:none; border:1px solid var(--border); border-radius:16px; background:#fff; box-shadow:0 12px 34px -22px rgba(20,20,30,.25); display:flex; flex-direction:column; overflow:hidden; transition:width .25s ease;}
  #panel.wide{width:660px;}
  #pExpand{margin-left:auto; border:0; background:transparent; color:var(--muted-fg); font-size:14px; cursor:pointer; padding:6px 10px; border-radius:8px;}
  #pExpand:hover{background:var(--surface); color:var(--fg);}
  .ptabs{display:flex; flex-wrap:wrap; gap:2px; padding:8px 8px 0; border-bottom:1px solid var(--border); flex:none; background:#fcfcfe;}
  .ptabs button{font-family:var(--sans); font-size:12px; font-weight:600; border:0; background:transparent; color:#6a6a70; padding:8px 12px; cursor:pointer; border-radius:8px 8px 0 0; border-bottom:2px solid transparent;}
  .ptabs button.on{color:var(--primary); border-bottom-color:var(--primary); background:#fff;}
  .ptab{display:none; overflow-y:auto; padding:16px; flex:1;}
  .ptab.on{display:block;}
  #panel h3{margin:0 0 8px; font-size:16px; letter-spacing:-.01em;}
  .chips{display:flex; flex-wrap:wrap; gap:5px; margin:0 0 12px;}
  .chip{font-size:10px; font-weight:700; padding:3px 8px; border-radius:999px; border:1px solid var(--border); background:var(--surface); color:#4b4b4f; letter-spacing:.02em;}
  .pbody{font-size:13px; color:#3f3f43; line-height:1.6;}
  .pbody code{font-family:var(--mono); font-size:11.5px; background:var(--surface); padding:1px 5px; border-radius:4px;}
  .entry{margin-top:12px; padding:10px 12px; border-left:3px solid var(--primary); background:#faf8ff; border-radius:0 8px 8px 0; font-size:12.5px; color:#3f3f43;}
  .entry b{color:var(--primary);}
  .sect{margin-top:14px; border-top:1px dashed var(--border); padding-top:10px;}
  .sect .t{font-size:10px; font-weight:700; letter-spacing:.08em; text-transform:uppercase; color:var(--muted-fg); margin-bottom:7px;}
  .ppl{display:flex; flex-wrap:wrap; gap:6px;}
  .pchip{display:inline-flex; align-items:center; gap:6px; font-size:11.5px; background:var(--surface); border:1px solid var(--border); border-radius:999px; padding:3px 10px 3px 4px; color:#3f3f43;}
  .pchip i{font-style:normal; width:18px; height:18px; border-radius:50%; background:var(--primary); color:#fff; font-size:8.5px; font-weight:800; display:grid; place-items:center; letter-spacing:.02em;}
  .pchip small{color:var(--muted-fg); font-size:10px;}
  .lnks{display:grid; gap:5px;}
  .lnk{display:flex; align-items:center; gap:8px; font-size:12.5px; padding:7px 10px; border:1px solid var(--border); border-radius:10px; text-decoration:none; color:#3f3f43; background:#fff;}
  .lnk:hover{border-color:var(--primary); background:#faf8ff;}
  .lnk .ic{flex:none;}
  .lnk .u{margin-left:auto; font-family:var(--mono); font-size:9.5px; color:var(--muted-fg); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; max-width:110px;}
  .insbtns{display:flex; flex-wrap:wrap; gap:6px;}
  .insbtn{font-size:11px; font-weight:700; border:1px solid #ddd6fe; background:#f5f3ff; color:#5b21b6; border-radius:999px; padding:4px 11px; cursor:pointer;}
  .insbtn:hover{background:#ede9fe;}
  .conn{display:flex; gap:7px; align-items:baseline; font-size:12px; padding:5px 6px; border-radius:8px; cursor:pointer;}
  .conn:hover{background:var(--surface);}
  .conn .dot{width:8px; height:8px; border-radius:50%; flex:none; align-self:center;}
  .conn .lbl{color:var(--muted-fg); font-family:var(--mono); font-size:10px; margin-left:auto; text-align:right;}
  .hint{font-size:12.5px; color:var(--muted-fg);}
  kbd{font-family:var(--mono); font-size:10px; background:var(--surface); border:1px solid var(--border); border-bottom-width:2px; border-radius:5px; padding:1px 5px;}

  /* insights / week cards inside panel */
  .prob{background:var(--bg); border:1px solid var(--border); border-radius:12px; padding:13px 14px; position:relative; overflow:hidden; margin-bottom:10px;}
  .prob::before{content:""; position:absolute; inset:0 auto 0 0; width:3px; background:var(--amber-300);}
  .prob.red::before{background:var(--red-300);} .prob.vio::before{background:var(--primary);} .prob.grn::before{background:var(--green-600);} .prob.amb::before{background:var(--amber-300);}
  .prob h4{font-size:12.5px; margin:0 0 5px; font-weight:700;}
  .prob p{font-size:12px; color:#5a5a5e; margin:0; line-height:1.55;}
  .prob.flash{animation:flash 1.6s ease;}
  @keyframes flash{0%{background:#f5f3ff;}100%{background:#fff;}}
  .mnote.flash{animation:flash 1.6s ease; border-radius:8px;}
  .phase{border:1px solid var(--border); border-radius:12px; padding:13px 14px; background:#fff; margin-bottom:10px;}
  .phase.now{border-color:var(--green-200); background:var(--green-50);}
  .phase .ord{font-family:var(--mono); font-size:11px; font-weight:700; color:var(--primary);}
  .phase h4{font-size:13px; margin:5px 0 4px;} .phase p{font-size:12px; color:#5a5a5e; margin:0 0 8px;}
  .tagp{font-size:10px; font-weight:700; padding:2px 8px; border-radius:999px; background:var(--surface); color:#6a6a70; border:1px solid var(--border);}
  .tagp.now{background:var(--green-100); color:var(--green-700); border:0;}
  .srcl{display:grid; gap:8px; font-size:12.5px;}
  .srcl a{color:var(--primary); text-decoration:none;} .srcl a:hover{text-decoration:underline;}
  .footline{font-size:10.5px; color:#b3b3b8; padding:8px 4px 4px; font-family:var(--mono);}
  .excel{margin-top:12px; padding:11px 13px; border-left:3px solid var(--amber-600); background:var(--amber-50); border-radius:0 8px 8px 0; font-size:12.5px; color:#3f3f43; line-height:1.6;}
  .excel b{color:var(--amber-700);}
  .excel ul{margin:6px 0 0; padding-left:18px;}
  .excel li{margin-bottom:5px;}
  .ckrow{display:flex; gap:8px; align-items:center; font-size:12.5px; padding:5px 6px; border-radius:8px; cursor:pointer;}
  .ckrow:hover{background:var(--surface);}
  .ckrow input{accent-color:var(--primary); width:14px; height:14px; flex:none;}
  .ckrow.done .tt{text-decoration:line-through; color:var(--muted-fg);}
  .jrow{cursor:default;}
  .jrow .tt{color:var(--muted-fg);}
  .ckgroup-hd{cursor:pointer; user-select:none;}
  .ckgroup-hd:hover{color:var(--fg);}
  .ckgroup-body{display:none;}
  .ckgroup-body.open{display:block;}
  .wk-hd{font-size:11px; font-weight:700; color:var(--fg); margin:10px 0 3px; opacity:.8;}
  .wk-hd:first-child{margin-top:0;}
  .day-hd{font-size:11px; color:var(--muted-fg); margin:6px 0 2px 2px;}
  .wk-cnt{font-weight:400; opacity:.75; text-transform:none; letter-spacing:0;}

  /* historial timeline (Historial tab + Hoy "esta semana") */
  .hist-filters{display:flex; flex-wrap:wrap; gap:7px; margin-bottom:14px;}
  .hist-tl .wk-hd{margin-top:20px;}
  .hist-tl .wk-hd:first-child{margin-top:0;}
  .hist-tl .day-hd{margin:14px 0 6px 2px;}
  .hist-tl .ckrow{align-items:flex-start; padding:6px 4px; gap:10px;}
  .hist-tl .ckrow .tt{flex:1; line-height:1.5;}
  .hist-tl .ckrow .chip{margin-top:1px;}
  .hist-actions{display:flex; gap:4px; align-items:center; margin-left:auto; flex:none;}
  .hist-more{display:inline-block; margin-top:4px; font-family:var(--sans); font-size:12px; font-weight:600; color:var(--primary); background:none; border:0; padding:2px 0; cursor:pointer;}
  .hist-more:hover{text-decoration:underline;}
  .ally{border:1px solid var(--border); border-radius:12px; padding:11px 13px; margin-bottom:8px;}
  .ally h4{font-size:12.5px; margin:0 0 4px; display:flex; align-items:center; gap:7px;}
  .ally h4 i{font-style:normal; width:20px; height:20px; border-radius:50%; background:var(--primary); color:#fff; font-size:9px; font-weight:800; display:grid; place-items:center;}
  .ally p{font-size:11.5px; color:#5a5a5e; margin:0; line-height:1.55;}
  .ally p b{color:#3f3f43;}
  .ddbtn{font-size:10px; font-weight:700; border:1px solid #ddd6fe; background:#f5f3ff; color:#5b21b6; border-radius:999px; padding:2px 9px; cursor:pointer; margin-left:8px; flex:none;}
  .ddbtn:hover{background:#ede9fe;}

  @media(max-width:1000px){
    .main{flex-direction:column; height:auto; max-height:none;}
    .stage{height:62vh; min-height:420px;}
    #panel{width:100%; height:480px;}
    .ov-cluster{display:none;}
  }
</style>

<div class="app">
  <div class="topbar">
    <div class="tb-l"><span class="tb-logo">🕸️</span><div><div class="tb-eyebrow">Q3 2026 en foco · historia H1 incluida</div><div class="tb-t">Employee OS — <em>[OWNER] @ [ORG]</em></div><div class="tb-s"><!--@TBS--></div></div></div>
    <div class="tb-search"><span class="qi">🔍</span><input id="q" type="text" placeholder="Buscar nodos, personas, temas…   ( / o ⌘K )" autocomplete="off"><button id="qClear" title="limpiar">✕</button><div id="qResults"></div></div>
    <div class="tb-views"><button id="vOrbit" class="on">🪐 Órbita</button><button id="vMatrix">▦ Matriz</button><button id="vPanel">▤ Panel</button></div>
  </div>
  <div class="lens-row"><div class="lens-bar" id="lensBar"></div><div class="lens-note" id="lensNote"></div></div>

  <div class="main">
    <div class="stage">
      <svg id="graph" viewBox="0 0 1000 1000" preserveAspectRatio="xMidYMid meet" role="img" aria-label="Mapa radial Q3"></svg>
      <svg id="matrix" viewBox="0 0 1100 560" preserveAspectRatio="xMidYMid meet" style="display:none"></svg>
      <button id="clearSel">✕ mostrar todo</button>
      <div class="filters-empty" id="filtersEmpty">
        <div class="fe-box">
          <p>Los filtros ocultan todos los nodos</p>
          <button id="filtersEmptyReset" type="button">Restablecer filtros</button>
        </div>
      </div>
      <div class="ov-cluster" id="ovCluster">
        <div class="ov-item">
          <button class="ov-chip" id="legendChip" type="button">▸ Leyenda</button>
          <div class="ov-panel legend-ov" id="legend">
            <button class="ov-x" id="legendClose" title="cerrar">✕</button>
            <div id="legendContent"></div>
          </div>
        </div>
        <div class="ov-item">
          <button class="ov-chip" id="filtersChip" type="button">▸ Filtros</button>
          <div class="ov-panel filters-ov" id="filters">
            <button class="ov-x" id="filtersClose" title="cerrar">✕</button>
            <div id="filtersContent"></div>
          </div>
        </div>
      </div>
      <div class="ctrl-toolbar" id="ctrlToolbar">
        <button class="ctrl-btn" id="btnZoomOut" title="Alejar (zoom out)">−</button>
        <button class="ctrl-btn" id="btnZoomIn" title="Acercar (zoom in)">+</button>
        <button class="ctrl-btn" id="btnFit" title="Ajustar a lo visible (fit)">⤢</button>
        <button class="ctrl-btn" id="btnMarquee" title="Zoom a región (o Shift+arrastrar)">▧</button>
        <button class="ctrl-btn" id="btnReset" title="Restablecer vista">⟲</button>
        <button class="ctrl-btn" id="btnMax" title="Maximizar / restaurar">⛶</button>
      </div>
    </div>

    <aside id="panel">
      <div class="ptabs">
        <button data-tab="hoy" class="on">Hoy</button>
        <button data-tab="det">Detalle</button>
        <button data-tab="ins">Insights</button>
        <button data-tab="kpi">KPIs</button>
        <button data-tab="ritmo">Ritmo</button>
        <button data-tab="proyectos">Proyectos</button>
        <button data-tab="aliados">Aliados</button>
        <button data-tab="prompt">Prompt</button>
        <button data-tab="src">Fuentes</button>
        <button data-tab="historial">🗄️ Historial</button>
        <button data-tab="memoria">🧠 Memoria</button>
        <button id="pExpand" title="expandir / contraer">⤢</button>
      </div>
      <div class="ptab" id="tab-det"><div id="detBody"></div></div>
      <div class="ptab" id="tab-ins"><!--@TAB_INSIGHTS-->
      </div>
      <div class="ptab on" id="tab-hoy"><div id="hoyBody"></div>
        <pre id="tpl-daily" style="display:none"><!--@TPL_DAILY--></pre>
        <pre id="tpl-weekly" style="display:none"><!--@TPL_WEEKLY--></pre>
        <pre id="tpl-health" style="display:none"><!--@TPL_HEALTH--></pre>
      </div>
      <div class="ptab" id="tab-aliados"><!--@TAB_ALIADOS-->
      </div>
      <div class="ptab" id="tab-ritmo"><!--@TAB_RITMO-->
      </div>
      <div class="ptab" id="tab-proyectos"><!--@TAB_PROYECTOS-->
      </div>
      <div class="ptab" id="tab-kpi"><!--@TAB_KPIS-->
      </div>
      <div class="ptab" id="tab-prompt"><!--@TAB_PROMPT_HEAD--><pre id="promptText" style="white-space:pre-wrap;font-family:var(--mono);font-size:10.5px;line-height:1.55;background:#1e1e2e;color:#e4e4ef;border-radius:12px;padding:14px 16px;margin:0;">
<!--@PROMPT--></pre>
      </div>
      <div class="ptab" id="tab-src"><!--@TAB_FUENTES-->
      </div>
      <div class="ptab" id="tab-historial">
        <div class="hist-filters" id="histFilters"></div>
        <div class="hist-tl" id="histTlBody"></div>
      </div>
      <div class="ptab" id="tab-memoria"><div id="memoriaBody"></div></div>
    </aside>
  </div>
  <div class="footline">source of truth: el archivo local docs/agent-evals-q2/q3-map-2026.html (funciona offline) — el artifact es una copia publicada de ese archivo</div>
</div>


<script>
/*@DATA*/
const RIT_BY={};RITUALS.forEach(function(r){RIT_BY[r.id]=r;});
const GROUPS={
 bets:{fill:"#f5f3ff",stroke:"#ddd6fe",text:"#5b21b6",label:"Apuestas"},
 builder:{fill:"#eff6ff",stroke:"#bfdbfe",text:"#1d4ed8",label:"Builder"},
 cluster:{fill:"#fffbeb",stroke:"#fde68a",text:"#92400e",label:"Evals & Testing"},
 process:{fill:"#f0fdf4",stroke:"#bbf7d0",text:"#166534",label:"Proceso/Calidad"},
 code:{fill:"#f7f7f7",stroke:"#e5e7eb",text:"#374151",label:"Fundaciones"},
 external:{fill:"#fdf2f8",stroke:"#fbcfe8",text:"#9d174d",label:"Externo"},
 people:{fill:"#eef2ff",stroke:"#c7d2fe",text:"#4338ca",label:"Aliados"},
 mine:{fill:"#ecfeff",stroke:"#a5f3fc",text:"#155e75",label:"Personal"},
 shipped:{fill:"#f1f5f9",stroke:"#94a3b8",text:"#0f766e",label:"H1 shipped"}
};
const EDGE_STYLE={dep:{color:"#9aa3af",dash:null,name:"depende de"},feeds:{color:"#16a34a",dash:null,name:"alimenta"},risk:{color:"#dc2626",dash:"6 4",name:"riesgo para"},val:{color:"#8b5cf6",dash:"2 4",name:"valida/presiona"},own:{color:"#4338ca",dash:"1 4",name:"le importa / impulsa"}};
const STATUS_STYLE={"existe":["#dcfce7","#15803d"],"parcial":["#fef3c7","#b45309"],"no existe":["#fee2e2","#b91c1c"],"decisión":["#ede9fe","#6d28d9"],"en curso":["#e0f2fe","#0369a1"],"idea":["#f4f4f5","#52525b"],"aliado":["#eef2ff","#4338ca"]};
const NS="http://www.w3.org/2000/svg";
const CX=500,CY=500;
const RING={5:150,4:232,3:310,2:385,1:450};
const SECTOR_ORDER=["builder","bets","external","people","mine","code","shipped","process","cluster"];
const SECTOR_SPAN={builder:42,bets:42,external:23,people:48,mine:22,code:20,shipped:42,process:48,cluster:73};
const byId={}; NODES.forEach(function(n){byId[n.id]=n;});
var sectorStart={},acc=-90-SECTOR_SPAN.builder/2;
SECTOR_ORDER.forEach(function(g){sectorStart[g]=acc;acc+=SECTOR_SPAN[g];});
const THEME_NODES=NODES.filter(function(n){return n.group!=="issues";});
const SAT_NODES=NODES.filter(function(n){return n.group==="issues";});
(function(){
 var byGR={};
 THEME_NODES.forEach(function(n){var k=n.group+"|"+n.prioScore;(byGR[k]=byGR[k]||[]).push(n);});
 Object.keys(byGR).forEach(function(k){byGR[k].sort(function(a,b){return a.slot-b.slot;});});
 THEME_NODES.forEach(function(n){
  var arr=byGR[n.group+"|"+n.prioScore],i=arr.indexOf(n),c=arr.length;
  var span=SECTOR_SPAN[n.group],start=sectorStart[n.group];
  var pad=Math.min(10,span*0.14);
  var a=(c===1)?(start+span/2):(start+pad+(span-2*pad)*(i/(c-1)));
  var rad=a*Math.PI/180;
  n.r=RING[n.prioScore]+((c>=3&&i%2===1)?26:0);
  n.x=CX+n.r*Math.cos(rad); n.y=CY+n.r*Math.sin(rad);
  n.size=n.prioScore>=5?27:(n.prioScore===4?23:(n.prioScore===3?20:17));
 });
})();
// satellites: orbit around their parent theme node (positioned above), fanned evenly by index
const SAT_R=46;
var satsByParent={},satParent={};
SAT_NODES.forEach(function(n){(satsByParent[n.parent]=satsByParent[n.parent]||[]).push(n);satParent[n.id]=n.parent;});
Object.keys(satsByParent).forEach(function(pid){
 var parent=byId[pid];if(!parent)return;
 var list=satsByParent[pid],count=list.length,base=Math.PI/5;
 list.forEach(function(n,i){
  var ang=base+(i/count)*2*Math.PI;
  n.x=parent.x+SAT_R*Math.cos(ang); n.y=parent.y+SAT_R*Math.sin(ang);
  n.size=9;
 });
});
function themeGroupOf(n){return (n.parent&&byId[n.parent])?byId[n.parent].group:n.group;}
function grFor(n){return GROUPS[themeGroupOf(n)]||GROUPS.code;}
const deg={}; EDGES.forEach(function(e){deg[e.from]=(deg[e.from]||0)+1;deg[e.to]=(deg[e.to]||0)+1;});
var state={lens:"all",selected:null,hover:null,searchSet:null};
function el(tag,attrs,parent){var e=document.createElementNS(NS,tag);for(var k in attrs)e.setAttribute(k,attrs[k]);if(parent)parent.appendChild(e);return e;}
const svg=document.getElementById("graph");
const vp=el("g",{id:"vp"},svg);
var defs=el("defs",{},svg);
Object.keys(EDGE_STYLE).forEach(function(t){
 var m=el("marker",{id:"arr-"+t,viewBox:"0 0 10 10",refX:"8",refY:"5",markerWidth:"6",markerHeight:"6",orient:"auto"},defs);
 el("path",{d:"M0,0 L10,5 L0,10 z",fill:EDGE_STYLE[t].color},m);
});
const decor=el("g",{id:"decor"},vp);
function arcPath(r0,r1,a0,a1){
 var large=(a1-a0)>Math.PI?1:0;
 function px(r,a){return (CX+r*Math.cos(a)).toFixed(1)+","+(CY+r*Math.sin(a)).toFixed(1);}
 return "M"+px(r1,a0)+" A"+r1+" "+r1+" 0 "+large+" 1 "+px(r1,a1)+" L"+px(r0,a1)+" A"+r0+" "+r0+" 0 "+large+" 0 "+px(r0,a0)+" Z";
}
SECTOR_ORDER.forEach(function(g){
 var a0=sectorStart[g]*Math.PI/180,a1=(sectorStart[g]+SECTOR_SPAN[g])*Math.PI/180;
 el("path",{d:arcPath(112,478,a0+0.008,a1-0.008),fill:GROUPS[g].fill,"fill-opacity":"0.5",stroke:"none"},decor);
 var mid=(a0+a1)/2, lx=CX+496*Math.cos(mid), ly=CY+496*Math.sin(mid);
 lx=Math.max(62,Math.min(938,lx)); ly=Math.max(16,Math.min(990,ly));
 var t=el("text",{x:lx,y:ly,"text-anchor":"middle","dominant-baseline":"middle","class":"seclab","font-size":"10.5","font-weight":"700","letter-spacing":"1.5",fill:GROUPS[g].text},decor);
 t.textContent=GROUPS[g].label.toUpperCase();
});
[5,4,3,2,1].forEach(function(s){el("circle",{cx:CX,cy:CY,r:RING[s],fill:"none",stroke:"#e9e9ef","stroke-dasharray":"2 7"},decor);});
[[150,"P0 ★"],[232,"P0"],[310,"P1"],[385,"P2"],[450,"contexto"]].forEach(function(rl){
 var ang=44.5*Math.PI/180;
 var t=el("text",{x:CX+(rl[0]+14)*Math.cos(ang),y:CY+(rl[0]+14)*Math.sin(ang),"text-anchor":"middle","class":"ringlab","font-size":"9",fill:"#b9b9c2","paint-order":"stroke",stroke:"#ffffff","stroke-width":"3"},decor);
 t.textContent=rl[1];
});
(function(){
 var grad=el("radialGradient",{id:"hubg"},defs);
 el("stop",{offset:"0%","stop-color":"#a78bfa"},grad);
 el("stop",{offset:"100%","stop-color":"#7c3aed"},grad);
 el("circle",{cx:CX,cy:CY,r:64,fill:"#8b5cf6","fill-opacity":"0.12"},decor);
 el("circle",{cx:CX,cy:CY,r:50,fill:"url(#hubg)"},decor);
 var t1=el("text",{x:CX,y:CY-2,"text-anchor":"middle","font-size":"22","font-weight":"800",fill:"#ffffff"},decor); t1.textContent="Q3";
 var t2=el("text",{x:CX,y:CY+16,"text-anchor":"middle","font-size":"8.5",fill:"#ede9fe","letter-spacing":"0.5"},decor); t2.textContent="calidad como sistema";
})();
function lerp(a,b,t){return [a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];}
const edgeEls=[];
EDGES.forEach(function(e){
 var a=byId[e.from],b=byId[e.to],st=EDGE_STYLE[e.type];
 var A=[a.x,a.y],B=[b.x,b.y],C=[CX,CY];
 var c1=lerp(A,C,0.42),c2=lerp(B,C,0.42);
 function shift(P,Q,d){var dx=Q[0]-P[0],dy=Q[1]-P[1],L=Math.sqrt(dx*dx+dy*dy)||1;return [P[0]+dx/L*d,P[1]+dy/L*d];}
 var A2=shift(A,c1,a.size+2),B2=shift(B,c2,b.size+7);
 var d="M"+A2[0].toFixed(1)+","+A2[1].toFixed(1)+" C"+c1[0].toFixed(1)+","+c1[1].toFixed(1)+" "+c2[0].toFixed(1)+","+c2[1].toFixed(1)+" "+B2[0].toFixed(1)+","+B2[1].toFixed(1);
 var p=el("path",{d:d,"class":"edge",stroke:st.color,"stroke-width":"1.5","marker-end":"url(#arr-"+e.type+")"},vp);
 if(st.dash)p.setAttribute("stroke-dasharray",st.dash);
 var mx=0.125*A2[0]+0.375*c1[0]+0.375*c2[0]+0.125*B2[0];
 var my=0.125*A2[1]+0.375*c1[1]+0.375*c2[1]+0.125*B2[1];
 var lab=el("text",{x:mx,y:my-4,"text-anchor":"middle","class":"elab"},vp); lab.textContent=e.label||"";
 edgeEls.push({e:e,path:p,lab:lab});
});
// satellite connectors — faint lines from parent center to each satellite, drawn before nodes
const satLinkEls=[];
SAT_NODES.forEach(function(n){
 var parent=byId[n.parent];if(!parent)return;
 var p=el("path",{d:"M"+parent.x+","+parent.y+" L"+n.x+","+n.y,"class":"satlink",stroke:"rgba(148,163,184,0.25)","stroke-width":"1"},vp);
 satLinkEls.push({pid:parent.id,sid:n.id,path:p});
});
function hexPoints(cx,cy,r){
 var pts=[];
 for(var i=0;i<6;i++){var a=(Math.PI/180)*(60*i-90);pts.push((cx+r*Math.cos(a)).toFixed(1)+","+(cy+r*Math.sin(a)).toFixed(1));}
 return pts.join(" ");
}
function diaPoints(cx,cy,r){return (cx)+","+(cy-r)+" "+(cx+r)+","+cy+" "+cx+","+(cy+r)+" "+(cx-r)+","+cy;}
function splitLabel(s){
 if(s.length<=15)return [s];
 var mid=Math.floor(s.length/2),best=-1;
 for(var i=0;i<s.length;i++){if(s[i]===" "&&(best===-1||Math.abs(i-mid)<Math.abs(best-mid)))best=i;}
 if(best===-1)return [s];
 return [s.slice(0,best),s.slice(best+1)];
}
const nodeEls={};
NODES.forEach(function(n){
 var isSat=n.group==="issues";
 var g=el("g",{"class":isSat?"node sat":"node",tabindex:"0",role:"button"},vp);
 var core;
 if(isSat){
  var gr2=grFor(n),isDone=n.state==="done",isTopic=n.kind==="topic",ownerGold=n.owner==="mine";
  var fillColor=isDone?"#6b7280":gr2.text;
  if(isTopic){
   // new topic: diamond core + owner ring + ✨ cue ring, all diamond-shaped
   el("polygon",{points:diaPoints(n.x,n.y,n.size+6),fill:"none",stroke:"#94a3b8","stroke-width":"1","stroke-dasharray":"3 3"},g);
   if(ownerGold)el("polygon",{points:diaPoints(n.x,n.y,n.size+3),fill:"none",stroke:"#f5d90a","stroke-width":"2.5"},g);
   else el("polygon",{points:diaPoints(n.x,n.y,n.size+3),fill:"none",stroke:"#5b6472","stroke-width":"1","stroke-dasharray":"2 2"},g);
   core=el("polygon",{"class":"core",points:diaPoints(n.x,n.y,n.size),fill:fillColor,"fill-opacity":isDone?0.4:1,stroke:fillColor,"stroke-opacity":isDone?0.4:1,"stroke-width":"1"},g);
  }else{
   // linear issue: small ticket (rounded rect); owner ring folded into the rect's own stroke
   var rw=18,rh=13;
   core=el("rect",{"class":"core",x:n.x-rw/2,y:n.y-rh/2,width:rw,height:rh,rx:3,fill:fillColor,"fill-opacity":isDone?0.4:1,stroke:ownerGold?"#f5d90a":"#5b6472","stroke-width":ownerGold?2.5:1},g);
   if(!ownerGold)core.setAttribute("stroke-dasharray","2 2");
  }
  var ic2=el("text",{x:n.x,y:n.y+n.size*0.34,"text-anchor":"middle","font-size":String(Math.round(n.size*0.95)),"pointer-events":"none",opacity:isDone?0.4:1},g);
  ic2.textContent=n.icon;
  var t2=el("text",{x:n.x,y:n.y+n.size+13,"text-anchor":"middle","font-size":"9.5","class":"nlab satlab"},g); t2.textContent=n.label;
  var s2=el("text",{x:n.x,y:n.y+n.size+24,"text-anchor":"middle","font-size":"8","class":"nsub satlab"},g); s2.textContent=n.sub;
 }else{
  var gr=GROUPS[n.group];
  var isBet=n.group==="bets",isExt=n.group==="external",isPersonal=n.group==="mine",isAlly=n.group==="people";
  var isDone=n.state==="done";
  var coreR=isBet?n.size+4:n.size; // strategic bet = bigger "big rock" glyph; layout (n.size/x/y) untouched
  if(n.p0c)el("circle",{cx:n.x,cy:n.y,r:coreR+5,fill:"none",stroke:gr.text,"stroke-opacity":"0.35","stroke-width":"1.5"},g);
  if(isExt)el("circle",{cx:n.x,cy:n.y,r:coreR+3,fill:"none",stroke:gr.stroke,"stroke-width":"1.3"},g); // double outline = external entity
  if(isPersonal)el("circle",{cx:n.x,cy:n.y,r:coreR+4,fill:"none",stroke:gr.text,"stroke-opacity":"0.45","stroke-width":"1.3","stroke-dasharray":"1 3"},g); // soft glow = personal/mine
  var coreFill=isAlly?"#ffffff":gr.fill;
  var coreStroke=n.p0c?gr.text:gr.stroke;
  var coreSW=n.p0c?2.4:1.8;
  if(isBet)core=el("polygon",{"class":"core",points:hexPoints(n.x,n.y,coreR),fill:coreFill,"fill-opacity":isDone?0.45:1,stroke:coreStroke,"stroke-opacity":isDone?0.45:1,"stroke-width":coreSW},g);
  else core=el("circle",{"class":"core",cx:n.x,cy:n.y,r:coreR,fill:coreFill,"fill-opacity":isDone?0.45:1,stroke:coreStroke,"stroke-opacity":isDone?0.45:1,"stroke-width":coreSW},g);
  if(n.status==="idea")core.setAttribute("stroke-dasharray","5 3");
  if(isPersonal){var star=el("text",{x:n.x+coreR*0.66,y:n.y-coreR*0.6,"text-anchor":"middle","font-size":"9","pointer-events":"none",fill:gr.text},g);star.textContent="★";}
  var ic=el("text",{x:n.x,y:n.y+n.size*0.34,"text-anchor":"middle","font-size":String(Math.round(n.size*(isAlly?1.1:0.95))),"pointer-events":"none",opacity:isDone?0.45:1},g);
  if(isAlly)ic.setAttribute("font-weight","800");
  ic.textContent=n.icon;
  var lines=splitLabel(n.label+(n.p0c?" ★":""));
  var ly0=n.y+n.size+13;
  lines.forEach(function(ln,i){
   var t=el("text",{x:n.x,y:ly0+i*12,"text-anchor":"middle","font-size":"11","class":"nlab",opacity:isDone?0.6:1},g);
   t.textContent=ln;
  });
  var sub=el("text",{x:n.x,y:ly0+lines.length*12+1,"text-anchor":"middle","font-size":"8.5","class":"nsub",opacity:isDone?0.6:1},g);
  sub.textContent=n.sub;
 }
 g.addEventListener("click",function(ev){ev.stopPropagation();if(moved){moved=false;return;}selectNode(n.id);});
 g.addEventListener("keydown",function(ev){if(ev.key==="Enter")selectNode(n.id);});
 g.addEventListener("mouseenter",function(){state.hover=n.id;applyState();});
 g.addEventListener("mouseleave",function(){state.hover=null;applyState();});
 nodeEls[n.id]={g:g,core:core};
});
const matrixDotEls={};
// zoom & pan
var view={x:0,y:0,k:1},moved=false;
var ZMIN=0.55,ZMAX=2.6;
function applyView(){vp.setAttribute("transform","translate("+view.x+" "+view.y+") scale("+view.k+")");}
function svgPt(cx,cy){var r=svg.getBoundingClientRect();var vb=1000;var scale=Math.min(r.width,r.height)/vb;var ox=(r.width-vb*scale)/2,oy=(r.height-vb*scale)/2;return {x:(cx-r.left-ox)/scale,y:(cy-r.top-oy)/scale};}
function zoomAt(px,py,k2){
 k2=Math.min(ZMAX,Math.max(ZMIN,k2));
 view.x=px-(px-view.x)*(k2/view.k); view.y=py-(py-view.y)*(k2/view.k); view.k=k2;
 applyView();
}
function resetView(){view={x:0,y:0,k:1};applyView();}
function fitView(){
 var vs2=visSet();
 var ids=NODES.filter(function(n){return passesFilter(n)&&(!vs2||vs2.has(n.id));}).map(function(n){return n.id;});
 if(!ids.length){resetView();return;}
 var minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
 ids.forEach(function(id){var n=byId[id],r=(n.size||9)+16;
  if(n.x-r<minX)minX=n.x-r; if(n.x+r>maxX)maxX=n.x+r;
  if(n.y-r<minY)minY=n.y-r; if(n.y+r>maxY)maxY=n.y+r;
 });
 var w=(maxX-minX)*1.16,h=(maxY-minY)*1.16;
 var cx=(minX+maxX)/2,cy=(minY+maxY)/2;
 var k=Math.min(ZMAX,Math.max(ZMIN,1000/Math.max(w,h,1)));
 view.k=k; view.x=500-cx*k; view.y=500-cy*k;
 applyView();
}
svg.addEventListener("wheel",function(ev){
 ev.preventDefault();
 var pt=svgPt(ev.clientX,ev.clientY);
 zoomAt(pt.x,pt.y,view.k*(ev.deltaY<0?1.12:0.9));
},{passive:false});
var drag=null;
svg.addEventListener("pointerdown",function(ev){
 if(marqueeArmed||ev.shiftKey){startMarquee(svg,ev,svgPt);return;}
 drag={x:ev.clientX,y:ev.clientY,vx:view.x,vy:view.y,id:ev.pointerId,captured:false};moved=false;
});
svg.addEventListener("pointermove",function(ev){
 if(marqueeState&&marqueeState.svgEl===svg){updateMarqueeVisual(ev);return;}
 if(!drag)return;
 var r=svg.getBoundingClientRect(),s=1000/Math.min(r.width,r.height);
 var dx=(ev.clientX-drag.x)*s,dy=(ev.clientY-drag.y)*s;
 if(Math.abs(dx)+Math.abs(dy)>3&&!drag.captured){
  moved=true;drag.captured=true;svg.classList.add("panning");
  try{svg.setPointerCapture(drag.id);}catch(_e){}
 }
 if(drag.captured){view.x=drag.vx+dx; view.y=drag.vy+dy; applyView();}
});
svg.addEventListener("pointerup",function(ev){
 if(marqueeState&&marqueeState.svgEl===svg){endMarquee(ev);return;}
 drag=null;svg.classList.remove("panning");
});
svg.addEventListener("dblclick",function(){resetView();});
svg.addEventListener("click",function(){if(moved){moved=false;return;}clearSelection();});
var stageEl=document.querySelector(".stage");
function activeView(){return mx.style.display==="block"?"matrix":"orbit";}
function toggleMax(){stageEl.classList.toggle("maximized");requestAnimationFrame(function(){if(activeView()==="matrix")mFitView();else fitView();});}
document.getElementById("btnZoomOut").addEventListener("click",function(){if(activeView()==="matrix")mZoomAt(550,280,mview.k*0.8);else zoomAt(500,500,view.k*0.8);});
document.getElementById("btnZoomIn").addEventListener("click",function(){if(activeView()==="matrix")mZoomAt(550,280,mview.k*1.25);else zoomAt(500,500,view.k*1.25);});
document.getElementById("btnFit").addEventListener("click",function(){if(activeView()==="matrix")mFitView();else fitView();});
document.getElementById("btnReset").addEventListener("click",function(){if(activeView()==="matrix")mResetView();else resetView();});
document.getElementById("btnMax").addEventListener("click",toggleMax);
var btnMarquee=document.getElementById("btnMarquee");
btnMarquee.addEventListener("click",function(){setMarqueeArmed(!marqueeArmed);});
document.addEventListener("keydown",function(ev){
 if(ev.key==="Escape"){
  if(marqueeArmed||marqueeState){cancelMarquee();}
  else if(stageEl.classList.contains("maximized")){toggleMax();}
  else if(qInput.value){clearSearch();}
  else{clearSelection();}
 }
 if((ev.key==="/"||((ev.metaKey||ev.ctrlKey)&&ev.key.toLowerCase()==="k"))&&document.activeElement!==qInput){ev.preventDefault();qInput.focus();}
});
// lenses
const lensBar=document.getElementById("lensBar"),lensNote=document.getElementById("lensNote");
LENSES.forEach(function(L){
 var b=document.createElement("button");b.className="lens"+(L.id===state.lens?" on":"");b.textContent=L.label;
 b.addEventListener("click",function(){state.lens=L.id;document.querySelectorAll(".lens").forEach(function(x){x.classList.remove("on");});b.classList.add("on");lensNote.textContent=L.note;applyState();});
 lensBar.appendChild(b);
});
lensNote.textContent=LENSES[0].note;
// legend
(function(){var lg=document.getElementById("legendContent");var html="";
 Object.keys(GROUPS).forEach(function(k){var g=GROUPS[k];html+="<span><span class='sw' style='background:"+g.fill+";border-color:"+g.stroke+"'></span>"+g.label+"</span>";});
 html+="<span><span class='ln' style='border-color:#9aa3af'></span>depende</span>";
 html+="<span><span class='ln' style='border-color:#16a34a'></span>alimenta</span>";
 html+="<span><span class='ln dash' style='border-color:#dc2626'></span>riesgo</span>";
 html+="<span><span class='ln dot' style='border-color:#8b5cf6'></span>valida</span>";
 html+="<span>★ P0 consenso · ⏰ fecha</span>";
 html+="<span>forma: ● tema · ⬢ apuesta · ▢ issue · ◆ tema nuevo · 👤 aliado · ◎ externo · ★ personal</span>";
 html+="<span>◯ anillo dorado = mío · borde punteado = de otros · atenuado = completado (done)</span>";
 html+="<span>▦ Matriz: X = complejidad (1-5) · Y = valor para ti (1-5) · color = área · cuadrantes: ↖ quick wins · ↗ apuestas grandes · ↙ relleno · ↘ cuidado (alto costo, bajo valor)</span>";
 lg.innerHTML=html;})();
var legendPanel=document.getElementById("legend"),legendChip=document.getElementById("legendChip"),legendClose=document.getElementById("legendClose");
function setLegendOpen(o){legendPanel.classList.toggle("open",o);legendChip.classList.toggle("on",o);legendChip.textContent=(o?"▾":"▸")+" Leyenda";}
legendChip.addEventListener("click",function(){setLegendOpen(!legendPanel.classList.contains("open"));});
legendClose.addEventListener("click",function(){setLegendOpen(false);});
setLegendOpen(false);
// filters (group toggles + kind toggles + hide-done + period), combine with lens inside applyState()
var hiddenGroups=new Set(),hiddenPeriods=new Set(),filterState={issues:true,topics:true,done:true};
function periodOf(n){
 if(n.group==="issues"){var p=(n.parent&&byId[n.parent])?byId[n.parent]:null;return p?(p.period||"q3"):"q3";}
 return n.period||"q3";
}
function passesFilter(n){
 if(!n)return true;
 if(hiddenPeriods.has(periodOf(n)))return false;
 if(n.group==="issues"){
  var pg=(n.parent&&byId[n.parent])?byId[n.parent].group:null;
  if(pg&&hiddenGroups.has(pg))return false;
  if(n.kind==="topic"){if(!filterState.topics)return false;}else{if(!filterState.issues)return false;}
  if(!filterState.done&&n.state==="done")return false;
  return true;
 }
 if(hiddenGroups.has(n.group))return false;
 if(!filterState.done&&n.state==="done")return false;
 return true;
}
(function(){
 var fc=document.getElementById("filtersContent"),html="";
 html+="<button class='fmini freset' data-freset='panel' type='button'>↺ Restablecer filtros</button>";
 html+="<div class='fsec'>Grupos <button class='fmini' data-fall='all' type='button'>todos</button><button class='fmini' data-fall='invert' type='button'>invertir</button></div>";
 Object.keys(GROUPS).forEach(function(k){var g=GROUPS[k];
  html+="<label class='fchk'><input type='checkbox' data-fg='"+k+"' checked><span style='display:inline-block;width:10px;height:10px;border-radius:3px;border:1px solid "+g.stroke+";background:"+g.fill+"'></span>"+g.label+"<button class='fmini fsolo' data-fsolo='"+k+"' type='button' title='mostrar solo este grupo'>solo</button></label>";
 });
 html+="<div class='fsec'>Satélites</div>";
 html+="<label class='fchk'><input type='checkbox' data-fk='issues' checked>📋 Issues</label>";
 html+="<label class='fchk'><input type='checkbox' data-fk='topics' checked>✨ Temas nuevos</label>";
 html+="<label class='fchk'><input type='checkbox' data-fk='done' checked>✅ Completadas (done)</label>";
 html+="<div class='fsec'>Periodo</div>";
 html+="<label class='fchk'><input type='checkbox' data-fperiod='q3' checked>Q3 2026</label>";
 html+="<label class='fchk'><input type='checkbox' data-fperiod='h1' checked>H1 (shipped)</label>";
 html+="<p class='fhint'>Un nodo se muestra si todo lo suyo está marcado: su grupo + su periodo · una issue requiere además el grupo/periodo de su tema padre.</p>";
 fc.innerHTML=html;
 function syncGroupChecks(){fc.querySelectorAll("[data-fg]").forEach(function(x){x.checked=!hiddenGroups.has(x.getAttribute("data-fg"));});}
 fc.querySelectorAll("[data-fg]").forEach(function(x){x.addEventListener("change",function(){
  var k=x.getAttribute("data-fg");if(x.checked)hiddenGroups.delete(k);else hiddenGroups.add(k);applyState();
 });});
 fc.querySelectorAll("[data-fk]").forEach(function(x){x.addEventListener("change",function(){
  filterState[x.getAttribute("data-fk")]=x.checked;applyState();
 });});
 fc.querySelectorAll("[data-fperiod]").forEach(function(x){x.addEventListener("change",function(){
  var k=x.getAttribute("data-fperiod");if(x.checked)hiddenPeriods.delete(k);else hiddenPeriods.add(k);applyState();
 });});
 fc.querySelectorAll("[data-fsolo]").forEach(function(x){x.addEventListener("click",function(ev){
  ev.preventDefault();ev.stopPropagation();
  var k=x.getAttribute("data-fsolo");
  hiddenGroups=new Set(Object.keys(GROUPS).filter(function(g){return g!==k;}));
  syncGroupChecks();applyState();
 });});
 fc.querySelectorAll("[data-fall]").forEach(function(x){x.addEventListener("click",function(){
  var mode=x.getAttribute("data-fall");
  if(mode==="all")hiddenGroups=new Set();
  else{var next=new Set();Object.keys(GROUPS).forEach(function(g){if(!hiddenGroups.has(g))next.add(g);});hiddenGroups=next;}
  syncGroupChecks();applyState();
 });});
 fc.querySelectorAll("[data-freset]").forEach(function(x){x.addEventListener("click",function(){resetFilters();});});
})();
function resetFilters(){
 hiddenGroups=new Set();hiddenPeriods=new Set();filterState={issues:true,topics:true,done:true};
 var fc=document.getElementById("filtersContent");
 fc.querySelectorAll("[data-fg]").forEach(function(x){x.checked=true;});
 fc.querySelectorAll("[data-fk]").forEach(function(x){x.checked=true;});
 fc.querySelectorAll("[data-fperiod]").forEach(function(x){x.checked=true;});
 applyState();
}
document.getElementById("filtersEmptyReset").addEventListener("click",resetFilters);
var filtersPanel=document.getElementById("filters"),filtersChip=document.getElementById("filtersChip"),filtersClose=document.getElementById("filtersClose");
function setFiltersOpen(o){filtersPanel.classList.toggle("open",o);filtersChip.classList.toggle("on",o);filtersChip.textContent=(o?"▾":"▸")+" Filtros";}
filtersChip.addEventListener("click",function(){setFiltersOpen(!filtersPanel.classList.contains("open"));});
filtersClose.addEventListener("click",function(){setFiltersOpen(false);});
setFiltersOpen(false);
// search
const qInput=document.getElementById("q"),qClear=document.getElementById("qClear"),qResults=document.getElementById("qResults");
function norm(s){return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g,"");}
const INDEX=NODES.map(function(n){
 var txt=(n.group==="issues")?[n.label,n.sub].join(" "):[n.label,n.sub,n.owner,n.prio,n.status,GROUPS[n.group].label,(n.people||[]).map(function(p){return p.n+" "+p.r;}).join(" "),n.detail.replace(/<[^>]+>/g," "),(n.entry||"").replace(/<[^>]+>/g," ")].join(" ");
 return {id:n.id,txt:norm(txt)};
});
function truncate(s,n){return s.length>n?s.slice(0,n-1)+"…":s;}
const MEM_INDEX=(function(){
 var arr=[];
 memCats().forEach(function(c){(c.notes||[]).forEach(function(nt){
  arr.push({noteId:nt.id,catId:c.id,catLabel:c.label,snippet:truncate(nt.t,64),txt:norm([nt.t,c.label].join(" "))});
 });});
 return arr;
})();
function runSearch(){
 var q=norm(qInput.value.trim());
 qClear.style.display=qInput.value?"block":"none";
 if(!q){state.searchSet=null;qResults.style.display="none";applyState();return;}
 var toks=q.split(/\s+/);
 var hits=INDEX.filter(function(ix){return toks.every(function(t){return ix.txt.indexOf(t)>=0;});}).map(function(ix){return byId[ix.id];});
 state.searchSet=new Set(hits.map(function(n){return n.id;}));
 var memHits=MEM_INDEX.filter(function(ix){return toks.every(function(t){return ix.txt.indexOf(t)>=0;});});
 var h="",total=hits.length+memHits.length,shown=0;
 if(!total){h="<div class='qempty'>Sin resultados para «"+qInput.value.replace(/</g,"&lt;")+"»</div>";}
 else{
  var memReserve=Math.min(memHits.length,3);
  hits.slice(0,Math.max(0,9-memReserve)).forEach(function(n){
   var gr=grFor(n),gtag=(n.group==="issues")?(n.state==="done"?"done":"live"):gr.label;
   h+="<div class='qr"+(shown===0?" hot":"")+"' data-nav='"+n.id+"'><span>"+n.icon+"</span><b>"+n.label+"</b><span class='gtag' style='background:"+gr.fill+";color:"+gr.text+"'>"+gtag+"</span></div>";
   shown++;
  });
  memHits.slice(0,Math.max(0,9-shown)).forEach(function(ix){
   h+="<div class='qr"+(shown===0?" hot":"")+"' data-navmem='"+ix.noteId+"|"+ix.catId+"'><span>🧠</span><b>"+ix.snippet+"</b><span class='gtag' style='background:#ede9fe;color:#6d28d9'>"+ix.catLabel+"</span></div>";
   shown++;
  });
  if(total>shown)h+="<div class='qempty'>+"+(total-shown)+" más — refiná la búsqueda</div>";
 }
 qResults.innerHTML=h;qResults.style.display="block";
 qResults.querySelectorAll("[data-nav]").forEach(function(x){x.addEventListener("click",function(){var id=x.getAttribute("data-nav");clearSearch();selectNode(id);});});
 qResults.querySelectorAll("[data-navmem]").forEach(function(x){x.addEventListener("click",function(){
  var parts=x.getAttribute("data-navmem").split("|");clearSearch();goToMemoryNote(parts[0],parts[1]);
 });});
 applyState();
}
function clearSearch(){qInput.value="";state.searchSet=null;qResults.style.display="none";qClear.style.display="none";applyState();}
qInput.addEventListener("input",runSearch);
qInput.addEventListener("keydown",function(ev){
 if(ev.key==="Enter"){var first=qResults.querySelector("[data-nav]");if(first){var id=first.getAttribute("data-nav");clearSearch();selectNode(id);qInput.blur();}}
 if(ev.key==="Escape"){clearSearch();qInput.blur();}
});
qClear.addEventListener("click",clearSearch);
document.addEventListener("click",function(ev){if(!ev.target.closest(".tb-search"))qResults.style.display="none";});
// state machine
const clearBtn=document.getElementById("clearSel");
clearBtn.addEventListener("click",clearSelection);
function clearSelection(){state.selected=null;applyState();renderPanel();}
function visSet(){
 var s=null;
 var L=null;for(var i=0;i<LENSES.length;i++){if(LENSES[i].id===state.lens)L=LENSES[i];}
 if(L&&L.nodes!=="*"){s=new Set(L.nodes);NODES.forEach(function(n){if(satParent[n.id]&&s.has(satParent[n.id]))s.add(n.id);});}
 if(state.searchSet){
  if(!s)s=new Set(state.searchSet);
  else{var s2=new Set();s.forEach(function(id){if(state.searchSet.has(id))s2.add(id);});s=s2;}
 }
 return s;
}
function applyState(){
 var filtersEmptyEl=document.getElementById("filtersEmpty");
 filtersEmptyEl.style.display=NODES.some(passesFilter)?"none":"flex";
 if(state.selected&&RIT_BY[state.selected]){
  var R=RIT_BY[state.selected],rs=new Set(R.nodes);
  NODES.forEach(function(n){var o=rs.has(n.id)?1:0;if(!passesFilter(n))o=0;nodeEls[n.id].g.style.opacity=o;nodeEls[n.id].g.style.pointerEvents=o?"auto":"none";nodeEls[n.id].g.classList.remove("sel");});
  edgeEls.forEach(function(E){var v=rs.has(E.e.from)&&rs.has(E.e.to)&&passesFilter(byId[E.e.from])&&passesFilter(byId[E.e.to]);E.path.style.opacity=v?0.9:0;E.path.setAttribute("stroke-width",v?2.2:1.5);E.lab.classList.toggle("show",v);});
  satLinkEls.forEach(function(L){L.path.style.opacity=0;});
  decor.style.opacity=0.22;clearBtn.style.display="block";styleMatrix();return;
 }
 var vs=visSet();
 var inVis=function(id){return !vs||vs.has(id);};
 var fOK=function(id){return passesFilter(byId[id]);};
 var focus=state.selected||state.hover;
 if(focus&&(!inVis(focus)||!fOK(focus)))focus=null;
 var neigh=null;
 if(focus){
  neigh=new Set([focus]);
  EDGES.forEach(function(e){if(!inVis(e.from)||!inVis(e.to)||!fOK(e.from)||!fOK(e.to))return;if(e.from===focus)neigh.add(e.to);if(e.to===focus)neigh.add(e.from);});
  if(satsByParent[focus])satsByParent[focus].forEach(function(s){if(fOK(s.id))neigh.add(s.id);});
  if(satParent[focus]&&fOK(satParent[focus]))neigh.add(satParent[focus]);
 }
 var hideMode=!!state.selected;
 NODES.forEach(function(n){
  var o;
  if(hideMode){o=(neigh&&neigh.has(n.id))?1:0;}
  else if(focus){o=inVis(n.id)?((neigh&&neigh.has(n.id))?1:0.22):0.08;}
  else{o=inVis(n.id)?1:(state.searchSet?0.05:0.12);}
  if(!fOK(n.id))o=0;
  nodeEls[n.id].g.style.opacity=o;
  nodeEls[n.id].g.style.pointerEvents=(o===0)?"none":"auto";
  if(state.selected===n.id)nodeEls[n.id].g.classList.add("sel");else nodeEls[n.id].g.classList.remove("sel");
 });
 edgeEls.forEach(function(E){
  var vis=inVis(E.e.from)&&inVis(E.e.to);
  var o,w=1.5,show=false;
  if(hideMode){
   var touch=(E.e.from===state.selected||E.e.to===state.selected);
   o=touch&&vis?0.95:0; w=touch?2.5:1.5; show=touch&&vis;
  }else if(focus){
   var t2=(E.e.from===focus||E.e.to===focus);
   o=t2&&vis?0.95:(vis?0.08:0.03); w=t2?2.5:1.5; show=t2&&vis;
  }else{
   o=vis?(vs?0.6:0.22):0.03;
  }
  if(!fOK(E.e.from)||!fOK(E.e.to)){o=0;show=false;}
  E.path.style.opacity=o;E.path.setAttribute("stroke-width",w);
  E.lab.classList.toggle("show",show);
 });
 satLinkEls.forEach(function(L){
  var vis=inVis(L.pid)&&inVis(L.sid);
  var o;
  if(hideMode){o=(L.pid===state.selected||L.sid===state.selected)&&vis?1:0;}
  else if(focus){o=(L.pid===focus||L.sid===focus)?(vis?1:0.15):(vis?0.4:0.05);}
  else{o=vis?1:0.15;}
  if(!fOK(L.pid)||!fOK(L.sid))o=0;
  L.path.style.opacity=o;
 });
 decor.style.opacity=hideMode?0.22:1;
 clearBtn.style.display=hideMode?"block":"none";
 styleMatrix();
}
function styleMatrix(){
 var vs=visSet();
 var inVis=function(id){return !vs||vs.has(id);};
 var selActive=!!state.selected;
 Object.keys(matrixDotEls).forEach(function(id){
  var n=byId[id],D=matrixDotEls[id],o,isSel=false;
  if(!passesFilter(n)){o=0;}
  else if(selActive){
   if(id===state.selected){o=1;isSel=true;}
   else{o=0.35;}
  }else{
   o=inVis(id)?1:0.12;
  }
  D.g.style.opacity=o;
  D.g.style.pointerEvents=(o===0)?"none":"auto";
  D.g.classList.toggle("sel",isSel);
  D.c.setAttribute("r",isSel?"10":"7");
  D.c.setAttribute("stroke-width",isSel?"2.6":"1.6");
  if(isSel)D.lb.setAttribute("font-weight","700");else D.lb.removeAttribute("font-weight");
 });
}
// panel tabs
document.querySelectorAll(".ptabs button[data-tab]").forEach(function(b){
 b.addEventListener("click",function(){switchTab(b.getAttribute("data-tab"));});
});
document.getElementById("pExpand").addEventListener("click",function(){
 var p=document.getElementById("panel");
 p.classList.toggle("wide");
 this.textContent=p.classList.contains("wide")?"⤡":"⤢";
});
function selectRitual(id){state.selected=id;switchTab("det");applyState();renderPanel();}
document.getElementById("tab-aliados").addEventListener("click",function(ev){
 var t=ev.target.closest("[data-nav]");
 if(t)selectNode(t.getAttribute("data-nav"));
});
document.getElementById("tab-ritmo").addEventListener("click",function(ev){
 var t=ev.target.closest("[data-rit]");
 if(t)selectRitual(t.getAttribute("data-rit"));
});
document.getElementById("tab-proyectos").addEventListener("click",function(ev){
 if(ev.target.closest("a"))return;
 var t=ev.target.closest("[data-nav]");
 if(t)selectNode(t.getAttribute("data-nav"));
});
document.getElementById("copyPrompt").addEventListener("click",function(){
 var btn=this,txt=document.getElementById("promptText").textContent;
 function done(){btn.textContent="✓ copiado";setTimeout(function(){btn.textContent="📋 Copy prompt";},1600);}
 if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(txt).then(done,function(){fallback();});}
 else{fallback();}
 function fallback(){var ta=document.createElement("textarea");ta.value=txt;ta.style.position="fixed";ta.style.opacity="0";document.body.appendChild(ta);ta.focus();ta.select();var s=false;try{s=document.execCommand("copy");}catch(e){}document.body.removeChild(ta);if(s){done();}else{btn.textContent="⚠️ copia manual";setTimeout(function(){btn.textContent="📋 Copy prompt";},2600);}}
});
function switchTab(id){
 document.querySelectorAll(".ptabs button").forEach(function(x){x.classList.toggle("on",x.getAttribute("data-tab")===id);});
 document.querySelectorAll(".ptab").forEach(function(x){x.classList.toggle("on",x.id==="tab-"+id);});
}
// panel detail
const detBody=document.getElementById("detBody");
function chipHtml(txt,bg,fg){return "<span class='chip' style='background:"+(bg||"var(--surface)")+";color:"+(fg||"#4b4b4f")+";border-color:transparent'>"+txt+"</span>";}
function prioChip(p){
 if(p.indexOf("P0")===0)return chipHtml(p,"#fee2e2","#b91c1c");
 if(p.indexOf("P1")===0)return chipHtml(p,"#fef3c7","#b45309");
 if(p.indexOf("P2")===0)return chipHtml(p,"#f4f4f5","#52525b");
 if(p==="propuesta")return chipHtml("propuesta","#ede9fe","#6d28d9");
 return chipHtml(p,"#f4f4f5","#52525b");
}
function initials(nm){var p=nm.split(/\s+/);return (p[0][0]+(p[1]?p[1][0]:"")).toUpperCase();}
function bitacoraHtml(id){
 var items=(JOURNAL||[]).filter(function(D){return D.node===id;});
 if(!items.length)return "";
 items=items.slice().sort(function(a,b){return a.date<b.date?1:(a.date>b.date?-1:0);});
 var h="<div class='sect'><div class='t'>🗄️ Bitácora</div>";
 items.forEach(function(D){h+="<p class='hint' style='margin:0 0 6px'>"+fmtDayLabel(parseLocalDate(D.date))+" · "+D.i+" "+D.t+"</p>";});
 h+="</div>";
 return h;
}
function memCats(){return (MEMORY&&MEMORY.cats)?MEMORY.cats:[];}
function memNoteSort(a,b){var pa=a.pinned?1:0,pb=b.pinned?1:0;if(pa!==pb)return pb-pa;return a.date_upd<b.date_upd?1:(a.date_upd>b.date_upd?-1:0);}
function memoriaHtml(id){
 var hits=[];
 memCats().forEach(function(c){(c.notes||[]).forEach(function(nt){if((nt.refs||[]).indexOf(id)>=0)hits.push({note:nt,cat:c});});});
 if(!hits.length)return "";
 hits.sort(function(a,b){return memNoteSort(a.note,b.note);});
 var h="<div class='sect'><div class='t'>🧠 Memoria</div>";
 hits.forEach(function(hit){h+="<p class='hint' style='margin:0 0 6px;color:#3f3f43'>"+(hit.note.pinned?"📌 ":"")+hit.cat.icon+" "+hit.note.t+" <span style='color:var(--muted-fg)'>· "+hit.note.date_upd+"</span></p>";});
 h+="</div>";
 return h;
}
function bestMemNoteFor(id){
 var hits=[];
 memCats().forEach(function(c){(c.notes||[]).forEach(function(nt){if((nt.refs||[]).indexOf(id)>=0)hits.push({note:nt,cat:c});});});
 if(!hits.length)return null;
 hits.sort(function(a,b){return memNoteSort(a.note,b.note);});
 return hits[0];
}
function memNotesForRefs(ids){
 var set={};ids.forEach(function(id){set[id]=true;});
 var hits=[],seen={};
 memCats().forEach(function(c){(c.notes||[]).forEach(function(nt){
  if(seen[nt.id])return;
  var refs=nt.refs||[];
  for(var i=0;i<refs.length;i++){if(set[refs[i]]){hits.push({note:nt,cat:c});seen[nt.id]=true;break;}}
 });});
 hits.sort(function(a,b){return memNoteSort(a.note,b.note);});
 return hits;
}
function renderPanel(){
 if(!state.selected){
  var top=THEME_NODES.slice().sort(function(a,b){return (deg[b.id]||0)-(deg[a.id]||0);}).slice(0,6);
  var h="<h3>Tu guía del Q3</h3><p class='hint'>Empieza el día en <b>Hoy</b> (checklist del día, deadlines, foco y plantillas); <b>Ritmo</b> y <b>Proyectos</b> traen el porqué de cada cosa, y <b>Aliados</b> la jugada por persona y usa el grafo para el contexto: click en un nodo deja solo lo asociado y su detalle aparece acá (personas, links a threads/docs, insights). <kbd>/</kbd> o <kbd>⌘K</kbd> para buscar; <kbd>Esc</kbd> o «✕ mostrar todo» para volver.</p><div class='sect'><div class='t'>Los más conectados</div>";
  top.forEach(function(n){h+="<div class='conn' data-nav='"+n.id+"'><span class='dot' style='background:"+GROUPS[n.group].stroke+"'></span><span>"+n.icon+" <b>"+n.label+"</b></span><span class='lbl'>"+(deg[n.id]||0)+" conexiones</span></div>";});
  h+="</div><div class='sect'><div class='t'>Empieza por</div><div class='insbtns'>";top.slice(0,4).forEach(function(n){h+="<button class='insbtn' data-nav='"+n.id+"'>"+n.icon+" "+n.label+"</button>";});h+="</div></div>";
  detBody.innerHTML=h;
 }else if(RIT_BY[state.selected]){
  var r=RIT_BY[state.selected];
  var h="<h3>"+r.icon+" "+r.label+"</h3><div class='chips'>"+chipHtml("recurrente","#ecfeff","#155e75")+chipHtml(r.cad,"#dcfce7","#15803d")+chipHtml("rol: tech lead","#f5f3ff","#5b21b6")+"</div>";
  h+="<div class='pbody'>"+r.guide+"</div>";
  h+="<div class='excel'><b>🌟 Jugadas de excelencia — cómo te ven los demás:</b>"+r.excel+"</div>";
  if(r.nodes.length){h+="<div class='sect'><div class='t'>En el grafo ("+r.nodes.length+" nodos conectados)</div>";
   r.nodes.forEach(function(id){var o=byId[id];if(!o)return;h+="<div class='conn' data-nav='"+id+"'><span class='dot' style='background:"+GROUPS[o.group].stroke+"'></span><span>"+o.icon+" <b>"+o.label+"</b></span></div>";});
   h+="</div>";}
  var ritRecall=memNotesForRefs(r.nodes);
  if(ritRecall.length){h+="<div class='sect'><div class='t'>🧠 Recuerda</div>";
   ritRecall.slice(0,3).forEach(function(hit){h+="<p class='hint' style='margin:0 0 6px;cursor:pointer' data-navmem='"+hit.note.id+"|"+hit.cat.id+"'>"+hit.cat.icon+" "+hit.note.t+"</p>";});
   h+="</div>";}
  detBody.innerHTML=h;
 }else if(byId[state.selected]&&byId[state.selected].group==="issues"){
  var n=byId[state.selected],parent=byId[n.parent],gr=grFor(n),isDone=n.state==="done",isMine=n.owner==="mine";
  var h="<h3>"+n.icon+" "+n.label+"</h3><div class='chips'>";
  if(parent)h+=chipHtml(parent.label,gr.fill,gr.text);
  h+=chipHtml(isDone?"Done":"Live",isDone?"#f4f4f5":"#dcfce7",isDone?"#52525b":"#15803d");
  h+=chipHtml(isMine?"Mío":"De otros",isMine?"#fef9c3":"#f4f4f5",isMine?"#a16207":"#52525b");
  h+="</div><div class='pbody'>"+n.sub+"</div>";
  if(n.url)h+="<div class='sect'><div class='lnks'><a class='lnk' href='"+n.url+"' target='_blank' rel='noopener'><span class='ic'>🔗</span><span>Abrir en Linear</span><span class='u'>abrir ↗</span></a></div></div>";
  if(parent)h+="<div class='sect'><div class='t'>Tema</div><div class='conn' data-nav='"+parent.id+"'><span class='dot' style='background:"+GROUPS[parent.group].stroke+"'></span><span>"+parent.icon+" <b>"+parent.label+"</b></span></div></div>";
  h+=bitacoraHtml(n.id);
  h+=memoriaHtml(n.id);
  detBody.innerHTML=h;
 }else{
  var n=byId[state.selected],gr=GROUPS[n.group],ss=STATUS_STYLE[n.status]||["#f4f4f5","#52525b"];
  var h="<h3>"+n.icon+" "+n.label+(n.p0c?" ★":"")+"</h3><div class='chips'>";
  h+=chipHtml(gr.label,gr.fill,gr.text);
  h+=prioChip(n.prio);
  var vv=n.val||n.prioScore;
  if(vv)h+=chipHtml("Val "+vv+"/5",vv>=4?"#dcfce7":(vv===3?"#fef3c7":"#f4f4f5"),vv>=4?"#15803d":(vv===3?"#b45309":"#52525b"));
  h+=chipHtml("Cx "+n.cx+"/5","#f4f4f5","#52525b");
  h+=chipHtml(n.owner,"#f4f4f5","#52525b");
  h+=chipHtml(n.status,ss[0],ss[1]);
  if(n.mine>=2)h+=chipHtml("⚡ palanca "+"●".repeat(n.mine)+"○".repeat(3-n.mine),"#ecfeff","#155e75");
  h+="</div>";
  if(n.matrix)h+="<button class='hist-more' data-gomatrix='"+n.id+"' style='display:inline-block;margin:-6px 0 10px;font-size:11.5px'>▦ ver en matriz</button>";
  h+="<div class='pbody'>"+n.detail+"</div>";
  if(n.entry)h+="<div class='entry'><b>⚡ Cómo entro yo:</b> "+n.entry+"</div>";
  if(n.people&&n.people.length){h+="<div class='sect'><div class='t'>Personas</div><div class='ppl'>";
   n.people.forEach(function(p){h+="<span class='pchip'><i>"+initials(p.n)+"</i>"+p.n+" <small>· "+p.r+"</small></span>";});
   h+="</div></div>";}
  if(n.links&&n.links.length){h+="<div class='sect'><div class='t'>Threads y documentos</div><div class='lnks'>";
   n.links.forEach(function(L){
    if(L.u){h+="<a class='lnk' href='"+L.u+"' target='_blank' rel='noopener'><span class='ic'>"+L.i+"</span><span>"+L.t+"</span><span class='u'>abrir ↗</span></a>";}
    else{h+="<div class='lnk'><span class='ic'>"+L.i+"</span><span style='font-family:var(--mono);font-size:11px'>"+L.t+"</span><span class='u'>local</span></div>";}
   });
   h+="</div></div>";}
  if(n.ins&&n.ins.length){h+="<div class='sect'><div class='t'>Insights relacionados</div><div class='insbtns'>";
   n.ins.forEach(function(i){h+="<button class='insbtn' data-ins='"+i+"'>Insight "+["①","②","③","④","⑤","⑥","⑦","⑧","⑨","⑩"][i-1]+"</button>";});
   h+="</div></div>";}
  var conns=EDGES.filter(function(e){return e.from===n.id||e.to===n.id;});
  if(conns.length){h+="<div class='sect'><div class='t'>Conexiones ("+conns.length+")</div>";
   conns.forEach(function(e){var out=e.from===n.id,other=byId[out?e.to:e.from],st=EDGE_STYLE[e.type];
    h+="<div class='conn' data-nav='"+other.id+"'><span class='dot' style='background:"+st.color+"'></span><span>"+(out?"→":"←")+" "+other.icon+" <b>"+other.label+"</b></span><span class='lbl'>"+e.label+"</span></div>";});
   h+="</div>";}
  h+=bitacoraHtml(n.id);
  h+=memoriaHtml(n.id);
  detBody.innerHTML=h;
 }
 detBody.querySelectorAll("[data-nav]").forEach(function(x){x.addEventListener("click",function(){selectNode(x.getAttribute("data-nav"));});});
 detBody.querySelectorAll("[data-navmem]").forEach(function(x){x.addEventListener("click",function(){
  var parts=x.getAttribute("data-navmem").split("|");goToMemoryNote(parts[0],parts[1]);
 });});
 detBody.querySelectorAll("[data-ins]").forEach(function(x){x.addEventListener("click",function(){
  switchTab("ins");
  var c=document.getElementById("ins-"+x.getAttribute("data-ins"));
  if(c){c.scrollIntoView({behavior:"smooth",block:"center"});c.classList.remove("flash");void c.offsetWidth;c.classList.add("flash");}
 });});
 detBody.querySelectorAll("[data-gomatrix]").forEach(function(x){x.addEventListener("click",function(){
  setView("matrix");
  requestAnimationFrame(function(){pulseMatrixDot(x.getAttribute("data-gomatrix"));});
 });});
}
function selectNode(id){state.selected=id;switchTab("det");applyState();renderPanel();}
// view toggle
const vOrbit=document.getElementById("vOrbit"),vMatrix=document.getElementById("vMatrix"),vPanel=document.getElementById("vPanel"),mx=document.getElementById("matrix");
var mainEl=document.querySelector(".main");
function setView(which){
 vOrbit.classList.toggle("on",which==="orbit");
 vMatrix.classList.toggle("on",which==="matrix");
 vPanel.classList.toggle("on",which==="panel");
 mainEl.classList.toggle("panelfull",which==="panel");
 if(which!=="panel"){svg.style.display=(which==="orbit")?"block":"none";mx.style.display=(which==="matrix")?"block":"none";}
}
vOrbit.addEventListener("click",function(){setView("orbit");});
vMatrix.addEventListener("click",function(){setView("matrix");});
vPanel.addEventListener("click",function(){setView("panel");});
// matrix
var ms=mx;
var X0=80,X1=850,Y0=40,Y1=470;
function sx(v){return X0+(v-0.5)/5*(X1-X0);}
function sy(v){return Y1-(v-0.5)/5*(Y1-Y0);}
const mvp=el("g",{id:"mvp"},ms);
var quads=[["↖ QUICK WINS — hazlas ya",(X0+sx(3))/2,(sy(3)+Y0)/2,"#16a34a"],["↗ APUESTAS GRANDES — diseña y hazlas visibles",(sx(3)+X1)/2,(sy(3)+Y0)/2,"#8b5cf6"],["↙ RELLENO — solo en huecos",(X0+sx(3))/2,(Y1+sy(3))/2,"#9ca3af"],["↘ CUIDADO — alto costo, bajo valor",(sx(3)+X1)/2,(Y1+sy(3))/2,"#dc2626"]];
quads.forEach(function(q){var t=el("text",{x:q[1],y:q[2],"text-anchor":"middle","class":"quad",fill:q[3],opacity:"0.12"},mvp);t.textContent=q[0];});
for(var i=1;i<=5;i++){
 el("line",{x1:sx(i),x2:sx(i),y1:Y0,y2:Y1,stroke:"#f1f1f4"},mvp);
 el("line",{x1:X0,x2:X1,y1:sy(i),y2:sy(i),stroke:"#f1f1f4"},mvp);
 var tx=el("text",{x:sx(i),y:Y1+22,"text-anchor":"middle","class":"axis"},mvp);tx.textContent=String(i);
 var lbl=["1","2","3","4","5 ★"][i-1];
 var ty=el("text",{x:X0-14,y:sy(i)+3,"text-anchor":"end","class":"axis"},mvp);ty.textContent=lbl;
}
el("line",{x1:sx(3),x2:sx(3),y1:Y0,y2:Y1,stroke:"#e2e2e8"},mvp);
el("line",{x1:X0,x2:X1,y1:sy(3),y2:sy(3),stroke:"#e2e2e8"},mvp);
var ax=el("text",{x:(X0+X1)/2,y:Y1+44,"text-anchor":"middle","class":"axis"},mvp);ax.textContent="COMPLEJIDAD →  (1 = baja · 5 = muy alta)";
var ay=el("text",{x:22,y:(Y0+Y1)/2,"class":"axis",transform:"rotate(-90 22 "+((Y0+Y1)/2)+")","text-anchor":"middle"},mvp);ay.textContent="VALOR PARA TI →";
var cells={};
NODES.filter(function(n){return n.matrix;}).forEach(function(n){
 var k=n.cx+"|"+(n.val||n.prioScore);(cells[k]=cells[k]||[]).push(n);
});
Object.keys(cells).forEach(function(k){
 var arr=cells[k].sort(function(a,b){return a.slot-b.slot;});
 arr.forEach(function(n,i){
  var x=sx(n.cx), y=sy(n.val||n.prioScore)+(i-(arr.length-1)/2)*26;
  var g=el("g",{"class":"dot"},mvp);
  var estW=24+(n.icon.length+1+n.label.length)*6.4;
  var hit=el("rect",{x:x-12,y:y-12,width:estW,height:24,fill:"transparent"},g);
  var c=el("circle",{cx:x,cy:y,r:7,fill:GROUPS[n.group].fill,stroke:GROUPS[n.group].text,"stroke-width":"1.6"},g);
  var t=el("title",{},hit);t.textContent=n.label+" — valor p/ ti "+(n.val||"?")+"/5 · Cx "+n.cx+"/5 · "+n.prio+" · "+n.owner;
  var lb=el("text",{x:x+12,y:y+4,"class":"dlabel"},g);lb.textContent=n.icon+" "+n.label;
  g.addEventListener("mouseenter",function(){var isSel=g.classList.contains("sel");c.setAttribute("r",isSel?"10":"9.5");c.setAttribute("stroke-width","2.6");lb.setAttribute("font-weight","700");});
  g.addEventListener("mouseleave",function(){var isSel=g.classList.contains("sel");c.setAttribute("r",isSel?"10":"7");c.setAttribute("stroke-width",isSel?"2.6":"1.6");if(!isSel)lb.removeAttribute("font-weight");});
  g.addEventListener("click",function(ev){ev.stopPropagation();if(mmoved){mmoved=false;return;}selectNode(n.id);});
  matrixDotEls[n.id]={g:g,c:c,lb:lb,x:x,y:y};
 });
});
// matrix pan/zoom
var mview={x:0,y:0,k:1};
var MZMIN=0.5,MZMAX=3;
function applyMView(){mvp.setAttribute("transform","translate("+mview.x+" "+mview.y+") scale("+mview.k+")");}
function mSvgPt(cx,cy){var r=mx.getBoundingClientRect();var scale=Math.min(r.width/1100,r.height/560);var ox=(r.width-1100*scale)/2,oy=(r.height-560*scale)/2;return {x:(cx-r.left-ox)/scale,y:(cy-r.top-oy)/scale};}
function mZoomAt(px,py,k2){
 k2=Math.min(MZMAX,Math.max(MZMIN,k2));
 mview.x=px-(px-mview.x)*(k2/mview.k); mview.y=py-(py-mview.y)*(k2/mview.k); mview.k=k2;
 applyMView();
}
function mResetView(){mview={x:0,y:0,k:1};applyMView();}
function mFitView(){
 var vs2=visSet();
 var ids=Object.keys(matrixDotEls).filter(function(id){return passesFilter(byId[id])&&(!vs2||vs2.has(id));});
 if(!ids.length){mResetView();return;}
 var minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
 ids.forEach(function(id){var D=matrixDotEls[id],r=14;
  if(D.x-r<minX)minX=D.x-r; if(D.x+r>maxX)maxX=D.x+r;
  if(D.y-r<minY)minY=D.y-r; if(D.y+r>maxY)maxY=D.y+r;
 });
 var w=(maxX-minX)*1.16,h=(maxY-minY)*1.16;
 var cx2=(minX+maxX)/2,cy2=(minY+maxY)/2;
 var k=Math.min(MZMAX,Math.max(MZMIN,Math.min(1100/Math.max(w,1),560/Math.max(h,1))));
 mview.k=k; mview.x=550-cx2*k; mview.y=280-cy2*k;
 applyMView();
}
var mdrag=null,mmoved=false;
mx.addEventListener("wheel",function(ev){
 ev.preventDefault();
 var pt=mSvgPt(ev.clientX,ev.clientY);
 mZoomAt(pt.x,pt.y,mview.k*(ev.deltaY<0?1.12:0.9));
},{passive:false});
mx.addEventListener("pointerdown",function(ev){
 if(marqueeArmed||ev.shiftKey){startMarquee(mx,ev,mSvgPt);return;}
 mdrag={x:ev.clientX,y:ev.clientY,vx:mview.x,vy:mview.y,id:ev.pointerId,captured:false};mmoved=false;
});
mx.addEventListener("pointermove",function(ev){
 if(marqueeState&&marqueeState.svgEl===mx){updateMarqueeVisual(ev);return;}
 if(!mdrag)return;
 var r=mx.getBoundingClientRect(),scale=Math.min(r.width/1100,r.height/560),s=1/scale;
 var dx=(ev.clientX-mdrag.x)*s,dy=(ev.clientY-mdrag.y)*s;
 if(Math.abs(dx)+Math.abs(dy)>3&&!mdrag.captured){
  mmoved=true;mdrag.captured=true;mx.classList.add("panning");
  try{mx.setPointerCapture(mdrag.id);}catch(_e){}
 }
 if(mdrag.captured){mview.x=mdrag.vx+dx; mview.y=mdrag.vy+dy; applyMView();}
});
mx.addEventListener("pointerup",function(ev){
 if(marqueeState&&marqueeState.svgEl===mx){endMarquee(ev);return;}
 mdrag=null;mx.classList.remove("panning");
});
mx.addEventListener("dblclick",function(){mResetView();});
function pulseMatrixDot(id){
 var D=matrixDotEls[id];if(!D)return;
 var sxp=D.x*mview.k+mview.x, syp=D.y*mview.k+mview.y;
 if(sxp<20||sxp>1080||syp<20||syp>540)mFitView();
 D.g.classList.remove("mx-pulse");void D.g.offsetWidth;D.g.classList.add("mx-pulse");
 setTimeout(function(){D.g.classList.remove("mx-pulse");},1600);
}
// marquee zoom-to-region (both #graph and #matrix)
var marqueeArmed=false, marqueeState=null;
function setMarqueeArmed(v){marqueeArmed=v;btnMarquee.classList.toggle("on",v);}
function marqueeRectFor(svgEl){return el("rect",{"class":"marquee-rect"},svgEl);}
var mqGraphRect=marqueeRectFor(svg), mqMatrixRect=marqueeRectFor(mx);
function startMarquee(svgEl,ev,ptFn){
 var p0=ptFn(ev.clientX,ev.clientY);
 marqueeState={svgEl:svgEl,ptFn:ptFn,x0:p0.x,y0:p0.y};
 try{svgEl.setPointerCapture(ev.pointerId);}catch(_e){}
}
function updateMarqueeVisual(ev){
 if(!marqueeState)return;
 var p=marqueeState.ptFn(ev.clientX,ev.clientY);
 var x=Math.min(marqueeState.x0,p.x),y=Math.min(marqueeState.y0,p.y);
 var w=Math.abs(p.x-marqueeState.x0),h=Math.abs(p.y-marqueeState.y0);
 var rectEl=marqueeState.svgEl===svg?mqGraphRect:mqMatrixRect;
 rectEl.setAttribute("x",x);rectEl.setAttribute("y",y);rectEl.setAttribute("width",w);rectEl.setAttribute("height",h);
 rectEl.style.display="block";
}
function endMarquee(ev){
 if(!marqueeState)return;
 var p=marqueeState.ptFn(ev.clientX,ev.clientY);
 var x0=Math.min(marqueeState.x0,p.x),y0=Math.min(marqueeState.y0,p.y);
 var w=Math.abs(p.x-marqueeState.x0),h=Math.abs(p.y-marqueeState.y0);
 var isMatrix=marqueeState.svgEl===mx;
 (isMatrix?mqMatrixRect:mqGraphRect).style.display="none";
 setMarqueeArmed(false);
 var wasReal=w>4&&h>4;
 marqueeState=null;
 if(!wasReal)return;
 if(isMatrix){
  var k=Math.min(MZMAX,Math.max(MZMIN,Math.min(1100/w,560/h)));
  mview.k=k; mview.x=550-(x0+w/2)*k; mview.y=280-(y0+h/2)*k; applyMView();
  mmoved=true;
 }else{
  var k2=Math.min(ZMAX,Math.max(ZMIN,Math.min(1000/w,1000/h)));
  view.k=k2; view.x=500-(x0+w/2)*k2; view.y=500-(y0+h/2)*k2; applyView();
  moved=true;
 }
}
function cancelMarquee(){
 if(marqueeState){(marqueeState.svgEl===mx?mqMatrixRect:mqGraphRect).style.display="none";marqueeState=null;}
 setMarqueeArmed(false);
}

function _store(){try{var st=window.localStorage;st.setItem("__t","1");st.removeItem("__t");return st;}catch(e){return null;}}
var STORE=_store(),MEM={};
var HOY_DONE_OPEN=false;
var HOY_WEEK_OPEN=false;
function ckGet(k){if(STORE)return STORE.getItem(k)==="1";return !!MEM[k];}
function ckSet(k,v){if(STORE){if(v)STORE.setItem(k,"1");else STORE.removeItem(k);}else{MEM[k]=v;}}
function dstr(d){return d.getFullYear()+"-"+("0"+(d.getMonth()+1)).slice(-2)+"-"+("0"+d.getDate()).slice(-2);}
function wstr(d){var j=new Date(d.getFullYear(),0,1);var w=Math.ceil((((d-j)/86400000)+j.getDay()+1)/7);return d.getFullYear()+"-w"+w;}
var MESES_ES=["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"];
var DIAS_ES=["dom","lun","mar","mié","jue","vie","sáb"];
function parseLocalDate(iso){var p=iso.split("-").map(Number);return new Date(p[0],p[1]-1,p[2]);}
function mondayOf(d){var wd=(d.getDay()+6)%7;var m=new Date(d.getFullYear(),d.getMonth(),d.getDate()-wd);return m;}
function fmtWeekRange(monday,refYear){
 var sunday=new Date(monday.getFullYear(),monday.getMonth(),monday.getDate()+6);
 var a=monday.getDate(),b=sunday.getDate();
 if(monday.getMonth()===sunday.getMonth()){
  return a+"–"+b+" "+MESES_ES[sunday.getMonth()];
 }
 var ya=monday.getFullYear()!==refYear?" "+monday.getFullYear():"";
 var yb=sunday.getFullYear()!==refYear?" "+sunday.getFullYear():"";
 return a+" "+MESES_ES[monday.getMonth()]+ya+" – "+b+" "+MESES_ES[sunday.getMonth()]+yb;
}
function fmtDayLabel(d){return DIAS_ES[d.getDay()]+" "+d.getDate()+"/"+(d.getMonth()+1);}
function histRowHtml(D,gid,compact){
 if(D.node!==undefined){
  var nd=byId[D.node],full=D.i+" "+D.t,h;
  if(compact&&full.length>90){
   h="<div class='ckrow jrow'><span class='tt jtxt-short'>"+truncate(full,90)+"</span><span class='tt jtxt-full' style='display:none'>"+full+"</span> <button class='ddbtn jmore' type='button'>más</button>";
  }else{
   h="<div class='ckrow jrow'><span class='tt'>"+full+"</span>";
  }
  if(nd)h+="<span class='chip' data-nav='"+D.node+"' style='cursor:pointer'>"+nd.icon+" "+nd.label+"</span>";
  h+="</div>";
  return h;
 }
 var h="<div class='ckrow'><span class='tt'>"+D.i+" "+D.t+"</span><span class='hist-actions'>";
 if(D.g)h+="<button class='ddbtn' data-histg='"+gid+"'>ver</button>";
 h+="<a class='ddbtn' href='"+D.u+"' target='_blank' rel='noopener'>↗</a></span></div>";
 if(D.g){
  h+="<div class='hint' id='"+gid+"' style='display:none;margin:2px 0 8px 0'>"+D.g;
  if(D.nav)h+=" <button class='hist-more' data-nav-go='"+D.nav+"'>ver más →</button>";
  h+="</div>";
 }
 return h;
}
function histBody(entries,opts){
 opts=opts||{};
 var idPrefix=opts.idPrefix||"hg";
 if(!entries.length)return opts.emptyHtml||"";
 var sorted=entries.slice().sort(function(a,b){return a.date<b.date?1:(a.date>b.date?-1:0);});
 var refYear=parseLocalDate(sorted[0].date).getFullYear();
 var weeks=[],weekMap={};
 sorted.forEach(function(D){
  var d=parseLocalDate(D.date),mon=mondayOf(d),wk=dstr(mon);
  var W=weekMap[wk];
  if(!W){W={monday:mon,days:[],dayMap:{}};weekMap[wk]=W;weeks.push(W);}
  var dk2=dstr(d),Dy=W.dayMap[dk2];
  if(!Dy){Dy={date:d,entries:[]};W.dayMap[dk2]=Dy;W.days.push(Dy);}
  Dy.entries.push(D);
 });
 var out="",idx=0;
 weeks.forEach(function(W){
  if(!opts.noWeekHd){
   var wkCount=0;W.days.forEach(function(Dy){wkCount+=Dy.entries.length;});
   out+="<div class='wk-hd'>Semana "+fmtWeekRange(W.monday,refYear)+" <span class='wk-cnt'>· "+wkCount+"</span></div>";
  }
  W.days.forEach(function(Dy){
   out+="<div class='day-hd'>"+fmtDayLabel(Dy.date)+"</div>";
   Dy.entries.forEach(function(D){out+=histRowHtml(D,idPrefix+(idx++),!!opts.compactJournal);});
  });
 });
 return out;
}
// Historial tab — filter chips (todo/entregas/eventos) + full timeline, data-driven from DONE_LOG+JOURNAL
var HIST_FILTER="all";
function histCounts(){return {all:(DONE_LOG||[]).length+(JOURNAL||[]).length,deliv:(DONE_LOG||[]).length,event:(JOURNAL||[]).length};}
function histEntriesFor(filter){
 if(filter==="deliv")return (DONE_LOG||[]).slice();
 if(filter==="event")return (JOURNAL||[]).slice();
 return (DONE_LOG||[]).concat(JOURNAL||[]);
}
function renderHistorial(){
 var c=histCounts();
 var fbox=document.getElementById("histFilters");
 if(fbox){
  var chips=[["all","Todo ("+c.all+")"],["deliv","📦 Entregas ("+c.deliv+")"],["event","📝 Eventos ("+c.event+")"]];
  var h="";
  chips.forEach(function(ch){h+="<button class='lens"+(HIST_FILTER===ch[0]?" on":"")+"' data-hfilt='"+ch[0]+"'>"+ch[1]+"</button>";});
  fbox.innerHTML=h;
 }
 var box=document.getElementById("histTlBody");if(!box)return;
 var entries=histEntriesFor(HIST_FILTER);
 box.innerHTML=entries.length?histBody(entries,{idPrefix:"hth"}):"<p class='hint'>Sin entradas.</p>";
}
document.getElementById("tab-historial").addEventListener("click",function(ev){
 var f=ev.target.closest("[data-hfilt]");
 if(f){HIST_FILTER=f.getAttribute("data-hfilt");renderHistorial();return;}
 var g=ev.target.closest("[data-histg]");
 if(g){var gg=document.getElementById(g.getAttribute("data-histg"));if(gg){var open=gg.style.display==="block";gg.style.display=open?"none":"block";g.textContent=open?"ver":"ocultar";}return;}
 var nvg=ev.target.closest("[data-nav-go]");
 if(nvg){var nv=nvg.getAttribute("data-nav-go");if(nv.slice(0,2)==="r-")selectRitual(nv);else selectNode(nv);return;}
 var t=ev.target.closest("[data-nav]");
 if(t){selectNode(t.getAttribute("data-nav"));return;}
});
// Memoria tab — collapsible category sections built from MEMORY.cats
var MEM_OPEN={},MEM_INITED=false;
function memRefChipsHtml(refs){
 var h="";
 (refs||[]).forEach(function(rid){var nd=byId[rid];if(!nd)return;h+="<span class='chip' data-nav='"+rid+"' style='cursor:pointer'>"+nd.icon+" "+nd.label+"</span>";});
 return h;
}
function memNoteHtml(nt){
 var h="<div class='mnote' id='mnote-"+nt.id+"' style='margin:0 0 14px'>";
 h+="<p class='hint' style='margin:0 0 3px;color:#3f3f43;line-height:1.55'>"+(nt.pinned?"📌 ":"")+nt.t+"</p>";
 h+="<p class='hint' style='margin:0 0 5px;font-size:11px'>"+nt.id+" · actualizado "+nt.date_upd+"</p>";
 var chips=memRefChipsHtml(nt.refs);
 if(chips)h+="<div class='chips' style='margin:0'>"+chips+"</div>";
 h+="</div>";
 return h;
}
function renderMemoria(){
 var box=document.getElementById("memoriaBody");if(!box)return;
 var cats=memCats();
 if(!MEM_INITED){cats.forEach(function(c){MEM_OPEN[c.id]=(c.notes||[]).some(function(nt){return nt.pinned;});});MEM_INITED=true;}
 if(!cats.length){box.innerHTML="<p class='hint'>Sin notas todavía.</p>";return;}
 var h="";
 cats.forEach(function(c){
  var notes=(c.notes||[]).slice().sort(memNoteSort);
  var open=!!MEM_OPEN[c.id];
  h+="<div class='sect'><div class='t ckgroup-hd' data-memcat='"+c.id+"'>"+(open?"▾":"▸")+" "+c.icon+" "+c.label+" ("+notes.length+")</div>";
  h+="<div class='ckgroup-body"+(open?" open":"")+"' id='memcat-"+c.id+"'>";
  notes.forEach(function(nt){h+=memNoteHtml(nt);});
  h+="</div></div>";
 });
 box.innerHTML=h;
 box.querySelectorAll("[data-memcat]").forEach(function(x){x.addEventListener("click",function(){MEM_OPEN[x.getAttribute("data-memcat")]=!MEM_OPEN[x.getAttribute("data-memcat")];renderMemoria();});});
 box.querySelectorAll("[data-nav]").forEach(function(x){x.addEventListener("click",function(){selectNode(x.getAttribute("data-nav"));});});
}
function goToMemoryNote(noteId,catId){
 switchTab("memoria");
 MEM_OPEN[catId]=true;
 renderMemoria();
 requestAnimationFrame(function(){
  var e2=document.getElementById("mnote-"+noteId);
  if(!e2)return;
  e2.scrollIntoView({behavior:"smooth",block:"center"});
  e2.classList.remove("flash");void e2.offsetWidth;e2.classList.add("flash");
  setTimeout(function(){e2.classList.remove("flash");},1600);
 });
}
function hoyToday(){return parseLocalDate(META.updated);}
function renderHoy(){
 var box=document.getElementById("hoyBody");if(!box)return;
 var now=hoyToday(),day=now.getDay();
 var names=["domingo","lunes","martes","miércoles","jueves","viernes","sábado"];
 var h="";
 h+="<div class='sect' style='border-top:0;padding-top:0'><div class='t'>⏳ Deadlines</div><div style='display:flex;flex-wrap:wrap;gap:6px'>";
 DEADLINES.forEach(function(D){
  var days=Math.round((parseLocalDate(D[0])-now)/86400000);
  var bg=days<=3?"#fee2e2":(days<=11?"#fef3c7":"#f4f4f5"),fg=days<=3?"#b91c1c":(days<=11?"#b45309":"#52525b");
  h+="<span class='chip' data-nav='"+D[2]+"' title='ver contexto' style='background:"+bg+";color:"+fg+";border-color:transparent;font-size:11px;cursor:pointer'>"+D[1]+" · "+(days<0?"pasó":(days===0?"HOY":days+"d"))+"</span>";
 });
 h+="</div></div>";
 if(INBOX.length){
  h+="<div class='sect'><div class='t'>📥 Inbox ("+INBOX.length+") — por triar</div>";
  h+="<p class='hint' style='margin:0 0 8px'>Captura con: update_q3.py note --text \"...\" · el triage diario lo vacía</p>";
  INBOX.forEach(function(I){h+="<p class='hint' style='margin:0 0 4px;color:#3f3f43'>"+fmtDayLabel(parseLocalDate(I.date))+" · "+I.t+"</p>";});
  h+="</div>";
 }
 var dk="q3:"+dstr(now)+":", wk="q3:"+wstr(now)+":";
 function row(key,icon,label,target){
  var done=ckGet(key);
  var btn="";
  if(target){var attr=(target.slice(0,2)==="r-")?"data-rit":"data-nav";btn="<button class='ddbtn' "+attr+"='"+target+"' style='margin-left:auto'>ver</button>";}
  return "<label class='ckrow"+(done?" done":"")+"'><input type='checkbox' data-ck='"+key+"'"+(done?" checked":"")+"> <span class='tt'>"+icon+" "+label+"</span>"+btn+"</label>";
 }
 var doneRows=[];
 function pushRow(key,icon,label,target){
  var html=row(key,icon,label,target);
  if(ckGet(key)){doneRows.push(html);return "";}
  return html;
 }
 if(day===0||day===6){
  h+="<div class='sect'><div class='t'>✅ "+names[day]+"</div><p class='hint'>Fin de semana — nada obligatorio. Recarga; el lunes arranca con la weekly.</p></div>";
 }else{
  var todayHtml="";
  todayHtml+=pushRow(dk+"daily","🌅","Daily check-in + barrido del canal de incidencias","r-daily");
  if(day===1)todayHtml+=pushRow(dk+"weekly","🧭","Weekly sync: 3 bullets + actualizar esta guía al salir","r-weekly");
  if(day===3)todayHtml+=pushRow(dk+"review","🏛️","Design review (pregunta preparada / presentar)","r-review");
  if(day===5)todayHtml+=pushRow(dk+"health","📊","Publicar la nota de salud semanal","r-health");
  todayHtml+=pushRow(dk+"code","💻","Bloque de código protegido cumplido","r-code");
  h+="<div class='sect'><div class='t'>✅ Hoy · "+names[day]+"</div>"+todayHtml+"</div>";
 }
 var weekHtml="";
 WEEK_PENDINGS.forEach(function(W){var lbl=W[2];if(W[4]){var days=Math.round((hoyToday()-parseLocalDate(W[4]))/86400000);if(days>=1)lbl+=" <span style='font-size:10px;color:"+(days>3?"#d97706":"var(--muted-fg)")+"'>· "+days+"d</span>";}weekHtml+=pushRow(wk+W[0],W[1],lbl,W[3]||null);});
 h+="<div class='sect'><div class='t'>📌 Pendientes de la semana</div>"+weekHtml+"</div>";
 if(doneRows.length){
  h+="<div class='sect'><div class='t ckgroup-hd' id='ckDoneHd'>"+(HOY_DONE_OPEN?"▾":"▸")+" ✓ Completadas hoy ("+doneRows.length+")</div>";
  h+="<div class='ckgroup-body"+(HOY_DONE_OPEN?" open":"")+"' id='ckDoneBody'>"+doneRows.join("")+"</div></div>";
 }
 var weekStart=mondayOf(now),weekEnd=new Date(weekStart.getFullYear(),weekStart.getMonth(),weekStart.getDate()+6);
 var wkStartStr=dstr(weekStart),wkEndStr=dstr(weekEnd);
 var HIST_WEEK=(DONE_LOG||[]).concat(JOURNAL||[]).filter(function(D){return D.date>=wkStartStr&&D.date<=wkEndStr;});
 if(HIST_WEEK.length){
  h+="<div class='sect'><div class='t ckgroup-hd' id='ckWeekHd'>"+(HOY_WEEK_OPEN?"▾":"▸")+" 🗄️ Sucedió esta semana ("+HIST_WEEK.length+")</div>";
  h+="<div class='ckgroup-body"+(HOY_WEEK_OPEN?" open":"")+"' id='ckWeekBody'><div class='hist-tl'>"+histBody(HIST_WEEK,{noWeekHd:true,idPrefix:"hoh",compactJournal:true})+"</div></div>";
  h+="<button class='hist-more' data-tab-go='historial'>Ver historial completo →</button></div>";
 }else{
  h+="<div class='sect'><button class='hist-more' data-tab-go='historial'>Ver historial completo →</button></div>";
 }
 h+="<div class='sect'><div class='t'>🎯 Foco del día (en orden)</div>";
 FOCUS.forEach(function(F){
  h+="<div class='conn' data-nav='"+F[0]+"'><span class='dot' style='background:"+F[1]+"'></span><span>"+F[2]+" <b>"+F[3]+"</b></span><span class='lbl'>"+F[4]+"</span></div>";
  var fh=bestMemNoteFor(F[0]);
  if(fh)h+="<p class='hint' style='margin:0 0 6px 20px;cursor:pointer' data-navmem='"+fh.note.id+"|"+fh.cat.id+"'>🧠 "+fh.note.t+"</p>";
 });
 h+="</div>";
 h+="<div class='sect'><div class='t'>🧭 Tu narrativa (cuelga todo de esta frase)</div><p class='hint' style='color:#3f3f43'>"+META.narrativa+"</p></div>";
 h+="<div class='sect'><div class='t'>📋 Plantillas (1 click y pegar)</div>";
 h+="<p class='hint' style='margin:0 0 8px'>Esqueletos: 1 click copia el texto, lo rellenas y lo pegas donde toque.</p>";
 h+="<button class='ddbtn' data-copytpl='tpl-daily' title='Daily / standup' style='margin:0 6px 6px 0;font-size:11px;padding:4px 10px'>📋 Daily update</button>";
 h+="<button class='ddbtn' data-copytpl='tpl-weekly' title='Update semanal a leads' style='margin:0 6px 6px 0;font-size:11px;padding:4px 10px'>📋 3 bullets weekly</button>";
 h+="<button class='ddbtn' data-copytpl='tpl-health' title='Nota de salud semanal' style='margin:0 6px 6px 0;font-size:11px;padding:4px 10px'>📋 Nota de salud</button>";
 h+="</div>";
 box.innerHTML=h;
 box.querySelectorAll("[data-ck]").forEach(function(x){x.addEventListener("change",function(){ckSet(x.getAttribute("data-ck"),x.checked);renderHoy();});});
 var ckDoneHd=box.querySelector("#ckDoneHd");
 if(ckDoneHd){ckDoneHd.addEventListener("click",function(){
  HOY_DONE_OPEN=!HOY_DONE_OPEN;
  document.getElementById("ckDoneBody").classList.toggle("open",HOY_DONE_OPEN);
  ckDoneHd.textContent=(HOY_DONE_OPEN?"▾":"▸")+" ✓ Completadas hoy ("+doneRows.length+")";
 });}
 var ckWeekHd=box.querySelector("#ckWeekHd");
 if(ckWeekHd){ckWeekHd.addEventListener("click",function(){
  HOY_WEEK_OPEN=!HOY_WEEK_OPEN;
  document.getElementById("ckWeekBody").classList.toggle("open",HOY_WEEK_OPEN);
  ckWeekHd.textContent=(HOY_WEEK_OPEN?"▾":"▸")+" 🗄️ Sucedió esta semana ("+HIST_WEEK.length+")";
 });}
 box.querySelectorAll(".jmore").forEach(function(x){x.addEventListener("click",function(){
  var row=x.closest(".jrow");if(!row)return;
  var s=row.querySelector(".jtxt-short"),f=row.querySelector(".jtxt-full");
  if(!s||!f)return;
  var opening=f.style.display==="none";
  f.style.display=opening?"inline":"none";
  s.style.display=opening?"none":"inline";
  x.textContent=opening?"menos":"más";
 });});
 box.querySelectorAll("[data-histg]").forEach(function(x){x.addEventListener("click",function(){
  var g=document.getElementById(x.getAttribute("data-histg"));if(!g)return;
  var open=g.style.display==="block";
  g.style.display=open?"none":"block";
  x.textContent=open?"ver":"ocultar";
 });});
 box.querySelectorAll("[data-nav-go]").forEach(function(x){x.addEventListener("click",function(ev){ev.preventDefault();var nv=x.getAttribute("data-nav-go");if(nv.slice(0,2)==="r-")selectRitual(nv);else selectNode(nv);});});
 box.querySelectorAll("[data-tab-go]").forEach(function(x){x.addEventListener("click",function(){switchTab(x.getAttribute("data-tab-go"));});});
 box.querySelectorAll("[data-rit]").forEach(function(x){x.addEventListener("click",function(ev){ev.preventDefault();selectRitual(x.getAttribute("data-rit"));});});
 box.querySelectorAll("[data-nav]").forEach(function(x){x.addEventListener("click",function(ev){ev.preventDefault();selectNode(x.getAttribute("data-nav"));});});
 box.querySelectorAll("[data-navmem]").forEach(function(x){x.addEventListener("click",function(ev){
  ev.preventDefault();var parts=x.getAttribute("data-navmem").split("|");goToMemoryNote(parts[0],parts[1]);
 });});
 box.querySelectorAll("[data-copytpl]").forEach(function(x){x.addEventListener("click",function(){
  var t=document.getElementById(x.getAttribute("data-copytpl"));if(!t)return;
  var btn=x,orig=btn.textContent;
  function ok(){btn.textContent="✓ copiado";setTimeout(function(){btn.textContent=orig;},1300);}
  var txt=t.textContent;
  function ko(){var ta=document.createElement("textarea");ta.value=txt;ta.style.position="fixed";ta.style.opacity="0";document.body.appendChild(ta);ta.focus();ta.select();var s=false;try{s=document.execCommand("copy");}catch(e){}document.body.removeChild(ta);if(s){ok();}else{btn.textContent="⚠️ copia manual (⌘C)";var sel=window.getSelection(),rg=document.createRange();rg.selectNodeContents(t);sel.removeAllRanges();sel.addRange(rg);setTimeout(function(){btn.textContent=orig;},2600);}}
  if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(txt).then(ok,ko);}else{ko();}
 });});
}
renderHoy();
renderHistorial();
renderMemoria();
applyState();renderPanel();switchTab("hoy");
</script>
