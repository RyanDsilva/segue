import json, sys, re, statistics as st
from collections import defaultdict
sys.path.insert(0, '.')
from gold import PASTE, SET, DEFAULTS
import os

def _flag(name):
    """--name PATH from argv (removed from argv so the rest are result files)."""
    if name in sys.argv:
        i = sys.argv.index(name)
        val = sys.argv[i + 1]
        del sys.argv[i:i + 2]
        return val
    return None

# P3-A: score Ryan's real pastes against a local gold file instead of the spike fixtures.
#   python3 score.py --gold ../phase3-eval/gold.local.json --hints ../phase3-eval/results/hints.json run.jsonl
# Gold JSON: {"<paste name>": {"labels": [label | [alternatives]], "title": str|null|[alts],
#   "artist": str|null|[alts], "key": str|[alts], "keyStated": bool}}. Lists become tuples
#   (the "any of" form used in gold.py).
_gold_path = _flag('--gold')
_hints_path = _flag('--hints') or 'hints.json'
if _gold_path:
    def _alts(v):
        return tuple(v) if isinstance(v, list) else v
    PASTE = {name: dict(labels=[_alts(l) for l in g['labels']], title=_alts(g.get('title')),
                        artist=_alts(g.get('artist')), key=_alts(g.get('key', 'unknown')),
                        keyStated=bool(g.get('keyStated')))
             for name, g in json.load(open(_gold_path)).items()}
HINTS = json.load(open(_hints_path)) if os.path.exists(_hints_path) else {}

def norm(s):
    return re.sub(r'[^a-z0-9]', '', (s or '').lower()) or None

def match(val, gold):
    golds = gold if isinstance(gold, tuple) else (gold,)
    return any(norm(val) == norm(g) for g in golds) if any(isinstance(g,str) for g in golds) or val else (val in (None,'') and None in golds)

def meta_ok(val, gold):
    golds = gold if isinstance(gold, tuple) else (gold,)
    v = norm(val)
    return any((v is None and g is None) or (g is not None and v == norm(g)) for g in golds)

def merge_chunks(recs):
    """records for one item/run -> merged output dict or error"""
    out = {'blocks': []}
    for r in sorted(recs, key=lambda r: r['chunk']):
        if not r['ok']: return None, r.get('errorKind')
        o = json.loads(r['output'])
        out['blocks'] += o.get('blocks', [])
        for k in ('title','artist','key'):
            if k in o and k not in out: out[k] = o[k]
    # deterministic post-processing (code, not model): placeholder words -> empty; artist == title -> empty
    for k in ('title','artist'):
        if norm(out.get(k)) in ('unknown','none','na','null','notitle','noartist'): out[k] = None
    if out.get('artist') and norm(out.get('artist')) == norm(out.get('title')): out['artist'] = None
    return out, None

def score_paste(path):
    recs = [json.loads(l) for l in open(path)]
    by = defaultdict(list)
    # group into runs: consecutive records for same item with chunk restarting at 0
    runs = []
    for r in recs:
        if r['task'] != 'paste': continue
        if r['chunk'] == 0: runs.append([r])
        else: runs[-1].append(r)
    rows = []
    for run in runs:
        item = run[0]['item']; g = PASTE[item]
        out, err = merge_chunks(run)
        lat = sum(r['latencyMs'] for r in run)
        row = dict(item=item, lang=item[0], ok=out is not None, err=err, latency=lat, chunks=len(run),
                   promptTokens=sum(r.get('promptTokens') or 0 for r in run),
                   outTokens=sum(r.get('outputTokens') or 0 for r in run),
                   peakMB=max((r.get('peakMemoryMB') or 0) for r in run))
        if out:
            lab = {b['block']: b['label'] for b in out['blocks']}
            correct = 0; uh_c = 0; uh_n = 0
            hints = HINTS.get(item, [''] * len(g['labels']))
            for i, gl in enumerate(g['labels']):
                if 'header says' not in hints[i]:
                    uh_n += 1
                    gls = gl if isinstance(gl, tuple) else (gl,)
                    uh_c += lab.get(i) in gls
                gls = gl if isinstance(gl, tuple) else (gl,)
                if lab.get(i) in gls: correct += 1
            row.update(uhC=uh_c, uhN=uh_n, blocksGold=len(g['labels']), blocksOut=len(out['blocks']), labelCorrect=correct,
                       countMismatch=len(out['blocks']) != len(g['labels']) or sorted(lab) != list(range(len(g['labels']))),
                       title=meta_ok(out.get('title'), g['title']), artist=meta_ok(out.get('artist'), g['artist']),
                       key=meta_ok(out.get('key'), g['key']), keyStated=g['keyStated'], out=out)
        rows.append(row)
    return rows

