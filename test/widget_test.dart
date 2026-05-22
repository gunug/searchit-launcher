// Unit tests for the Korean search helpers.

import 'package:flutter_test/flutter_test.dart';

import 'package:searchitlauncher/search/korean.dart';

void main() {
  test('chosung extracts leading consonants', () {
    expect(Korean.chosung('카카오톡'), 'ㅋㅋㅇㅌ');
  });

  test('isChosungOnly detects jamo-only queries', () {
    expect(Korean.isChosungOnly('ㅋㅋㅇ'), isTrue);
    expect(Korean.isChosungOnly('카카오'), isFalse);
  });

  test('romanize converts Hangul to Revised Romanization', () {
    expect(Korean.romanize('카카오'), 'kakao');
  });

  test('phoneticKey collapses English and Korean to the same skeleton', () {
    // Korean drops the epenthetic 으; folds reduce equivalent consonants.
    expect(Korean.phoneticKey('instagram'), Korean.phoneticKey('인스타그램'));
    expect(Korean.phoneticKey('youtube'), 'ytb');
  });

  test('normalize lowercases and strips spaces', () {
    expect(Korean.normalize('Kakao Talk'), 'kakaotalk');
  });

  test('qwerty projects Hangul onto QWERTY keys', () {
    // 카카오 typed on a 2-set keyboard hits the keys z-k-z-k-d-h.
    expect(Korean.qwerty('카카오'), 'zkzkdh');
    // Already-Latin text passes through unchanged.
    expect(Korean.qwerty('hello'), 'hello');
  });

  test('initials extracts abbreviations of English names', () {
    expect(Korean.initials('Google Play'), 'gp');
    expect(Korean.initials('YouTube'), 'yt'); // camelCase boundary
    expect(Korean.initials('카카오톡'), ''); // no Latin letters
  });
}
