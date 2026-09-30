"""Compare reviewed G2 images without silently accepting new output."""
import argparse
import hashlib
import json
import re
import math
from pathlib import Path
from PIL import Image, ImageChops

CHANNEL_TOLERANCE = 8
MAX_OUTLIER_RATIO = .005
MAX_GEOMETRY_DELTA = 1.0

def compare(expected, actual, expected_geometry=None, actual_geometry=None):
    errors = []
    if expected.size != actual.size:
        return {'passed':False,'outlierRatio':None,'geometryFailures':['image dimensions differ']}
    delta = ImageChops.difference(expected.convert('RGBA'),actual.convert('RGBA'))
    channels = delta.split()
    maximum = channels[0]
    for channel in channels[1:]: maximum = ImageChops.lighter(maximum,channel)
    outliers = sum(maximum.histogram()[CHANNEL_TOLERANCE+1:])
    ratio = outliers / (expected.width * expected.height)
    if expected_geometry is not None:
        actual_geometry = actual_geometry or {}
        if expected_geometry.keys() != actual_geometry.keys(): errors.append('control inventory differs')
        for key,bounds in expected_geometry.items():
            current = actual_geometry.get(key)
            if current is None or len(bounds) != len(current) or any(abs(a-b)>MAX_GEOMETRY_DELTA for a,b in zip(bounds,current)):
                errors.append(key)
    return {'passed':ratio<=MAX_OUTLIER_RATIO and not errors,'outlierRatio':ratio,'geometryFailures':errors}

def sha256(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def semantic_facts(path):
    text = Path(path).read_text(encoding='utf-8')
    if 'SemanticsNode' not in text: return []
    facts=[]
    active=None
    indentation=0
    quoted=False
    for line in text.splitlines():
        content=line.lstrip(' │├└─')
        depth=len(line)-len(content)
        match=re.match(r'(label|tooltip|value|hint|actions|flags|textDirection|inputType):\s*(.*)',content)
        if match and not (quoted and depth>indentation):
            active=match.group(1)
            indentation=depth
            facts.append((active,match.group(2).strip()))
            quoted=active in ('label','tooltip','value','hint') and len(re.findall(r'(?<!\\)"',match.group(2)))%2==1
        elif (active and content and depth>indentation
              and 'SemanticsNode#' not in content
              and (quoted or not re.match(r'\w+:',content))):
            # Flutter's diagnostics wrap flags and put merged text labels on
            # indented following lines. Those words are accessibility evidence.
            separator=' ' if active in ('flags','actions') else '\n'
            previous=facts[-1][1]
            facts[-1]=(active,previous+(separator if previous else '')+content.strip())
            if active in ('label','tooltip','value','hint') and len(re.findall(r'(?<!\\)"',content))%2==1:
                quoted=not quoted
        else:
            active=None
            quoted=False

    return facts

def valid_geometry(value):
    return isinstance(value,dict) and bool(value) and all(
        isinstance(bounds,list) and len(bounds)==4 and all(isinstance(n,(int,float)) and math.isfinite(n) for n in bounds)
        and bounds[2]>=0 and bounds[3]>=0 for bounds in value.values())

def verify(actual_root, expected_root, review_path, output_root):
    actual_root,expected_root,output_root = map(Path,(actual_root,expected_root,output_root))
    actual = json.loads((actual_root/'manifest.json').read_text(encoding='utf-8'))
    expected = json.loads((expected_root/'manifest.json').read_text(encoding='utf-8'))
    review = json.loads(Path(review_path).read_text(encoding='utf-8'))
    output_root.mkdir(parents=True,exist_ok=True)
    by_id = {entry['id']:entry for entry in actual}
    results=[]
    environments=[directory/'environment.json' for directory in (expected_root,actual_root)]
    if any(not path.is_file() for path in environments):
        results.append({'id':'environment','passed':False,'reason':'missing frozen environment'})
    else:
        frozen,current=(json.loads(path.read_text(encoding='utf-8')) for path in environments)
        if not frozen or not frozen.get('fonts') or not frozen.get('sdk') or frozen!=current:
            results.append({'id':'environment','passed':False,'reason':'SDK/font/surface environment differs or incomplete'})
    if len(by_id)!=len(actual) or len({e['id'] for e in expected})!=len(expected) or {e['id'] for e in expected} != set(by_id):
        results.append({'id':'inventory','passed':False,'reason':'missing, additional or duplicate capture'})
    for case in expected:
        identity=case['id']; current=by_id.get(identity)
        approved=review.get(identity,{})
        expected_image=expected_root/case['image']
        if current is None or not expected_image.is_file() or approved.get('status')!='reviewed' or approved.get('sha256')!=sha256(expected_image):
            results.append({'id':identity,'passed':False,'reason':'missing image or unreviewed golden'}); continue
        actual_image=actual_root/current['image']
        if not actual_image.is_file():
            results.append({'id':identity,'passed':False,'reason':'missing actual image'}); continue
        # Comparison requires independently captured geometry and a semantics tree.
        geometry_files=[expected_root/case.get('geometry','__missing__'),actual_root/current.get('geometry','__missing__')]
        semantics_files=[expected_root/case.get('semantics','__missing__'),actual_root/current.get('semantics','__missing__')]
        if any(not path.is_file() for path in geometry_files+semantics_files):
            results.append({'id':identity,'passed':False,'reason':'missing geometry or semantics'}); continue
        geometry=[json.loads(path.read_text(encoding='utf-8')) for path in geometry_files]
        semantic=[semantic_facts(path) for path in semantics_files]
        integrity=[]
        if approved.get('geometrySha256')!=sha256(geometry_files[0]) or approved.get('semanticsSha256')!=sha256(semantics_files[0]): integrity.append('unreviewed geometry or semantics')
        if not all(valid_geometry(value) for value in geometry): integrity.append('empty or malformed control geometry')
        if not all(semantic) or semantic[0]!=semantic[1]: integrity.append('semantic labels/actions/state differ or empty')
        if any(case.get(key)!=current.get(key) for key in ('width','height','locale','textScale','fixture','keyboard','elapsedMs','clock')): integrity.append('capture configuration differs')
        with Image.open(expected_image) as before,Image.open(actual_image) as after:
            result=compare(before,after,*geometry) if all(valid_geometry(value) for value in geometry) else {'passed':False,'geometryFailures':['invalid geometry']}
            result['integrityFailures']=integrity
            result['passed']=result['passed'] and not integrity
            result['id']=identity
            if not result['passed']:
                before.save(output_root/f'{identity}-expected.png')
                after.save(output_root/f'{identity}-actual.png')
                if before.size==after.size: ImageChops.difference(before.convert('RGBA'),after.convert('RGBA')).convert('RGB').save(output_root/f'{identity}-diff.png')
            results.append(result)
    report={'passed':bool(results) and all(item['passed'] for item in results),'scope':'reviewed inventory only; not full G2 certification',
        'channelTolerance':CHANNEL_TOLERANCE,'maxOutlierRatio':MAX_OUTLIER_RATIO,'maxGeometryDelta':MAX_GEOMETRY_DELTA,'cases':results}
    (output_root/'report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('actual','expected','review','output'): parser.add_argument('--'+name,required=True)
    args=parser.parse_args()
    report=verify(args.actual,args.expected,args.review,args.output)
    print(f"Visual inventory: {'PASS' if report['passed'] else 'FAIL'} ({len(report['cases'])} cases)")
    raise SystemExit(0 if report['passed'] else 1)
