import '../models/app_entry.dart';
import '../services/storage_service.dart';
import 'korean.dart';

/// The four classified result sections, in display order.
class SearchResults {
  SearchResults({
    this.match = const [],
    this.history = const [],
    this.similar = const [],
    this.related = const [],
  });

  final List<AppEntry> match;
  final List<AppEntry> history;
  final List<AppEntry> similar;
  final List<AppEntry> related;

  bool get isEmpty =>
      match.isEmpty && history.isEmpty && similar.isEmpty && related.isEmpty;
}

class _Scored {
  _Scored(this.app, this.score);
  final AppEntry app;
  final double score;
}

/// Classifies apps into match / history / similar / related for a query.
///
/// Each app appears in only the highest-ranking section it qualifies for,
/// and apps inside a section are ordered by relevance (일치도순).
class SearchEngine {
  SearchEngine._();

  static SearchResults search(
    String rawQuery,
    List<AppEntry> apps,
    List<HistoryEntry> history,
  ) {
    final query = rawQuery.trim();
    if (query.isEmpty) return SearchResults();

    final q = Korean.normalize(query);
    final qRoman = Korean.romanize(query);
    final qQwerty = Korean.qwerty(query);
    final qPhonetic = Korean.phoneticKey(query);
    final chosungQuery = Korean.isChosungOnly(query);
    final used = <String>{};

    // 1. match — query is contained in the app name or package name,
    //    plus Korean 초성 search against the app name.
    final matchScored = <_Scored>[];
    for (final app in apps) {
      final label = app.labelNorm;
      final pkg = app.packageNorm;
      double score = 0;
      if (label == q) {
        score = 5;
      } else if (label.startsWith(q)) {
        score = 4;
      } else if (label.contains(q)) {
        score = 3;
      } else if (pkg.contains(q)) {
        score = 2;
      }
      if (score == 0 && chosungQuery && app.chosung.contains(query)) {
        score = 1;
      }
      if (score > 0) matchScored.add(_Scored(app, score));
    }
    final match = _take(matchScored, used);

    // 2. history — the query partially matches a past keyword whose apps
    //    were launched from the similar/related sections.
    final histScore = <String, double>{};
    for (final entry in history) {
      if (!_keywordMatches(query, q, chosungQuery, entry.keyword)) continue;
      for (final pkg in entry.packages) {
        final ts = entry.updatedAt.toDouble();
        if (ts > (histScore[pkg] ?? 0)) histScore[pkg] = ts;
      }
    }
    final historyScored = <_Scored>[];
    for (final app in apps) {
      final ts = histScore[app.packageName];
      if (ts != null) historyScored.add(_Scored(app, ts));
    }
    final historyList = _take(historyScored, used);

    // 3. similar — the query is not literally in the name but sounds or
    //    types like it. Three signals, each scored on a 0..~1 scale:
    //      a) substring of a normalized / romanized / QWERTY-layout form,
    //         so wrong-IME typing ("zkzkdh" → 카카오) is recovered here;
    //      b) fuzzy match on the phonetic skeleton, so English spelling and
    //         Korean transcription line up despite the epenthetic 으 and
    //         missing f/v/z sounds;
    //      c) initials match, so "gp" finds "Google Play".
    final queryForms = {q, qRoman, qQwerty}..removeWhere((e) => e.isEmpty);
    final similarScored = <_Scored>[];
    for (final app in apps) {
      if (used.contains(app.packageName)) continue;
      final appForms = {app.labelNorm, app.roman, app.qwerty}
        ..removeWhere((e) => e.isEmpty);
      double best = 0;
      // 3a. substring across forms; a hit at a word boundary scores higher.
      for (final qf in queryForms) {
        for (final af in appForms) {
          final at = af.indexOf(qf);
          if (at < 0) continue;
          final score = qf.length / af.length + _wordBoundaryBonus(af, at);
          if (score > best) best = score;
        }
      }
      // 3b. fuzzy phonetic-skeleton match.
      if (qPhonetic.length >= 3 && app.phonetic.length >= 2) {
        final dist = _fuzzySubstringDistance(qPhonetic, app.phonetic);
        final allowed = (qPhonetic.length ~/ 3).clamp(1, 99);
        if (dist <= allowed) {
          // Kept just below 1.0 so exact substring hits still rank first.
          final fuzzy = 0.9 * (1 - dist / qPhonetic.length);
          if (fuzzy > best) best = fuzzy;
        }
      }
      // 3c. initials / abbreviation match (English app names only).
      if (q.length >= 2 && app.initials.length >= 2) {
        final at = app.initials.indexOf(q);
        if (at >= 0) {
          final score = (0.85 - at * 0.05).clamp(0.0, 1.0);
          if (score > best) best = score;
        }
      }
      if (best > 0) similarScored.add(_Scored(app, best));
    }
    final similar = _take(similarScored, used);

    // 4. related — loose character-overlap / subsequence match; only shown
    //    for 2+ char queries. Subsequence catches names where every query
    //    character appears in order with gaps (e.g. "ggl" → "google"); a
    //    tighter spread of those characters scores higher.
    final relatedScored = <_Scored>[];
    if (query.length >= 2) {
      final relQuery = chosungQuery ? query : q;
      for (final app in apps) {
        if (used.contains(app.packageName)) continue;
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
        if (score <= 0) continue;
        relatedScored.add(_Scored(app, score));
      }
    }
    final related = _take(relatedScored, used);

    return SearchResults(
      match: match,
      history: historyList,
      similar: similar,
      related: related,
    );
  }

