"""Isolated actual-game overview and motion captures for the twelve public courts."""
import json, os, subprocess, tempfile
from pathlib import Path
project=Path(__file__).resolve().parents[1]
output=Path(os.environ.get('PUBLIC_PLAZA_OUTPUT',str(project.parent/'evidence/outdoor-life-2026-09-07')))
output.mkdir(parents=True,exist_ok=True)
scratch=Path(tempfile.mkdtemp(prefix='ge-plaza-captures-'))
for venue in json.loads((project/'data/venues.json').read_text())['venues']:
 vid=venue['id']
 if os.environ.get('PUBLIC_PLAZA_VENUES') and vid not in os.environ['PUBLIC_PLAZA_VENUES'].split(','):continue
 env=os.environ.copy();env['XDG_DATA_HOME']=str(scratch/vid);env['GRAND_EXHIBIT_TEST_RUN']='1'
 with (output/(vid+'-capture.log')).open('w') as log:
  result=subprocess.run(['/data/opt/godot/godot441','--path',str(project),'-s','tools/shot.gd','--','venue='+vid,'cash=1e30','levels=8','sim=30','warm=3','out='+str(output/(vid+'.png')),'out2='+str(output/(vid+'-motion.png')),'at2=5.5'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 print(vid,result.returncode,flush=True)
 if result.returncode:raise SystemExit(result.returncode)
