import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_pilot/data/local/database.dart';

void main() {
  test('saveAsset menyimpan dan bisa dibaca ulang', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await db.upsertWorkspaceFromServer({
      'id': 'ws1',
      'type': 'PERSONAL',
      'name': 'Pribadi',
      'color': '#10B981',
      'icon': 'person',
    });

    final saved = await db.saveAsset(AssetsCompanion.insert(
      id: 'asset1',
      workspaceId: 'ws1',
      name: 'Laptop',
      category: Value('electronics'),
      purchaseAt: const Value(null),
      purchasePrice: const Value(null),
      currentValue: Value(1500000),
      status: Value('ACTIVE'),
      note: const Value(null),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      deviceId: '',
    ));

    expect(saved.id, 'asset1');

    final list = await db.watchAssets('ws1').first;
    expect(list.length, 1);
    expect(list.first.name, 'Laptop');

    await db.addValuation(
      workspaceId: 'ws1',
      assetId: 'asset1',
      value: 1600000,
      valuedAt: DateTime.now(),
    );

    final again = await db.watchAssets('ws1').first;
    expect(again.first.currentValue, 1600000);

    await db.close();
  });
}