def summarize_paste(rows, label=''):
    def agg(rs):
        n = len(rs); ok = [r for r in rs if r['ok']]
        errs = defaultdict(int)
        for r in rs:
            if not r['ok']: errs[r['err']] += 1
        lab_c = sum(r['labelCorrect'] for r in ok); lab_n = sum(r['blocksGold'] for r in ok)
        lab_all_n = sum(len(PASTE[r['item']]['labels']) for r in rs)
        perfect = sum(1 for r in ok if r['labelCorrect'] == r['blocksGold'])
        lats = sorted(r['latency'] for r in ok) or [0]
        return dict(n=n, ok=len(ok), errors=dict(errs),
            labelAccOk=round(100*lab_c/lab_n,1) if lab_n else None,
            labelAccAll=round(100*lab_c/lab_all_n,1) if lab_all_n else None,
            songsAllLabelsRight=perfect,
            unheadedAcc=round(100*sum(r['uhC'] for r in ok)/max(1,sum(r['uhN'] for r in ok)),1),
            countMismatch=sum(1 for r in ok if r['countMismatch']),
            title=sum(1 for r in ok if r['title']), artist=sum(1 for r in ok if r['artist']),
            titleArtist=sum(1 for r in ok if r['title'] and r['artist']),
            key=sum(1 for r in ok if r['key']), keyStated=f"{sum(1 for r in ok if r['key'] and r['keyStated'])}/{sum(1 for r in ok if r['keyStated'])}",
            latMedianS=round(st.median(lats)/1000,2), latP90S=round(lats[int(0.9*(len(lats)-1))]/1000,2), latMaxS=round(max(lats)/1000,2),
            promptTokMean=round(st.mean(r['promptTokens'] for r in rs)), outTokMean=round(st.mean([r['outTokens'] for r in ok] or [0])),
            peakMB=round(max(r['peakMB'] for r in rs)))
    res = {'all': agg(rows), 'en': agg([r for r in rows if r['lang']=='E']), 'hi': agg([r for r in rows if r['lang']=='H'])}
    return res

def score_set(path):
    recs = [json.loads(l) for l in open(path) if json.loads(l)['task']=='setreq']
    rows = []
    for r in recs:
        g = SET[r['item']]
        row = dict(item=r['item'], ok=r['ok'], err=r.get('errorKind'), latency=r['latencyMs'])
        if r['ok']:
            o = json.loads(r['output'])
            if 'minutes' in o:  # v2 schema -> v1 filter struct (deterministic mapper)
                e = o.get('energy', 'any')
                o = dict(targetMinutes=o['minutes'], songCount=o['songCount'], minProficiency=o['minProficiency'],
                         energyMin=4 if e == 'high' else None, energyMax=2 if e == 'low' else None,
                         openerEnergy=o['opener'], closer=o['closer'], includeTags=o['includeTags'],
                         excludeTags=o['excludeTags'], keys=o['keys'], tempoMinBPM=o['minBPM'], tempoMaxBPM=o['maxBPM'])
            # deterministic normalisation of no-op values (what the app's mapper would do)
            for f in ('targetMinutes','songCount','tempoMinBPM','tempoMaxBPM'):
                if o.get(f) == 0: o[f] = None
            if o.get('energyMin') == 1: o['energyMin'] = None
            if (o.get('tempoMaxBPM') or 0) >= 250: o['tempoMaxBPM'] = None
            if o.get('energyMax') == 5: o['energyMax'] = None
            for f in ('includeTags','excludeTags','keys'):
                if o.get(f): o[f] = sorted(set(o[f]))
            fields_ok = 0; wrong = []
            for f, d in DEFAULTS.items():
                v = o.get(f, d)
                exp = g.get(f, d)
                if isinstance(d, list):
                    alts = exp if (exp and isinstance(exp[0], list)) else [exp]
                    good = any(sorted(v or []) == sorted(a) for a in alts)
                else:
                    alts = exp if isinstance(exp, tuple) else (exp,)
                    good = v in alts
                fields_ok += good
                if not good: wrong.append(f"{f}={v}")
            row.update(fieldsOk=fields_ok, fields=len(DEFAULTS), exact=fields_ok==len(DEFAULTS), wrong=wrong)
        rows.append(row)
    return rows

def summarize_set(rows):
    ok = [r for r in rows if r['ok']]
    lats = sorted(r['latency'] for r in ok) or [0]
    errs = defaultdict(int)
    for r in rows:
        if not r['ok']: errs[r['err']] += 1
    return dict(n=len(rows), ok=len(ok), errors=dict(errs), exact=sum(r['exact'] for r in ok),
        fieldAcc=round(100*sum(r['fieldsOk'] for r in ok)/max(1,sum(r['fields'] for r in ok)),1),
        latMedianS=round(st.median(lats)/1000,2), latP90S=round(lats[int(0.9*(len(lats)-1))]/1000,2), latMaxS=round(max(lats)/1000,2))

if __name__ == '__main__':
    for p in sys.argv[1:]:
        recs = [json.loads(l) for l in open(p) if '"warmup"' not in l]
        if not recs: continue
        print('==', p)
        if recs[0]['task'] == 'paste':
            rows = score_paste(p)
            for k, v in summarize_paste(rows).items(): print(' ', k, v)
            if '-v' in sys.argv[0:1] or True:
                for r in rows:
                    if r['ok'] and (r['labelCorrect'] != r['blocksGold'] or not (r['title'] and r['artist'] and r['key'])):
                        o = r['out']; print('   ', r['item'], f"{r['labelCorrect']}/{r['blocksGold']}", [b['label'][:4] for b in o['blocks']], o.get('title'), '|', o.get('artist'), '|', o.get('key'))
        elif recs[0]['task'] == 'setreq':
            rows = score_set(p)
            print(' ', summarize_set(rows))
            for r in rows:
                if r['ok'] and not r['exact']: print('   ', r['item'], r['wrong'])
                if not r['ok']: print('   ', r['item'], r['err'])