  /// Applies the same match logic to a stored history [keyword].
  static bool _keywordMatches(
      String query, String q, bool chosungQuery, String keyword) {
    if (Korean.normalize(keyword).contains(q)) return true;
    if (chosungQuery && Korean.chosung(keyword).contains(query)) return true;
    return false;
  }

  /// Sorts by relevance desc (label asc on ties) and drops apps already
  /// placed in a higher section.
  static List<AppEntry> _take(List<_Scored> scored, Set<String> used) {
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.app.label.toLowerCase().compareTo(b.app.label.toLowerCase());
    });
    final out = <AppEntry>[];
    for (final s in scored) {
      if (used.add(s.app.packageName)) out.add(s.app);
    }
    return out;
  }

  /// Length of the longest run of characters shared by [a] and [b].
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

  /// Minimum edit distance to align [pattern] against any substring of
  /// [text]. Used for fuzzy phonetic-skeleton matching in the similar
  /// section: free start/end offsets, edits counted only within the window.
  static int _fuzzySubstringDistance(String pattern, String text) {
    final m = pattern.length;
    final n = text.length;
    if (m == 0) return 0;
    if (n == 0) return m;
    var prev = List<int>.filled(n + 1, 0); // row 0 = 0: any start offset free
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
    return prev.reduce((a, b) => a < b ? a : b); // best end offset
  }

  /// Count of [a]'s characters that also appear in [b] (multiset overlap).
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

  /// Ranking bonus when a substring match starts at a word boundary, so a
  /// hit on a word's first letter outranks one buried mid-word. Returns 0
  /// when [pos] is inside a word.
  static double _wordBoundaryBonus(String haystack, int pos) {
    if (pos == 0) return 0.10;
    if (pos < 0 || pos >= haystack.length) return 0;
    final prev = haystack[pos - 1];
    if (prev == ' ' || prev == '-' || prev == '_' || prev == '.') return 0.05;
    return 0;
  }

  /// True when every character of [pattern] appears in [text] in order,
  /// gaps allowed (e.g. "ggl" is a subsequence of "google").
  static bool _isSubsequence(String pattern, String text) {
    if (pattern.isEmpty) return true;
    var i = 0;
    for (var j = 0; j < text.length && i < pattern.length; j++) {
      if (text[j] == pattern[i]) i++;
    }
    return i == pattern.length;
  }

  /// Index span between the first and last matched character of a
  /// subsequence alignment of [pattern] in [text] — smaller means the
  /// matched characters sit closer together. Returns [text].length when
  /// [pattern] is not a subsequence of [text].
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
