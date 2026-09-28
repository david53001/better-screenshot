import json,sys
import os; rows=json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'out/results.json')))
def stat(rs):
    return f"{sum(r['pass'] for r in rs)}/{len(rs)} · CER {sum(r['cer'] for r in rs)/max(len(rs),1):.3f}"
orig=[r for r in rows if r['id'][0] not in 'HN']
held=[r for r in rows if r['id'][0]=='H']
nh=[r for r in rows if r['id'][0]=='N']
print("existing", stat(orig), "| held-out", stat(held), "| no-harm", stat(nh))
for r in rows:
    if len(sys.argv)>1 and r['id'] in sys.argv[1:]:
        print(f"--- {r['id']} {'PASS' if r['pass'] else 'FAIL'} CER {r['cer']:.3f}\n  exp: {r['expected']!r}\n  act: {r.get('actual')!r}")
