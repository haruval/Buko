"""Transparent review of two lexical-rubric limitations; never alter raw reports.

Declared after the first complete run, before its repeat: 'instance' is an
acceptable use/example role, and explicit syntax plans locate their subject in
targets rather than the optional inferred-subject field. This is not an
independent human or held-out semantic evaluation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import statistics

def review(corpus_path, report_path):
    data = Path(corpus_path).read_bytes()
    cases = {x['id']: x for x in json.loads(data)['cases']}
    report = json.loads(Path(report_path).read_text())
    if report['corpusSHA256'] != hashlib.sha256(data).hexdigest():
        raise ValueError('Corpus hash mismatch')
    rows = report['records']
    expected = {(name, candidate) for name in cases for candidate in (False, True)}
    observed = [(r['id'], r['candidate']) for r in rows]
    if len(observed) != len(expected) or set(observed) != expected:
        raise ValueError('Require exactly one complete paired run')
    reviewed = []
    for row in rows:
        item = cases[row['id']]
        passed = row['passed']
        reasons = []
        if not passed and not item['clarify'] and not row.get('error') and not row.get('clarification'):
            gap = row.get('gap', {})
            subjects = [s['quote'].lower() for s in gap.get('subjects', [])]
            if not subjects and row.get('bindingStrategy') == 'explicitSyntax':
                subjects = [s['quote'].lower() for s in gap.get('targets', [])]
                reasons.append('explicit target is the subject anchor')
            needs = ' '.join(gap.get('informationNeeds', [])).lower()
            need_ok = any(n.lower() in needs for n in item['needs'])
            if not need_ok and any(n in ('use', 'application', 'example') for n in item['needs']) and 'instance' in needs:
                need_ok = True
                reasons.append('instance is a valid use/example role')
            passed = (len(subjects) == len(item['subjects']) and
                all(any(name.lower() in subject for subject in subjects) for name in item['subjects']) and need_ok)
        reviewed.append({'id':row['id'],'candidate':row['candidate'],'rawPassed':row['passed'],
            'reviewedPassed':passed,'overrideReasons':reasons if passed and not row['passed'] else [],
            'seconds':row['seconds'],'expectedClarification':item['clarify']})
    summary = {}
    for kind in (False, True):
        subset = [r for r in reviewed if r['candidate']==kind]
        summary['candidate' if kind else 'current'] = {
            'rawPasses':sum(r['rawPassed'] for r in subset),'reviewedPasses':sum(r['reviewedPassed'] for r in subset),
            'cases':len(subset),'positivePasses':sum(r['reviewedPassed'] for r in subset if not r['expectedClarification']),
            'positiveCases':sum(not r['expectedClarification'] for r in subset),
            'clarificationPasses':sum(r['reviewedPassed'] for r in subset if r['expectedClarification']),
            'clarificationCases':sum(r['expectedClarification'] for r in subset),
            'hostMedianSeconds':statistics.median(r['seconds'] for r in subset)}
    index = {(r['id'],r['candidate']):r['reviewedPassed'] for r in reviewed}
    return {'formatVersion':1,'scope':__doc__,'corpusSHA256':report['corpusSHA256'],
        'reportSHA256':hashlib.sha256(Path(report_path).read_bytes()).hexdigest(),
        'summary':summary, 'gains':[k for k in cases if index[k,True] and not index[k,False]],
        'regressions':[k for k in cases if index[k,False] and not index[k,True]],'rows':reviewed}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for flag in ('corpus','report','output'):parser.add_argument('--'+flag,required=True)
    args=parser.parse_args()
    path=Path(args.output)
    if path.exists():raise ValueError('Use a new report path')
    result=review(args.corpus,args.report)
    path.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result['summary'],indent=2))
