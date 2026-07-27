#!/usr/bin/env python3
"""Builder de la guía Q3: q3-data.json (estado) + _q3-shell.tpl (UI) -> q3-map-2026.html (auto-contenido)."""
import json, os
here=os.path.dirname(os.path.abspath(__file__))
data=json.load(open(os.path.join(here,'q3-data.json')))
prompt_txt=open(os.path.join(here,'q3-prompt.txt')).read()
prompt_html=prompt_txt.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
sh=open(os.path.join(here,'_q3-shell.tpl')).read()
consts=""
for name,key in [("RITUALS","rituals"),("NODES","nodes"),("EDGES","edges"),("LENSES","lenses"),("DEADLINES","deadlines"),("WEEK_PENDINGS","week_pendings"),("FOCUS","focus"),("DONE_LOG","done_log"),("JOURNAL","journal"),("INBOX","inbox"),("MEMORY","memory")]:
    consts+="const %s=%s;\n"%(name,json.dumps(data.get(key,[]),ensure_ascii=False))
consts+="const META=%s;\n"%json.dumps({"narrativa":data["narrativa"],"updated":data["meta"]["updated"]},ensure_ascii=False)
out=sh.replace('/*@DATA*/\n',consts)

# --- 📏 Mi desempeño: computed from the DB at build time ---
def _perf_html(data):
    import datetime, collections
    dl=data.get('done_log',[]); jr=data.get('journal',[])
    per_month=collections.Counter(e['date'][:7] for e in dl)
    with_ev=sum(1 for e in dl if e.get('g') or e.get('u'))
    months=' · '.join('%s: <b>%d</b>'%(m,c) for m,c in sorted(per_month.items(),reverse=True)[:4])
    # racha nota de salud: semanas ISO consecutivas (hacia atrás desde la última) con entrega nav==r-health
    weeks=set()
    for e in dl:
        if e.get('nav')=='r-health':
            y,m,dd=map(int,e['date'].split('-')); iso=datetime.date(y,m,dd).isocalendar()
            weeks.add((iso[0],iso[1]))
    streak=0
    if weeks:
        cur=max(weeks)
        while cur in weeks:
            streak+=1
            prev=datetime.date.fromisocalendar(cur[0],cur[1],1)-datetime.timedelta(weeks=1)
            cur=prev.isocalendar()[:2]
    inc=[j for j in jr if '🚨' in j.get('i','') or 'incidente' in j.get('t','').lower()]
    return ('<div class="hint">📦 Entregas con evidencia: %d total (%d%% con doc/guía) — %s</div>'
            '<div class="hint">📊 Racha nota de salud: <b>%d semana%s</b> consecutiva%s</div>'
            '<div class="hint">🚨 Incidentes registrados en bitácora: %d (objetivo: mitigación &lt;1 día — anota el turnaround al journalear)</div>'
            )%(len(dl),round(100*with_ev/len(dl)) if dl else 0,months or '—',
               streak,'s' if streak!=1 else '','s' if streak!=1 else '',len(inc))

def _competencias_html(data):
    c=data.get('competencias')
    if not c: return '<div class="hint">Sin auto-score aún.</div>'
    rows=''
    for it in c['items']:
        s=it['score']; bar='█'*s+'░'*(5-s)
        rows+='<div class="hint" style="margin:0 0 4px"><code>%s</code> <b>%s</b> %d/5 — %s</div>'%(bar,it['label'],s,it['note'])
    return rows+'<div class="hint" style="opacity:.7">%s (actualizado %s)</div>'%(c.get('note',''),c.get('updated',''))

kpis=data['tabs']['kpis'].replace('@EVIDENCE@','<br>'.join(data['evidence']))
kpis=kpis.replace('@PERF@',_perf_html(data)).replace('@COMPETENCIAS@',_competencias_html(data))
repl={
 '<!--@TAB_RITMO-->':data['tabs']['ritmo'],
 '<!--@TAB_PROYECTOS-->':data['tabs']['proyectos'],
 '<!--@TAB_ALIADOS-->':data['tabs']['aliados'],
 '<!--@TAB_INSIGHTS-->':data['tabs']['insights'],
 '<!--@TAB_KPIS-->':kpis,
 '<!--@TAB_FUENTES-->':data['tabs']['fuentes'],
 '<!--@TAB_PROMPT_HEAD-->':data['tabs']['prompt_head'],
 '<!--@TPL_DAILY-->':data['templates']['tpl-daily'],
 '<!--@TPL_WEEKLY-->':data['templates']['tpl-weekly'],
 '<!--@TPL_HEALTH-->':data['templates']['tpl-health'],
 '<!--@TBS-->':"%d nodos · %d relaciones · fuentes: %s · %s"%(len(data['nodes']),len(data['edges']),data['meta']['fuentes'],data['meta']['updated']),
}
for k,v in repl.items():
    assert k in out, "placeholder faltante: "+k
    out=out.replace(k,v)
assert '<!--@' not in out.replace('<!--@PROMPT-->','') and '/*@DATA*/' not in out, "quedaron placeholders"
assert '<!--@PROMPT-->' in out
out=out.replace('<!--@PROMPT-->',prompt_html)
open(os.path.join(here,'q3-map-2026.html'),'w').write(out)
print("built q3-map-2026.html · %dKB · %d nodos · %d edges"%(os.path.getsize(os.path.join(here,'q3-map-2026.html'))//1024,len(data['nodes']),len(data['edges'])))
