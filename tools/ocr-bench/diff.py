# Compares the last run (out/results.json) with a saved baseline and lists every case whose
# pass/fail or CER changed. Usage: python3 diff.py baselines/2026-09-28-end-of-day.json [--show]
# (--show also prints both outputs). Save a new baseline with: cp out/results.json baselines/NAME.json
import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
if len(sys.argv) < 2: sys.exit(__doc__ or "usage: diff.py BASELINE.json [--show]")
base = {r['id']: r for r in json.load(open(sys.argv[1]))}
now = {r['id']: r for r in json.load(open(os.path.join(here, 'out/results.json')))}
better = worse = 0
for k, r in now.items():
    b = base.get(k)
    if not b or (b['pass'] == r['pass'] and abs(b['cer'] - r['cer']) < 1e-6): continue
    up = (r['pass'] and not b['pass']) or (r['pass'] == b['pass'] and r['cer'] < b['cer'])
    better += up; worse += not up
    print(f"{'+' if up else '-'} {k}: {'PASS' if b['pass'] else 'fail'} {b['cer']:.3f} -> {'PASS' if r['pass'] else 'fail'} {r['cer']:.3f}")
    if '--show' in sys.argv:
        print('    was:', repr(b.get('actual'))[:240]); print('    now:', repr(r.get('actual'))[:240])
print(f"{better} better, {worse} worse")
