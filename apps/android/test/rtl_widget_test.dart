import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Arabic locale lays out the app right-to-left', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(builder: (context) => Text(Directionality.of(context).name)),
    ));
    expect(Directionality.of(tester.element(find.byType(Text))), TextDirection.rtl);
  });

  testWidgets('task form shows an error when its title is blank', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Form(key: key, child: TextFormField(validator: (value) => value == null || value.trim().isEmpty ? 'Task title is required' : null))),
    ));
    key.currentState!.validate();
    await tester.pump();
    expect(find.text('Task title is required'), findsOneWidget);
  });
}
