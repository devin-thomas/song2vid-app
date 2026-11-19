#!/usr/bin/env python3
"""Render STATUS.md and index.html from status.json for one dashboard task.

Usage: python3 docs/agent-dashboard/render.py docs/agent-dashboard/<task-slug>
"""
import html, json, sys, pathlib

d = pathlib.Path(sys.argv[1])
s = json.loads((d / "status.json").read_text())
e = lambda t: html.escape(str(t), quote=True)

STATE_ICON = {"working": "⚙️", "healthy": "✅", "waiting": "⏳", "attention": "⚠️", "blocked": "⛔", "complete": "✅"}
MS_ICON = {"pending": "○ Pending", "in_progress": "◐ In progress", "complete": "● Complete", "blocked": "⛔ Blocked"}

# ---------- STATUS.md ----------
md = [f"# {s['title']}", "",
      f"State: **{s['state']}** · Phase: {s['phase']} · Updated: {s['updated_at']}",
      f"Repository: {s['repository']} · Branch: {s['branch']}", "", "## Action required", ""]
md += [f"- **{a['need']}**: {a['reason']} Smallest action: {a['action']}" for a in s["action_required"]] or ["No action required from you right now."]
md += ["", "## Current activity", "", s["current_activity"], "", "## Milestones", ""]
md += [f"- [{m['status']}] {m['name']}" + (f" ({m['note']})" if m.get('note') else "") for m in s["milestones"]]
md += ["", "## Blockers", ""] + ([f"- {b['cause']} Impact: {b['impact']} Owner: {b['owner']}. Recovery: {b['recovery']}" for b in s["blockers"]] or ["None."])
md += ["", "## Warnings", ""] + ([f"- ({w['label']}) {w['text']}" for w in s["warnings"]] or ["None."])
md += ["", "## Decisions", ""] + [f"- {x['time']}: {x['decision']} ({x['status']}; {x['reversibility']}). {x['rationale']}" for x in s["decisions"]]
md += ["", "## Outputs", ""] + [f"- [{o['label']}]({o['link']})" + (f": {o['note']}" if o.get('note') else "") for o in s["outputs"]]
md += ["", "## Next up", ""] + [f"{i}. {n}" for i, n in enumerate(s["next_up"], 1)]
md += ["", "## Activity", ""] + [f"- {a['time']}: {a['event']}" for a in s["activity"]]
w = s["walk_away"]
md += ["", "## Walk-away snapshot", "", f"- Last verified good state: {w['last_good']}", f"- Unfinished: {w['unfinished']}",
       f"- Next safe step: {w['next_safe_step']}", f"- Touched: {w['touched']}", f"- Expected processes: {w['processes']}", f"- Input needed: {w['input_needed']}"]
dl = s["delivery"]
md += ["", "## Delivery and persistence", "", f"- Mode: {dl['mode']} ({dl['url']})", f"- Last endpoint check: {dl['last_verified']}", f"- Persistence: {dl['persistence']}", f"- Limitations: {dl['limitations']}", ""]
(d / "STATUS.md").write_text("\n".join(md))

# ---------- index.html ----------
def lis(items, fn, empty):
    return "".join(f"<li>{fn(i)}</li>" for i in items) or f"<li class=quiet>{e(empty)}</li>"

