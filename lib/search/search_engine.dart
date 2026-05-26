import '../models/app_entry.dart';
import '../services/storage_service.dart';
import 'korean.dart';

class _Scored {
  _Scored(this.app, this.score);
  final AppEntry app;
  final double score;
}

/// Returns apps ranked by relevance for [rawQuery].
///
/// 11-tier priority (docs/ranking.md):
///   1.  exact, case+space sensitive          → 11000
///   2.  exact, case-insensitive, space-kept  → 10000
///   3.  exact, normalized (case+space strip) → 9000
///   4.  startsWith                           → 8000–8100
///   5.  word-boundary contains               → 7000–7100
///   6.  contains                             → 6000–6100
///   7.  초성                                 → 5000
///   8.  history (recency-weighted)           → 4000–4999
///   9.  QWERTY / 자판오타                    → 3000–3999
///  10.  phonetic / roman / initials          → 2000–2999
///  11.  LCS / overlap / subsequence          → 1000–1999
class SearchEngine {
  SearchEngine._();

  static List<AppEntry> search(
    String rawQuery,
    List<AppEntry> apps,
    List<HistoryEntry> history,
  ) {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];

    final q = Korean.normalize(query);
    final qRoman = Korean.romanize(query);
    final qQwerty = Korean.qwerty(query);
    final qPhonetic = Korean.phoneticKey(query);
    final chosungQuery = Korean.isChosungOnly(query);

    // Precompute history: package → most recent timestamp for matching keywords.
    final histTs = <String, double>{};
    for (final entry in history) {
      if (!_keywordMatches(query, q, chosungQuery, entry.keyword)) continue;
      for (final pkg in entry.packages) {
        final ts = entry.updatedAt.toDouble();
        if (ts > (histTs[pkg] ?? 0)) histTs[pkg] = ts;
      }
    }
    final maxTs = histTs.values.fold(0.0, (m, v) => v > m ? v : m);

