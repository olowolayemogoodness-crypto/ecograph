// ignore_for_file: use_super_parameters, use_null_aware_elements
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;

const _apiEnv = String.fromEnvironment('ECO_API');

String _defaultBase() {
  if (kIsWeb) {
    // Served by the API itself (the deployed demo): same origin. Local `flutter run -d chrome`: the API on this machine.
    final host = Uri.base.host;
    return (host.isEmpty || host == 'localhost' || host == '127.0.0.1') ? 'http://127.0.0.1:8000' : Uri.base.origin;
  }
  // The Android emulator reaches the host machine at 10.0.2.2; the iOS simulator shares the Mac's localhost.
  return defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
}

/// Where the API lives. Override with `--dart-define=ECO_API=https://your-server`.
String get apiBase => _apiEnv.isNotEmpty ? _apiEnv : _defaultBase();
const apiToken = String.fromEnvironment('ECO_TOKEN', defaultValue: '');

class ApiException implements Exception {
  final int status;
  final String message;
  final bool unavailable;
  ApiException(this.status, this.message, {this.unavailable = false});
  @override
  String toString() => message;
}

class Signal {
  final String signal, why;
  final double weight;
  Signal(Map<String, dynamic> j)
      : signal = j['signal'],
        why = j['why'],
        weight = (j['weight'] as num).toDouble();
}

class EvNode {
  final String id, kind, label, sub;
  final bool flag;
  final double x, y;
  EvNode(Map<String, dynamic> j)
      : id = j['id'],
        kind = j['kind'],
        label = j['label'],
        sub = j['sub'] ?? '',
        flag = j['flag'] == true,
        x = (j['x'] as num).toDouble(),
        y = (j['y'] as num).toDouble();
}

class EvEdge {
  final String a, b, rel;
  final String? label;
  final bool flag;
  EvEdge(Map<String, dynamic> j)
      : a = j['a'],
        b = j['b'],
        rel = j['rel'],
        label = j['label'],
        flag = j['flag'] == true;
}

class TraceStep {
  final String tool, cypher, detail;
  TraceStep(Map<String, dynamic> j)
      : tool = j['tool'],
        cypher = j['cypher'] ?? '',
        detail = j['detail'] ?? '';
}

/// What the agent recommended on a case. It is a note for the reviewer: only a person can act on it.
class Proposal {
  final String action, rationale, at;
  Proposal(Map<String, dynamic> j)
      : action = (j['action'] ?? '').toString(),
        rationale = (j['rationale'] ?? '').toString(),
        at = (j['at'] ?? '').toString();
}

