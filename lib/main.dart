import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/repo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = await openAppDatabase(
        p.join(await getDatabasesPath(), 'arbol_monitor.db'));
    repo = Repo(db);
    // Sesiones que quedaron abiertas si la app se cerró durante una medición.
    await repo.recoverInterrupted();
    runApp(const ArbolApp());
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No se pudo abrir la base de datos local.\n\n$e',
                textAlign: TextAlign.center),
          ),
        ),
      ),
    ));
  }
}
