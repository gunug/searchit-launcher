/// Rule-based Korean text helpers used by the search engine:
/// leading-consonant (초성) extraction and Revised-Romanization.
class Korean {
  Korean._();

  static const _choCompat = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';

  static const _choRoman = [
    'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's',
    'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h',
  ];

  static const _jungRoman = [
    'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa',
    'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i',
  ];

  static const _jongRoman = [
    '', 'k', 'k', 'ks', 'n', 'nj', 'nh', 't', 'l', 'lk',
    'lm', 'lp', 'ls', 'lt', 'lp', 'lh', 'm', 'p', 'ps', 's',
    'ss', 'ng', 'j', 'ch', 'k', 't', 'p', 'h',
  ];

  static const _base = 0xAC00;
  static const _last = 0xD7A3;

  static bool _isSyllable(int c) => c >= _base && c <= _last;

  /// Extracts the leading-consonant (초성) skeleton of [text].
  /// Non-Hangul characters are kept as-is so mixed strings still work.
  static String chosung(String text) {
    final sb = StringBuffer();
    for (final rune in text.runes) {
      if (_isSyllable(rune)) {
        sb.write(_choCompat[(rune - _base) ~/ 588]);
      } else {
        sb.write(String.fromCharCode(rune));
      }
    }
    return sb.toString();
  }

  /// True when every character of [text] is a 초성 jamo (e.g. "ㅋㅋㅇ").
  static bool isChosungOnly(String text) {
    if (text.isEmpty) return false;
    for (final rune in text.runes) {
      if (!_choCompat.contains(String.fromCharCode(rune))) return false;
    }
    return true;
  }

  /// Revised-romanization of [text]; non-Hangul characters pass through.
  /// Romanization is the common ground for English ↔ Korean similar search.
  static String romanize(String text) {
    final sb = StringBuffer();
    for (final rune in text.runes) {
      if (_isSyllable(rune)) {
        final c = rune - _base;
        sb.write(_choRoman[c ~/ 588]);
        sb.write(_jungRoman[(c % 588) ~/ 28]);
        sb.write(_jongRoman[c % 28]);
      } else {
        sb.write(String.fromCharCode(rune));
      }
    }
    return sb.toString().toLowerCase();
  }

  /// Single-consonant equivalence folds — sounds Korean does not distinguish.
  static const _consonantFolds = {
    'f': 'p', 'v': 'b', 'z': 'j', 'c': 'k', 'q': 'k', 'l': 'r', 'x': 'k',
  };

  /// A coarse phonetic skeleton for fuzzy English ↔ Korean similar search.
  ///
  /// It romanizes Hangul, folds equivalent consonants and drops every vowel.
  /// Dropping vowels neutralizes the epenthetic 으 that Korean inserts into
  /// consonant clusters, so e.g. "instagram" and "인스타그램" collapse to the
  /// same skeleton "nstgrm".
  static String phoneticKey(String text) {
    var s = romanize(text).replaceAll(RegExp('[^a-z]'), '');
    s = s.replaceAll('ph', 'p').replaceAll('th', 't').replaceAll('sh', 's');
    final sb = StringBuffer();
    var last = '';
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if ('aeiou'.contains(ch)) continue;
      final folded = _consonantFolds[ch] ?? ch;
      if (folded == last) continue; // collapse doubled consonants
      sb.write(folded);
      last = folded;
    }
    return sb.toString();
  }
}
