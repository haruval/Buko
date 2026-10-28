"""Freeze synthetic layout probes before observing candidate outputs. No real ink claim."""
import argparse
import hashlib
import json
from pathlib import Path

def create(output):
    output = Path(output)
    if output.exists():
        raise ValueError('Choose a new output')
    cases = []
    def add(identifier, text, rects, context='', subjects=(), needs=(), clarify=False, pages=None):
        lines = text.splitlines()
        cases.append(dict(id=identifier, selected=text, context=context,
            lines=[dict(blockID=f'S{i+1}', text=s, page=(pages or ['p1']*len(lines))[i], rect=rects[i]) for i,s in enumerate(lines)],
            subjects=list(subjects), needs=list(needs), clarify=clarify))
    for arrangement in ('columns', 'rows'):
        for owner in ('Luma','Neral'):
            rects = [[80,100,300,25],[580,100,300,25],[100 if owner=='Luma' else 600,140,280,25]] if arrangement=='columns' else [[80,100,300,25],[80,350,300,25],[100,140 if owner=='Luma' else 390,280,25]]
            add(f'{arrangement}-{owner.lower()}', 'Luma buffers inputs.\nNeral buffers inputs.\nCapacity: eight entries.', rects,
                'For each component, record its purpose and capacity.', ['Neral' if owner=='Luma' else 'Luma'], ['capacity','limit','entries'])
    add('transfer-uses-right', 'A conductor lets current flow.\nAn insulator resists current flow.\nRubber coats wires to protect people.',
        [[60,100,370,25],[560,100,370,25],[580,140,350,25]], 'Give a use alongside each meaning.', ['conductor'], ['use','application','example'])
    add('transfer-uses-left', 'A conductor lets current flow.\nAn insulator resists current flow.\nCopper wiring carries current in a lamp.',
        [[60,100,370,25],[560,100,370,25],[80,140,350,25]], 'Give a use alongside each meaning.', ['insulator'], ['use','application','example'])
    add('wrapped-example', 'A queue serves items in arrival order.\nA stack serves the newest item first.\nA printer handles\nwaiting jobs this way.',
        [[60,100,370,25],[560,100,370,25],[80,140,350,25],[80,180,350,25]], 'Give a concrete use for each structure.', ['stack'], ['use','example','application'])
    add('three-groups', 'A stack serves the newest item first.\nA queue serves items in arrival order.\nPrinters use queues for waiting jobs.\nA set keeps distinct items. A guest list uses a set to avoid duplicates.',
        [[60,100,370,25],[60,350,370,25],[80,390,350,25],[560,100,370,25]], 'Give a use alongside each meaning.', ['stack'], ['use','example','application'])
    add('processes', 'Condensation changes vapor into liquid.\nEvaporation changes liquid into vapor.\nA cold glass gets wet.',
        [[560,100,370,25],[60,100,370,25],[580,140,350,25]], 'Pair each process with an everyday situation.', ['Evaporation'], ['situation','example','instance'])
    add('limit-transfer', 'Vexa tracks requests.\nTovin tracks requests.\nLimit: six pending requests.',
        [[560,100,370,25],[60,100,370,25],[580,140,350,25]], 'Record what each component does and its limit.', ['Tovin'], ['limit','capacity','requests'])
    add('complete-capacities', 'Luma buffers inputs. Capacity: eight entries.\nNeral buffers inputs. Capacity: five entries.',
        [[60,100,370,25],[560,100,370,25]], 'For each component, record its purpose and capacity.', clarify=True)
    add('complete-uses', 'A conductor lets current flow. Copper wiring carries current in a lamp.\nAn insulator resists current flow. Rubber coats wires to protect people.',
        [[60,100,370,25],[560,100,370,25]], 'Give a use alongside each meaning.', clarify=True)
    add('shared-annotation', 'Luma buffers inputs.\nNeral buffers inputs.\nCapacity: eight entries.',
        [[60,100,370,25],[560,100,370,25],[60,140,870,25]], 'For each component, record its purpose and capacity.', clarify=True)
    add('two-incomplete', 'Luma buffers inputs. Capacity: eight entries.\nNeral buffers inputs.\nVexa buffers inputs.',
        [[60,100,370,25],[60,350,370,25],[560,100,370,25]], 'For each component, record its purpose and capacity.', clarify=True)
    add('duplicate-annotation', 'Luma buffers inputs.\nNeral buffers inputs.\nCapacity: eight entries.\nCapacity: eight entries.',
        [[60,100,370,25],[560,100,370,25],[80,140,350,25],[580,140,350,25]], 'For each component, record its purpose and capacity.', clarify=True)
    add('text-geometry-conflict', 'Luma buffers inputs.\nNeral buffers inputs.\nNeral capacity: eight entries.',
        [[60,100,370,25],[560,100,370,25],[80,140,350,25]], 'For each component, record its purpose and capacity.', clarify=True)
    add('page-boundary', 'Luma buffers inputs.\nNeral buffers inputs.\nCapacity: eight entries.',
        [[60,100,370,25],[560,100,370,25],[80,140,350,25]], 'For each component, record its purpose and capacity.', clarify=True, pages=['p1','p1','p2'])
    add('explicit-question', 'How many chambers does Luma have?', [[60,100,600,25]], subjects=['Luma'], needs=['number','count','chamber'])
    add('already-complete-no-cue', 'A closure captures variables from its lexical environment.', [[60,100,700,25]], clarify=True)
    add('explicit-missing-heading', 'Lexical analysis: groups characters into tokens.\nParsing:', [[60,100,700,25],[60,150,700,25]], subjects=['Parsing'], needs=['definition'])
    payload={'formatVersion':1,'partition':'assistant-authored development; paired synthetic geometry, not held-out or recognition accuracy','cases':cases}
    output.write_text(json.dumps(payload,indent=2)+'\n')
    print(len(cases),'cases',hashlib.sha256(output.read_bytes()).hexdigest())

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True)
    create(parser.parse_args().output)
