"""Actual campaign views with one initial station and isolated preview profiles."""
import json,os,subprocess,tempfile,hashlib
from pathlib import Path
project=Path(__file__).resolve().parents[1]
output=Path(os.environ['CAMPAIGN_EARLY_OUTPUT']);output.mkdir(parents=True,exist_ok=True)
scratch=Path(tempfile.mkdtemp(prefix='ge-campaign-early-'))
source=project/'data/venues.json';venues=json.loads(source.read_text())['venues'];manifest=[]
for venue in venues:
 vid=venue['id'];env=os.environ.copy();env['XDG_DATA_HOME']=str(scratch/vid);env['GRAND_EXHIBIT_TEST_RUN']='1'
 with (output/(vid+'.log')).open('w') as log:
  result=subprocess.run(['/data/opt/godot/godot441','--path',str(project),'-s','tools/shot.gd','--','venue='+vid,'sim=30','warm=3','out='+str(output/(vid+'.png'))],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 print(vid,result.returncode,flush=True)
 if result.returncode:raise SystemExit(result.returncode)
 manifest.append(dict(venue=vid,name=venue.get('name',vid),file=vid+'.png',sha256=hashlib.sha256((output/(vid+'.png')).read_bytes()).hexdigest()))
(output/'capture-manifest.json').write_text(json.dumps(dict(venue_data_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),mode='Single-desk initial venue state; no granted upgrades/cash; 30 simulated seconds then 3 seconds native rendering. Preview selects the venue directly in an isolated profile, not a full campaign playthrough.',captures=manifest),indent=2)+'\n')