actions = lis(s["action_required"], lambda a: f"<strong>🚨 {e(a['need'])}</strong><br>{e(a['reason'])}<br><em>Do this:</em> {e(a['action'])}" + (f"<br><span class=quiet>Default if no answer: {e(a['default'])}</span>" if a.get('default') else ""), "No action required from you right now.")
ms = lis(s["milestones"], lambda m: f"<span class='ms {e(m['status'])}'>{e(MS_ICON.get(m['status'], m['status']))}</span> {e(m['name'])}" + (f" <span class=quiet>· {e(m['note'])}</span>" if m.get('note') else ""), "None")
bl = lis(s["blockers"], lambda b: f"<strong>⛔ {e(b['cause'])}</strong><br>Impact: {e(b['impact'])} · Owner: {e(b['owner'])}<br>Recovery: {e(b['recovery'])}<br><span class=quiet>Continuing meanwhile: {e(b.get('independent_work',''))}</span>", "None.")
wa = lis(s["warnings"], lambda x: f"<span class=warn>⚠️ {e(x['label'])}</span> {e(x['text'])}", "None.")
de = lis(s["decisions"], lambda x: f"<strong>{e(x['decision'])}</strong> <span class=quiet>({e(x['time'])} · {e(x['status'])} · {e(x['reversibility'])})</span><br>{e(x['rationale'])}", "None")
ou = lis(s["outputs"], lambda o: f"<a href='{e(o['link'])}'>{e(o['label'])}</a>" + (f" <span class=quiet>· {e(o['note'])}</span>" if o.get('note') else ""), "None yet")
nx = "".join(f"<li>{e(n)}</li>" for n in s["next_up"])
ac = lis(list(reversed(s["activity"])), lambda a: f"<span class=quiet>{e(a['time'])}</span> {e(a['event'])}", "None")
wk = "".join(f"<dt>{e(k)}</dt><dd>{e(v)}</dd>" for k, v in [("Last verified good state", w['last_good']), ("Unfinished", w['unfinished']), ("Next safe step", w['next_safe_step']), ("Touched", w['touched']), ("Expected processes", w['processes']), ("Input needed", w['input_needed'])])
dv = "".join(f"<dt>{e(k)}</dt><dd>{e(v)}</dd>" for k, v in [("Mode", f"{dl['mode']} · {dl['url']}"), ("Last endpoint check", dl['last_verified']), ("Persistence", dl['persistence']), ("Limitations", dl['limitations'])])

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="dashboard-task-id" content="{e(s['task_id'])}">
<meta name="dashboard-updated-at" content="{e(s['updated_at'])}">
<title>Song2Vid build dashboard</title>
<link rel="icon" href="data:,">
<style>
:root{{--bg:#f7f6fb;--card:#fff;--fg:#1d1b26;--muted:#6b6880;--line:#e4e1ee;--accent:#7c3aed;--alarm:#b42318;--alarmbg:#fdecea;--warn:#8a5a00;--warnbg:#fff6e0;--ok:#127a3d}}
@media (prefers-color-scheme:dark){{:root:not([data-theme=light]){{--bg:#14121b;--card:#1d1a27;--fg:#ece9f5;--muted:#a19db5;--line:#2e2a3c;--accent:#b794f6;--alarm:#ff8a80;--alarmbg:#3a1a1a;--warn:#ffcf70;--warnbg:#3a2e12;--ok:#6fdc9a}}}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}}
main{{max-width:960px;margin:0 auto;padding:16px}} header h1{{margin:0;font-size:1.4rem}} .meta{{color:var(--muted);font-size:.9rem}}
.state{{display:inline-block;padding:2px 10px;border-radius:999px;background:var(--card);border:1px solid var(--line);font-weight:600}}
section{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 16px;margin:12px 0}} h2{{font-size:1rem;margin:0 0 8px}}
ul,ol{{margin:0;padding-left:20px}} li{{margin:4px 0}} .quiet{{color:var(--muted)}} a{{color:var(--accent)}}
#action{{border:2px solid var(--alarm);background:var(--alarmbg)}} #action.none{{border:1px solid var(--line);background:var(--card)}}
.warn{{color:var(--warn);background:var(--warnbg);padding:0 6px;border-radius:4px;font-weight:600}}
.ms.complete{{color:var(--ok);font-weight:600}} .ms.in_progress{{color:var(--accent);font-weight:600}} .ms.blocked{{color:var(--alarm);font-weight:600}}
dl{{margin:0}} dt{{font-weight:600}} dd{{margin:0 0 6px}} .grid{{display:grid;gap:0 12px;grid-template-columns:1fr}}
@media(min-width:760px){{.grid{{grid-template-columns:1fr 1fr}}}} #fresh{{font-size:.85rem}}
</style></head><body><main>
<header><h1>{e(s['title'])}</h1>
<p><span class=state>{e(STATE_ICON.get(s['state'],''))} {e(s['state'])}</span> · Phase: {e(s['phase'])}</p>
<p class=meta>Updated {e(s['updated_at'])} · {e(s['repository'])} · branch {e(s['branch'])} · <span id=fresh>live check pending</span></p></header>
<section id=action class="{'' if s['action_required'] else 'none'}"><h2>Action required</h2><ul>{actions}</ul></section>
<section><h2>Current activity</h2><p style="margin:0">{e(s['current_activity'])}</p></section>
<div class=grid><section><h2>Milestones</h2><ul>{ms}</ul></section><section><h2>Next up</h2><ol>{nx}</ol></section></div>
<div class=grid><section><h2>Blockers</h2><ul>{bl}</ul></section><section><h2>Warnings</h2><ul>{wa}</ul></section></div>
<section><h2>Decisions</h2><ul>{de}</ul></section>
<section><h2>Outputs</h2><ul>{ou}</ul></section>
<section><h2>Activity</h2><ul>{ac}</ul></section>
<div class=grid><section><h2>Walk-away snapshot</h2><dl>{wk}</dl></section><section><h2>Delivery and persistence</h2><dl>{dv}</dl></section></div>
</main>
<script>
const shown = document.querySelector('meta[name="dashboard-updated-at"]').content;
const f = document.getElementById('fresh');
async function check(){{
  try {{
    const r = await fetch('status.json?ts=' + Date.now(), {{cache:'no-store'}});
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const j = await r.json();
    if (j.updated_at !== shown) {{ location.replace(location.pathname + '?ts=' + Date.now()); return; }}
    f.textContent = 'live, checked ' + new Date().toLocaleTimeString();
  }} catch (err) {{ f.textContent = 'could not refresh (' + err.message + '): this view may be stale'; }}
}}
if (location.protocol.startsWith('http')) {{ check(); setInterval(check, 15000); }} else {{ f.textContent = 'offline snapshot'; }}
</script></body></html>
"""
(d / "index.html").write_text(page)
print("rendered", s["task_id"], s["updated_at"])
