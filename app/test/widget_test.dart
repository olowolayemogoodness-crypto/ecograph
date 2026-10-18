import 'package:flutter_test/flutter_test.dart';
import 'package:ecograph_app/eco_api.dart';
import 'package:ecograph_app/theme.dart';

void main() {
  test('a queue row parses and defaults to open', () {
    final c = CaseSummary({
      'id': 'CASE-1',
      'title': 'Linked scheme around P-07, P-19',
      'band': 'freeze',
      'suggested': 'freeze',
      'score': 0.985,
      'credits_at_risk': 4,
      'tonnes_at_risk': 1140,
      'projects': ['P-07', 'P-19'],
      'types': ['loop'],
    });
    expect(c.id, 'CASE-1');
    expect(c.status, 'open');
    expect(c.score, closeTo(0.985, 1e-9));
    expect(c.projects, ['P-07', 'P-19']);
  });

  test('a case detail keeps flagged links and the credits a freeze would mark', () {
    final d = CaseDetail({
      'id': 'CASE-1',
      'title': 'Linked scheme',
      'band': 'freeze',
      'suggested': 'freeze',
      'score': 0.9,
      'signals': [
        {'signal': 'double_retirement', 'weight': 0.9, 'why': 'The same credit was retired twice.'},
      ],
      'evidence': {
        'nodes': [
          {'id': 'P-19', 'kind': 'project', 'label': 'P-19', 'x': 0.5, 'y': 0.5, 'flag': true},
        ],
        'edges': [
          {'a': 'CR-1', 'b': 'P-19', 'rel': 'ISSUED_FOR', 'flag': true},
        ],
      },
      'trace': [
        {'tool': 'find_double_retirements', 'cypher': 'MATCH (c:Credit) RETURN c', 'detail': '1 credit'},
      ],
      'findings': [],
      'at_risk_ids': ['CR-1'],
    });
    expect(d.edges.single.flag, isTrue);
    expect(d.nodes.single.flag, isTrue);
    expect(d.nodes.single.sub, '');
    expect(d.atRiskIds, ['CR-1']);
    expect(d.signals.single.weight, 0.9);
  });

  test('an agent proposal rides along with the case, and a case with none has null', () {
    final base = {
      'id': 'CASE-1',
      'title': 'Linked scheme',
      'band': 'freeze',
      'suggested': 'freeze',
      'score': 0.9,
    };
    expect(CaseSummary(base).proposal, isNull);
    final withNote = CaseSummary({
      ...base,
      'proposal': {'action': 'freeze', 'rationale': 'Double retirement (0.90) and a loop (0.55).', 'by': 'agent', 'at': '2026-10-18 09:00 UTC'},
    });
    expect(withNote.proposal, isNotNull);
    expect(withNote.proposal!.action, 'freeze');
    expect(withNote.proposal!.rationale, contains('Double retirement'));
  });

  test('the audit log remembers what the agent had proposed', () {
    final a = AuditEntry({'log': 'LOG-1', 'case': 'CASE-1', 'action': 'refer', 'at': '2026-10-18 09:05 UTC', 'by': 'human', 'proposed': 'freeze', 'credits_frozen': 0});
    expect(a.proposed, 'freeze');
    final b = AuditEntry({'log': 'LOG-2', 'case': 'CASE-2', 'action': 'freeze', 'at': '2026-10-18 09:06 UTC', 'by': 'human', 'credits_frozen': 4});
    expect(b.proposed, '');
  });

  test('numbers and dates read the way the design shows them', () {
    expect(fmtInt(27880), '27,880');
    expect(fmtInt(950), '950');
    expect(fmtWhen('2026-07-04 15:14 UTC'), '4 JUL 2026 · 15:14 UTC');
  });
}
