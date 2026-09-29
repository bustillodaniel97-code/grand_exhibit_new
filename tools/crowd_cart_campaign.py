#!/usr/bin/env python3
"""Run live-crowd cases in isolated saves; retain per-venue evidence, not just a green summary."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--seconds', type=float, default=300)
parser.add_argument('--jobs', type=int, default=2)
parser.add_argument('--godot', default='/data/opt/godot/godot441')
parser.add_argument('--venues', nargs='*')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
venues = args.venues or [v['id'] for v in json.loads((repo/'game/data/venues.json').read_text())['venues']]

def run(venue):
    report = out/f'{venue}.json'
    with tempfile.TemporaryDirectory(prefix=f'ge-crowd-{venue}-') as saves:
        env = dict(os.environ, XDG_DATA_HOME=saves, GRAND_EXHIBIT_TEST_RUN='1')
        command = [args.godot, '--headless', '--path', str(repo/'game'), '--script',
                   'res://tools/cart_traffic_probe.gd', '--', venue, str(report), str(args.seconds)]
        try:
            with (out/f'{venue}.log').open('w') as log:
                completed = subprocess.run(command, cwd=repo, env=env, stdout=log,
                                           stderr=subprocess.STDOUT, timeout=1200)
            result = json.loads(report.read_text()) if report.exists() else {}
            summary = {'venue': venue, 'exit_code': completed.returncode,
                       'seconds': args.seconds, 'served': result.get('served'),
                       'deposits': result.get('deposits'),
                       'cart_overlaps': result.get('cart_overlap_samples'),
                       'visitor_overlaps': result.get('visitor_overlap_samples'),
                       'porters': result.get('final_porters', []), 'report': str(report)}
            summary['runtime_errors'] = sum(1 for line in (out/f'{venue}.log').read_text().splitlines() if 'ERROR:' in line)
            summary['observed_service_with_clearance'] = (
                completed.returncode == 0 and summary['runtime_errors'] == 0 and bool(result) and result['served'] > 0
                and result['deposits'] > 0 and result['cart_overlap_samples'] == 0
                and result['visitor_overlap_samples'] == 0)
        except subprocess.TimeoutExpired:
            summary = {'venue': venue, 'timeout': True, 'observed_service_with_clearance': False}
    print(json.dumps(summary), flush=True)
    return summary

results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, min(args.jobs, 4))) as pool:
    for future in concurrent.futures.as_completed([pool.submit(run, v) for v in venues]):
        results.append(future.result())
        (out/'summary.json').write_text(json.dumps(results, indent=2))
# This only establishes sampled clearance and some service for each venue.
# It does not establish per-station fairness, throughput targets or phone FPS.
raise SystemExit(0 if all(r['observed_service_with_clearance'] for r in results) else 1)
