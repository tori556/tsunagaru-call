import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsunagaru_call/models.dart';

void main() {
  test('Helpers handle empty, emoji, expire labels, and byte sizes safely', () {
    expect(initialLetter(''), '?');
    expect(initialLetter('   '), '?');
    expect(initialLetter('😀太郎'), '😀');
    expect(initialLetter('お母さん'), 'お');
    expect(formatExpireLabel(0), '消えない');
    expect(formatExpireLabel(24), '24時間');
    expect(formatBytes(2048), '2.0KB');
  });

  test('View-once photo tracks viewers independently', () {
    final msg = ChatMessage(
      id: 'm1',
      sender: 'お母さん',
      text: '1回表示',
      createdAt: DateTime.now(),
      kind: 'photo',
      viewOncePhoto: true,
      viewedOnceBy: <String>['user_a'],
    );
    expect(msg.isViewedOnceBy('user_a'), isTrue);
    expect(msg.isViewedOnceBy('user_b'), isFalse);
  });

  testWidgets('Basic MaterialApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('trancefer'))),
    );
    expect(find.text('trancefer'), findsOneWidget);
  });
}
