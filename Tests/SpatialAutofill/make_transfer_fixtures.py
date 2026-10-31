"""Additional development transfer controls, frozen separately from the original 20."""
import argparse
import hashlib
import json
from pathlib import Path

def create(path):
    cases=[]
    def add(id,text,rects,context='',subjects=(),needs=(),clarify=False,pages=None):
        cases.append(dict(id=id,selected=text,context=context,subjects=list(subjects),needs=list(needs),clarify=clarify,
            lines=[dict(blockID=f'S{i+1}',text=line,page=(pages or ['p1']*len(rects))[i],rect=rects[i]) for i,line in enumerate(text.splitlines())]))
    left=[60,100,370,25];right=[560,100,370,25];below_left=[80,140,350,25];below_right=[580,140,350,25]
    add('transfer-energy','A solar cell converts light into electricity.\nA turbine converts wind into electricity.\nA rooftop panel powers a lamp.',[left,right,below_left],'Give a concrete application alongside each description.',['turbine'],['application','use','example'])
    add('transfer-energy-moved','A solar cell converts light into electricity.\nA turbine converts wind into electricity.\nAn offshore rotor powers a village.',[left,right,below_right],'Give a concrete application alongside each description.',['solar cell'],['application','use','example'])
    add('transfer-ranges','Rilo measures distances.\nPavo measures distances.\nRange: thirty meters.',[left,right,below_left],'Record purpose and measurement range for each instrument.',['Pavo'],['range'])
    add('transfer-pages','Rilo measures distances.\nPavo measures distances.\nRange: thirty meters.',[left,right,below_right],'Record purpose and measurement range for each instrument.',['Rilo'],['range'],pages=['p1','p2','p2'])
    add('transfer-wrapped','A sieve separates particles by size.\nA magnet separates magnetic material.\nRemove pebbles\nfrom garden soil.',[left,right,below_left,[80,180,350,25]],'Give a practical use for each tool.',['magnet'],['use','example','application'])
    add('transfer-same-row-multiple-roles','A sieve separates particles by size. Remove pebbles from soil.\nA magnet separates magnetic material.',[left,right],'Give a practical use alongside each description.',['magnet'],['use','example','application'])
    add('transfer-complete','Rilo measures distances. Range: thirty meters.\nPavo measures distances. Range: ten meters.',[left,right],'Record purpose and measurement range for each instrument.',clarify=True)
    add('transfer-conflict','Rilo measures distances.\nPavo measures distances.\nPavo range: thirty meters.',[left,right,below_left],'Record purpose and measurement range for each instrument.',clarify=True)
    add('transfer-shared','Rilo measures distances.\nPavo measures distances.\nRange: thirty meters.',[left,right,[60,140,870,25]],'Record purpose and measurement range for each instrument.',clarify=True)
    add('transfer-no-cue','Rilo measures distances.\nPavo measures distances.',[left,right],clarify=True)
    add('transfer-direct-question','How many chambers does Luma have?\nNeral has four chambers.',[left,right],subjects=['Luma'],needs=['number','count','chamber'])
    add('transfer-two-incomplete','Rilo measures distances. Range: thirty meters.\nPavo measures distances.\nTuro measures distances.',[left,right,[560,350,370,25]],'Record purpose and measurement range for each instrument.',clarify=True)
    data=(json.dumps(dict(formatVersion=1,partition='Additional assistant-authored development controls, not held-out',cases=cases),indent=2)+'\n').encode()
    with Path(path).open('xb') as f:f.write(data)
    print(len(cases),hashlib.sha256(data).hexdigest())
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',required=True);create(p.parse_args().output)