    final scored = <_Scored>[];
    for (final app in apps) {
      final score = _score(
          app, query, q, qRoman, qQwerty, qPhonetic, chosungQuery, histTs, maxTs);
      if (score > 0) scored.add(_Scored(app, score));
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0
          ? c
          : a.app.label.toLowerCase().compareTo(b.app.label.toLowerCase());
    });

    return scored.map((s) => s.app).toList();
  }

  static double _score(
    AppEntry app,
    String rawQuery,
    String q,
    String qRoman,
    String qQwerty,
    String qPhonetic,
    bool chosungQuery,
    Map<String, double> histTs,
    double maxTs,
  ) {
    final label = app.labelNorm;
    final pkg = app.packageNorm;

    // Tier 1: exact, case+space sensitive
    if (app.label == rawQuery) return 11000;

    // Tier 2: exact, case-insensitive, space-sensitive
    if (app.label.toLowerCase() == rawQuery.toLowerCase()) return 10000;

    // Tier 3: exact, normalized (case+space insensitive)
    if (label == q || pkg == q) return 9000;

    // Tier 4: startsWith
    double startRatio = 0;
    if (label.startsWith(q)) startRatio = q.length / label.length;
    if (pkg.startsWith(q)) {
      final r = q.length / pkg.length;
      if (r > startRatio) startRatio = r;
    }
    if (startRatio > 0) return 8000 + startRatio * 100;

    // Tier 5: word-boundary contains (position > 0, so startsWith excluded)
    final wbLabel = _wordBoundaryRatio(label, q);
    final wbPkg = _wordBoundaryRatio(pkg, q);
    final wbRatio = wbLabel > wbPkg ? wbLabel : wbPkg;
    if (wbRatio > 0) return 7000 + wbRatio * 100;

    // Tier 6: contains
    double contRatio = 0;
    if (label.contains(q)) contRatio = q.length / label.length;
    if (pkg.contains(q)) {
      final r = q.length / pkg.length;
      if (r > contRatio) contRatio = r;
    }
    if (contRatio > 0) return 6000 + contRatio * 100;

    // Tier 7: 초성
    if (chosungQuery && app.chosung.contains(rawQuery)) return 5000;

    // Tier 8: history
    if (maxTs > 0) {
      final ts = histTs[app.packageName];
      if (ts != null) return 4000 + (ts / maxTs) * 999;
    }

    // Tier 9: QWERTY / 자판오타
    final qwertyScore = _qwertyScore(app, q, qQwerty);
    if (qwertyScore > 0) return 3000 + qwertyScore * 999;

    // Tier 10: phonetic / roman / initials
    final phoneticScore = _phoneticScore(app, q, qRoman, qPhonetic);
    if (phoneticScore > 0) return 2000 + phoneticScore * 999;

    // Tier 11: LCS / overlap / subsequence (2+ char queries)
    if (rawQuery.length >= 2) {
      final relScore = _relatedScore(app, rawQuery, q, qRoman, chosungQuery);
      if (relScore > 0) return 1000 + (relScore * 5).clamp(0, 999);
    }

    // Roman fallback: Korean query → romanize → re-score as plain English query.
    // This gives Korean input the same Tier 3–11 coverage English input gets,
    // since most app labels are Latin and Korean chars never match them directly.
    if (qRoman.isNotEmpty && qRoman != q) {
      return _scoreRoman(app, qRoman);
    }

    return 0;
  }

  // --- Tier helpers ---

  /// Ratio of [query] length to [text] length when [query] appears in [text]
  /// starting at a word boundary (position > 0). Returns 0 if no such match.
  static double _wordBoundaryRatio(String text, String query) {
    if (query.isEmpty) return 0;
    var pos = text.indexOf(query, 1); // skip pos 0 — that's startsWith (tier 4)
    while (pos > 0) {
      final prev = text[pos - 1];
      if (prev == ' ' || prev == '-' || prev == '_' || prev == '.') {
        return query.length / text.length;
      }
      pos = text.indexOf(query, pos + 1);
    }
    return 0;
  }

  /// Tier 9: query matches via QWERTY keyboard layout cross-mapping.
  static double _qwertyScore(AppEntry app, String q, String qQwerty) {
    double best = 0;

    // User typed QWERTY keys that correspond to a Korean label.
    if (q.isNotEmpty && app.qwerty.isNotEmpty) {
      if (app.qwerty == q) {
        best = 1.0;
      } else if (app.qwerty.startsWith(q)) {
        final r = 0.9 + (q.length / app.qwerty.length) * 0.09;
        if (r > best) best = r;
      } else if (app.qwerty.contains(q)) {
        final r = q.length / app.qwerty.length;
        if (r > best) best = r;
      }
    }

    // QWERTY projection of query matches label / roman / qwerty forms.
    if (qQwerty.isNotEmpty) {
      for (final af in [app.labelNorm, app.roman, app.qwerty]) {
        if (af.isEmpty) continue;
        if (af == qQwerty) {
          best = 1.0;
          break;
        } else if (af.startsWith(qQwerty)) {
          final r = 0.9 + (qQwerty.length / af.length) * 0.09;
          if (r > best) best = r;
        } else if (af.contains(qQwerty)) {
          final r = qQwerty.length / af.length;
          if (r > best) best = r;
        }
      }
    }

    return best;
  }

  /// Tier 10: romanized / phonetic / initials match.
  static double _phoneticScore(
      AppEntry app, String q, String qRoman, String qPhonetic) {
    double best = 0;

    // Romanized query vs label / roman forms.
    if (qRoman.isNotEmpty) {
      for (final af in [app.labelNorm, app.roman]) {
        if (af.isEmpty) continue;
        final at = af.indexOf(qRoman);
        if (at < 0) continue;
        final score = qRoman.length / af.length + _wordBoundaryBonus(af, at);
        if (score > best) best = score;
      }
    }

    // Fuzzy phonetic skeleton (consonant-skeleton edit distance).
    if (qPhonetic.length >= 3 && app.phonetic.length >= 2) {
      final dist = _fuzzySubstringDistance(qPhonetic, app.phonetic);
      final allowed = (qPhonetic.length ~/ 3).clamp(1, 99);
      if (dist <= allowed) {
        final fuzzy = 0.9 * (1 - dist / qPhonetic.length);
        if (fuzzy > best) best = fuzzy;
      }
    }

    // Initials / abbreviation (e.g. "gp" → "Google Play").
    if (q.length >= 2 && app.initials.length >= 2) {
      final at = app.initials.indexOf(q);
      if (at >= 0) {
        final score = (0.85 - at * 0.05).clamp(0.0, 1.0);
        if (score > best) best = score;
      }
    }

    return best;
  }

  static double _relatedScore(
    AppEntry app,
    String rawQuery,
    String q,
    String qRoman,
    bool chosungQuery,
  ) {
    final relQuery = chosungQuery ? rawQuery : q;
    final target = chosungQuery
        ? app.chosung
        : '${app.labelNorm}${app.packageNorm}';
    final lcs = _longestCommonSubstring(relQuery, target);
    final overlap = _charOverlap(relQuery, target);
    var score = (lcs * 10 + overlap).toDouble();

    if (!chosungQuery &&
        qRoman.length >= 3 &&
        _isSubsequence(qRoman, app.roman)) {
      final spread = _subsequenceSpread(qRoman, app.roman);
      final tightness =
          ((qRoman.length - 1) / (spread + 1)).clamp(0.0, 1.0);
      score += 15 + tightness * 10;
    }

    return score;
  }

  /// Scores [app] by treating [romanQuery] (the romanized Korean query) as a
  /// plain English query — mirrors Tiers 3–6 and 11 against Latin app labels.
  static double _scoreRoman(AppEntry app, String romanQuery) {
    if (romanQuery.isEmpty) return 0;
    final label = app.labelNorm;
    final pkg = app.packageNorm;

    if (label == romanQuery || pkg == romanQuery) return 9000;

    double startRatio = 0;
    if (label.startsWith(romanQuery)) startRatio = romanQuery.length / label.length;
    if (pkg.startsWith(romanQuery)) {
      final r = romanQuery.length / pkg.length;
      if (r > startRatio) startRatio = r;
    }
    if (startRatio > 0) return 8000 + startRatio * 100;

    final wbLabel = _wordBoundaryRatio(label, romanQuery);
    final wbPkg = _wordBoundaryRatio(pkg, romanQuery);
    final wbRatio = wbLabel > wbPkg ? wbLabel : wbPkg;
    if (wbRatio > 0) return 7000 + wbRatio * 100;

    double contRatio = 0;
    if (label.contains(romanQuery)) contRatio = romanQuery.length / label.length;
    if (pkg.contains(romanQuery)) {
      final r = romanQuery.length / pkg.length;
      if (r > contRatio) contRatio = r;
    }
    if (contRatio > 0) return 6000 + contRatio * 100;

    if (romanQuery.length >= 2) {
      final target = '$label$pkg';
      final lcs = _longestCommonSubstring(romanQuery, target);
      final overlap = _charOverlap(romanQuery, target);
      final relScore = (lcs * 10 + overlap).toDouble();
      if (relScore > 0) return 1000 + (relScore * 5).clamp(0, 999);
    }

    return 0;
  }

  static bool _keywordMatches(
      String query, String q, bool chosungQuery, String keyword) {
    if (Korean.normalize(keyword).contains(q)) return true;
    if (chosungQuery && Korean.chosung(keyword).contains(query)) return true;
    return false;
  }

  // --- Low-level helpers ---

  static int _longestCommonSubstring(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final ar = a.runes.toList();
    final br = b.runes.toList();
    var prev = List<int>.filled(br.length + 1, 0);
    var best = 0;
    for (var i = 1; i <= ar.length; i++) {
      final cur = List<int>.filled(br.length + 1, 0);
      for (var j = 1; j <= br.length; j++) {
        if (ar[i - 1] == br[j - 1]) {
          cur[j] = prev[j - 1] + 1;
          if (cur[j] > best) best = cur[j];
        }
      }
      prev = cur;
    }
    return best;
  }

  static int _fuzzySubstringDistance(String pattern, String text) {
    final m = pattern.length;
    final n = text.length;
    if (m == 0) return 0;
    if (n == 0) return m;
    var prev = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = pattern[i - 1] == text[j - 1] ? 0 : 1;
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      prev = cur;
    }
    return prev.reduce((a, b) => a < b ? a : b);
  }

  static int _charOverlap(String a, String b) {
    final counts = <int, int>{};
    for (final r in b.runes) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    var n = 0;
    for (final r in a.runes) {
      final c = counts[r] ?? 0;
      if (c > 0) {
        counts[r] = c - 1;
        n++;
      }
    }
    return n;
  }

  static double _wordBoundaryBonus(String haystack, int pos) {
    if (pos == 0) return 0.10;
    if (pos < 0 || pos >= haystack.length) return 0;
    final prev = haystack[pos - 1];
    if (prev == ' ' || prev == '-' || prev == '_' || prev == '.') return 0.05;
    return 0;
  }

  static bool _isSubsequence(String pattern, String text) {
    if (pattern.isEmpty) return true;
    var i = 0;
    for (var j = 0; j < text.length && i < pattern.length; j++) {
      if (text[j] == pattern[i]) i++;
    }
    return i == pattern.length;
  }

  static int _subsequenceSpread(String pattern, String text) {
    if (pattern.isEmpty) return 0;
    var first = -1;
    var last = -1;
    var i = 0;
    for (var j = 0; j < text.length && i < pattern.length; j++) {
      if (text[j] == pattern[i]) {
        if (first == -1) first = j;
        last = j;
        i++;
      }
    }
    if (first < 0 || i < pattern.length) return text.length;
    return last - first;
  }
}