class CaseSummary {
  final String id, title, band, suggested, summary, status;
  final String? note, decidedAt;
  final double score;
  final List<String> types, projects;
  final int creditsAtRisk, tonnesAtRisk, creditsFrozen;
  final Proposal? proposal;
  CaseSummary(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'],
        band = j['band'],
        suggested = j['suggested'],
        summary = j['summary'] ?? '',
        status = j['status'] ?? 'open',
        note = j['note'],
        decidedAt = j['decided_at'],
        score = (j['score'] as num).toDouble(),
        types = List<String>.from(j['types'] ?? []),
        projects = List<String>.from(j['projects'] ?? []),
        creditsAtRisk = (j['credits_at_risk'] ?? 0) as int,
        tonnesAtRisk = (j['tonnes_at_risk'] ?? 0) as int,
        creditsFrozen = (j['credits_frozen'] ?? 0) as int,
        proposal = j['proposal'] is Map ? Proposal(Map<String, dynamic>.from(j['proposal'] as Map)) : null;
}

class CaseDetail extends CaseSummary {
  final List<Signal> signals;
  final List<EvNode> nodes;
  final List<EvEdge> edges;
  final List<TraceStep> trace;
  final String howToRead;
  final List<Map<String, dynamic>> findings;
  final List<String> atRiskIds;
  CaseDetail(Map<String, dynamic> j)
      : findings = List<Map<String, dynamic>>.from(j['findings'] ?? []),
        signals = (j['signals'] as List).map((e) => Signal(e)).toList(),
        nodes = (j['evidence']['nodes'] as List).map((e) => EvNode(e)).toList(),
        edges = (j['evidence']['edges'] as List).map((e) => EvEdge(e)).toList(),
        trace = (j['trace'] as List).map((e) => TraceStep(e)).toList(),
        howToRead = j['how_to_read'] ?? '',
        atRiskIds = List<String>.from(j['at_risk_ids'] ?? []),
        super(j);
}

/// What the server returns after a person decides.
class DecisionResult {
  final CaseDetail detail;
  final String log, at, status, proposed;
  final int creditsFrozen;
  DecisionResult(Map<String, dynamic> j)
      : detail = CaseDetail(j['case']),
        log = (j['log'] ?? '').toString(),
        at = (j['at'] ?? '').toString(),
        status = (j['status'] ?? '').toString(),
        proposed = (j['proposed'] ?? '').toString(),
        creditsFrozen = (j['credits_frozen'] ?? 0) as int;
}

class AuditEntry {
  final String log, caseId, action, at, by, proposed;
  final String? note;
  final int creditsFrozen;
  AuditEntry(Map<String, dynamic> j)
      : log = (j['log'] ?? '').toString(),
        caseId = (j['case'] ?? '').toString(),
        action = (j['action'] ?? '').toString(),
        at = (j['at'] ?? '').toString(),
        by = (j['by'] ?? '').toString(),
        proposed = (j['proposed'] ?? '').toString(),
        note = j['note'],
        creditsFrozen = (j['credits_frozen'] ?? 0) as int;
}

class AskResult {
  final String answer;
  final List<TraceStep> calls;
  AskResult(Map<String, dynamic> j)
      : answer = j['answer'],
        calls = (j['calls'] as List).map((e) => TraceStep({'tool': e['tool'], 'cypher': e['cypher'], 'detail': e['detail']})).toList();
}

class EcoApi {
  final http.Client _c;
  EcoApi([http.Client? c]) : _c = c ?? http.Client();

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (apiToken.isNotEmpty) 'Authorization': 'Bearer $apiToken',
      };

  Future<Map<String, dynamic>> _go(Future<http.Response> f) async {
    final http.Response r;
    try {
      r = await f.timeout(const Duration(seconds: 45));
    } catch (_) {
      throw ApiException(0, 'Cannot reach the server at $apiBase. Is it running?');
    }
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode, body['error']?.toString() ?? 'Request failed (${r.statusCode})',
          unavailable: body['unavailable'] == true);
    }
    return body;
  }

  Uri _u(String p) => Uri.parse('$apiBase$p');

  Future<Map<String, dynamic>> health() => _go(_c.get(_u('/api/health'), headers: _h));

  Future<Map<String, dynamic>> overview() => _go(_c.get(_u('/api/overview'), headers: _h));

  Future<List<CaseSummary>> cases() async =>
      ((await _go(_c.get(_u('/api/cases'), headers: _h)))['cases'] as List).map((e) => CaseSummary(e)).toList();

  Future<CaseDetail> caseDetail(String id) async => CaseDetail(await _go(_c.get(_u('/api/cases/$id'), headers: _h)));

  /// action: freeze | refer | dismiss. Returns the refreshed case and the audit log entry.
  Future<DecisionResult> decide(String id, String action, {String note = ''}) async =>
      DecisionResult(await _go(_c.post(_u('/api/cases/$id/decision'), headers: _h, body: jsonEncode({'action': action, 'note': note}))));

  /// Rebuilds the synthetic ledger and clears every decision (the demo reset).
  Future<void> reset() async {
    await _go(_c.post(_u('/api/reset'), headers: _h, body: '{}'));
  }

  Future<Map<String, dynamic>> creditTrace(String id) => _go(_c.get(_u('/api/credits/$id'), headers: _h));

  Future<List<AuditEntry>> auditLog() async =>
      ((await _go(_c.get(_u('/api/actions'), headers: _h)))['actions'] as List).map((e) => AuditEntry(e)).toList();

  Future<AskResult> ask(String question, {String? caseId}) async =>
      AskResult(await _go(_c.post(_u('/api/ask'), headers: _h, body: jsonEncode({'question': question, if (caseId != null) 'case_id': caseId}))));
}
