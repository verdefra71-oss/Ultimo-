class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('preventivi_full.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, fileName),
      version: 11,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clienti (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            email TEXT,
            telefono TEXT,
            indirizzo TEXT,
            partita_iva TEXT,
            codice_fiscale TEXT,
            parrocchia TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE prodotti (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            prezzo REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE preventivi (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero TEXT NOT NULL,
            data TEXT NOT NULL,
            cliente TEXT NOT NULL,
            totale REAL NOT NULL,
            numero_rate INTEGER NOT NULL,
            articoli TEXT NOT NULL DEFAULT '[]',
            iva_percent REAL NOT NULL DEFAULT 0,
            accettato INTEGER NOT NULL DEFAULT 0,
            acconti TEXT NOT NULL DEFAULT '[]',
            sconto_percent REAL NOT NULL DEFAULT 0,
            pagato INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE fatture (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            numero TEXT NOT NULL,
            data TEXT NOT NULL,
            cliente TEXT NOT NULL,
            articoli TEXT NOT NULL DEFAULT '[]',
            iva_percent REAL NOT NULL DEFAULT 0,
            totale REAL NOT NULL DEFAULT 0,
            pagamento TEXT NOT NULL DEFAULT 'Contanti',
            iban TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE acconti (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            preventivo_id INTEGER NOT NULL,
            cliente TEXT NOT NULL,
            importo REAL NOT NULL,
            data_scadenza TEXT NOT NULL,
            pagata INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE preventivi ADD COLUMN articoli TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE preventivi ADD COLUMN iva_percent REAL NOT NULL DEFAULT 0",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE clienti ADD COLUMN partita_iva TEXT",
          );
          await db.execute(
            "ALTER TABLE clienti ADD COLUMN codice_fiscale TEXT",
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE clienti ADD COLUMN parrocchia TEXT",
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            "ALTER TABLE preventivi ADD COLUMN accettato INTEGER NOT NULL DEFAULT 0",
          );
        }
        if (oldVersion < 7) {
          await db.execute(
            "ALTER TABLE preventivi ADD COLUMN acconti TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 8) {
          await db.execute(
            "ALTER TABLE preventivi ADD COLUMN sconto_percent REAL NOT NULL DEFAULT 0",
          );
        }
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE fatture (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              numero TEXT NOT NULL,
              data TEXT NOT NULL,
              cliente TEXT NOT NULL,
              articoli TEXT NOT NULL DEFAULT '[]',
              iva_percent REAL NOT NULL DEFAULT 0,
              totale REAL NOT NULL DEFAULT 0,
              pagamento TEXT NOT NULL DEFAULT 'Contanti'
            )
          ''');
        }
        if (oldVersion < 10) {
          await db.execute("ALTER TABLE fatture ADD COLUMN iban TEXT");
        }
        if (oldVersion < 11) {
          await db.execute("ALTER TABLE preventivi ADD COLUMN pagato INTEGER NOT NULL DEFAULT 0");
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>> getClienti() async {
    return (await database).query('clienti', orderBy: 'nome COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> getPreventivi() async {
    return (await database).query('preventivi', orderBy: 'id DESC');
  }

  /// Preventivi che hanno ancora un saldo da incassare.
  Future<List<Map<String, dynamic>>> getPreventiviDaSaldare() async {
    final preventivi = await getPreventivi();
    final risultato = <Map<String, dynamic>>[];
    for (final p in preventivi) {
      // MODIFICA 1: Gestione robusta del campo pagato per vecchi preventivi (fallback su 0)
      final isPagato = (p['pagato'] as num?)?.toInt() ?? 0;
      if (isPagato == 1) continue;

      final totale = (p['totale'] as num?)?.toDouble() ?? 0;
      double totaleAcconti = 0;
      try {
        final raw = jsonDecode((p['acconti'] ?? '[]').toString());
        if (raw is List) {
          for (final item in raw) {
            if (item is Map) {
              totaleAcconti += (item['importo'] as num?)?.toDouble() ?? 0;
            }
          }
        }
      } catch (_) {}
      final saldo = totale - totaleAcconti;
      if (saldo > 0.005) {
        risultato.add({
          ...p,
          'saldo': saldo,
        });
      }
    }
    return risultato;
  }

  Future<List<Map<String, dynamic>>> getProdotti() async {
    return (await database).query('prodotti', orderBy: 'nome COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> getAcconti() async {
    final preventivi = await getPreventivi();
    final risultato = <Map<String, dynamic>>[];
    for (final p in preventivi) {
      // MODIFICA 2: Filtra ignorando i preventivi non accettati
      if ((p['accettato'] as num?)?.toInt() != 1) continue;

      try {
        final raw = jsonDecode((p['acconti'] ?? '[]').toString());
        if (raw is List) {
          for (var i = 0; i < raw.length; i++) {
            final a = Map<String, dynamic>.from(raw[i] as Map);
            risultato.add({
              'preventivo_id': p['id'],
              'preventivo': p['numero'],
              'cliente': p['cliente'],
              'indice': i + 1,
              'importo': (a['importo'] as num?)?.toDouble() ?? 0,
              'data': (a['data'] ?? '').toString(),
            });
          }
        }
      } catch (_) {}
    }
    return risultato;
  }

  Future<int> insertProdotto({
    required String nome,
    required double prezzo,
  }) async {
    final id = await (await database).insert('prodotti', {
      'nome': nome,
      'prezzo': prezzo,
    });
    await autoBackup();
    return id;
  }

  Future<int> updateProdotto({
    required int id,
    required String nome,
    required double prezzo,
  }) async {
    final result = await (await database).update(
      'prodotti',
      {'nome': nome, 'prezzo': prezzo},
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<int> deleteProdotto(int id) async {
    final result = await (await database).delete(
      'prodotti',
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<int> insertCliente({
    required String nome,
    String email = '',
    String telefono = '',
    String indirizzo = '',
    String partitaIva = '',
    String codiceFiscale = '',
    String parrocchia = '',
  }) async {
    final id = await (await database).insert('clienti', {
      'nome': nome,
      'email': email,
      'telefono': telefono,
      'indirizzo': indirizzo,
      'partita_iva': partitaIva,
      'codice_fiscale': codiceFiscale,
      'parrocchia': parrocchia,
    });
    await autoBackup();
    return id;
  }

  Future<int> updateCliente({
    required int id,
    required String nome,
    String email = '',
    String telefono = '',
    String indirizzo = '',
    String partitaIva = '',
    String codiceFiscale = '',
    String parrocchia = '',
  }) async {
    final result = await (await database).update(
      'clienti',
      {
        'nome': nome,
        'email': email,
        'telefono': telefono,
        'indirizzo': indirizzo,
        'partita_iva': partitaIva,
        'codice_fiscale': codiceFiscale,
        'parrocchia': parrocchia,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<int> deleteCliente(int id) async {
    final result = await (await database).delete(
      'clienti',
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<List<Map<String, dynamic>>> getFatture() async {
    return (await database).query('fatture', orderBy: 'id DESC');
  }

  Future<int> insertFattura({
    required String numero,
    required String cliente,
    required List<Map<String, dynamic>> articoli,
    required double ivaPercent,
    required double totale,
    required String pagamento,
    String? iban,
  }) async {
    final id = await (await database).insert('fatture', {
      'numero': numero,
      'data': DateTime.now().toIso8601String(),
      'cliente': cliente,
      'articoli': jsonEncode(articoli),
      'iva_percent': ivaPercent,
      'totale': totale,
      'pagamento': pagamento,
      'iban': iban,
    });
    await autoBackup();
    return id;
  }

  Future<int> deleteFattura(int id) async {
    final result = await (await database).delete(
      'fatture',
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<String> prossimoNumeroFattura() async {
    final rows = await (await database).rawQuery('SELECT COUNT(*) AS n FROM fatture');
    final n = (rows.first['n'] as int? ?? 0) + 1;
    return 'FAT-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';
  }

  Future<String> prossimoNumeroPreventivo() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM preventivi');
    final n = (rows.first['n'] as int? ?? 0) + 1;
    return 'PREV-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';
  }

  Future<int> insertPreventivo({
    required String numero,
    required String cliente,
    required double totale,
    required List<Map<String, dynamic>> articoli,
    required double ivaPercent,
    required bool accettato,
    required List<Map<String, dynamic>> acconti,
    required double scontoPercent,
    required bool pagato,
  }) async {
    final id = await (await database).insert('preventivi', {
      'numero': numero,
      'data': DateTime.now().toIso8601String(),
      'cliente': cliente,
      'totale': totale,
      'numero_rate': acconti.length,
      'articoli': jsonEncode(articoli),
      'iva_percent': ivaPercent,
      'accettato': accettato ? 1 : 0,
      'acconti': jsonEncode(acconti),
      'sconto_percent': scontoPercent,
      'pagato': pagato ? 1 : 0,
    });
    await autoBackup();
    await NotificationService.instance.refreshMonthlyReminder();
    return id;
  }

  Future<int> updateAccontiPreventivo({
    required int id,
    required List<Map<String, dynamic>> acconti,
    required bool pagato,
  }) async {
    final db = await database;
    final result = await db.update(
      'preventivi',
      {
        'acconti': jsonEncode(acconti),
        'numero_rate': acconti.length,
        'pagato': pagato ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    await NotificationService.instance.refreshMonthlyReminder();
    return result;
  }

  Future<int> updatePreventivo({
    required int id,
    required String cliente,
    required double totale,
    required List<Map<String, dynamic>> articoli,
    required double ivaPercent,
    required bool accettato,
    required List<Map<String, dynamic>> acconti,
    required double scontoPercent,
    required bool pagato,
  }) async {
    final result = await (await database).update(
      'preventivi',
      {
        'cliente': cliente,
        'totale': totale,
        'numero_rate': acconti.length,
        'articoli': jsonEncode(articoli),
        'iva_percent': ivaPercent,
        'accettato': accettato ? 1 : 0,
        'acconti': jsonEncode(acconti),
        'sconto_percent': scontoPercent,
        'pagato': pagato ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await autoBackup();
    return result;
  }

  Future<Map<String, dynamic>> _backupData() async {
    final db = await database;
    return {
      'backupVersion': 1,
      'app': 'Gestione Preventivi',
      'createdAt': DateTime.now().toIso8601String(),
      'clienti': await db.query('clienti'),
      'prodotti': await db.query('prodotti'),
      'preventivi': await db.query('preventivi'),
      'fatture': await db.query('fatture'),
      'acconti': await getAcconti(),
    };
  }

  Future<void> autoBackup() async {
    // Implementazione autoBackup
  }

  Future<void> createAutomaticBackup() async {
    // Implementazione createAutomaticBackup
  }
}

