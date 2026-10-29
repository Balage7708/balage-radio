import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/models.dart';
import 'common.dart';
import 'home_page.dart' show deleteStation;
import 'theme.dart';

Future<void> showEditStation(BuildContext context, Station st) async {
  final name = TextEditingController(text: st.name);
  final url = TextEditingController(text: st.url);
  final logo = TextEditingController(text: st.favicon);
  final form = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Adó szerkesztése', style: head(size: 18)),
      content: SizedBox(
        width: 460,
        child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Név'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Add meg a nevet' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: url,
              decoration: const InputDecoration(labelText: 'Stream-cím (URL)'),
              validator: (v) => Uri.tryParse((v ?? '').trim())?.hasScheme == true ? null : 'Érvényes címet adj meg',
            ),
            const SizedBox(height: 12),
            TextFormField(controller: logo, decoration: const InputDecoration(labelText: 'Logó címe (nem kötelező)')),
          ]),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: BC.danger),
          onPressed: () async {
            Navigator.pop(c);
            await deleteStation(context, st);
          },
          child: const Text('Törlés'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Mégse')),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            final urlChanged = st.url != url.text.trim();
            st
              ..name = name.text.trim()
              ..url = url.text.trim()
              ..favicon = logo.text.trim()
              ..query = '';
            if (urlChanged) {
              st
                ..codec = ''
                ..bitrate = 0;
            }
            store.saveStations();
            Navigator.pop(c);
            if (urlChanged && engine.current?.id == st.id && engine.want) engine.play(st);
            toast(context, 'Mentve');
          },
          child: const Text('Mentés'),
        ),
      ],
    ),
  );
}
