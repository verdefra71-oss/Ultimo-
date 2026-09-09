import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await DatabaseHelper.instance.createAutomaticBackup();
  runApp(const PreventiviApp());
}

class PreventiviApp extends StatelessWidget {
  const PreventiviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestione Preventivi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC99700),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF9A7000),
          onPrimary: Colors.white,
          secondary: const Color(0xFFD4AF37),
          surface: Colors.white,
          onSurface: const Color(0xFF222222),
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF9A7000),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

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
      version: 10,
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
  sconto_percent REAL NOT NULL DEFAULT 0
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
      },
    );
  }

  Future<List<Map<String, dynamic>>> getClienti() async {
    return (await database).query('clienti', orderBy: 'nome COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> getPreventivi() async {
    return (await database).query('preventivi', orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getProdotti() async {
    return (await database).query('prodotti', orderBy: 'nome COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> getAcconti() async {
    final preventivi = await getPreventivi();
    final risultato = <Map<String, dynamic>>[];

    for (final p in preventivi) {
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
    });
    await autoBackup();
    return id;
  }

  /// Salva SOLO gli acconti di un preventivo esistente.
  /// Questo metodo viene usato dalla schermata Modifica preventivo quando
  /// l'utente aggiunge un nuovo acconto dopo aver già generato il PDF.
  Future<int> updateAccontiPreventivo({
    required int id,
    required List<Map<String, dynamic>> acconti,
  }) async {
    final db = await database;
    final result = await db.update(
      'preventivi',
      {
        'acconti': jsonEncode(acconti),
        'numero_rate': acconti.length,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    // Il backup non deve impedire il salvataggio dell'acconto.
    try { await autoBackup(); } catch (e) { debugPrint('Backup acconti: $e'); }
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

  Future<File> createAutomaticBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'backup'));
    if (!await backupDir.exists()) await backupDir.create(recursive: true);
    final file = File(p.join(backupDir.path, 'preventivi_auto_backup.json'));
    await file.writeAsString(jsonEncode(await _backupData()), flush: true);
    return file;
  }

  Future<File> exportBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(dir.path, 'backup_export'));
    if (!await exports.exists()) await exports.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(exports.path, 'Preventivi_backup_$stamp.json'));
    await file.writeAsString(jsonEncode(await _backupData()), flush: true);
    return file;
  }

  Future<void> importBackup(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup non valido.');
    }
    final clienti = List<Map<String, dynamic>>.from(
      (decoded['clienti'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final prodotti = List<Map<String, dynamic>>.from(
      (decoded['prodotti'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final preventivi = List<Map<String, dynamic>>.from(
      (decoded['preventivi'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final fatture = List<Map<String, dynamic>>.from(
      (decoded['fatture'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('preventivi');
      await txn.delete('prodotti');
      await txn.delete('clienti');
      await txn.delete('fatture');
      for (final row in clienti) await txn.insert('clienti', row);
      for (final row in prodotti) await txn.insert('prodotti', row);
      for (final row in preventivi) await txn.insert('preventivi', row);
      for (final row in fatture) await txn.insert('fatture', row);
    });
    await createAutomaticBackup();
  }

  Future<void> autoBackup() async {
    try {
      await createAutomaticBackup();
    } catch (_) {}
  }

}
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'acconti_channel';
  static const String _channelName = 'Scadenze rate';
  static const String _channelDescription =
      'Avvisi il giorno prima delle scadenze delle rate';

  Future<AndroidFlutterLocalNotificationsPlugin?> _android() async =>
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _notifications.initialize(settings);

    final android = await _android();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
        ),
      );
    }
  }

  Future<bool> notificheAbilitate() async {
    final android = await _android();
    if (android == null) return false;
    return await android.areNotificationsEnabled() ?? false;
  }

  /// Richiede esplicitamente il permesso Android 13+.
  /// Restituisce true solo quando Android conferma che le notifiche sono abilitate.
  Future<bool> preparaPermessi() async {
    final android = await _android();
    if (android == null) return false;

    var abilitate = await notificheAbilitate();
    if (!abilitate) {
      try {
        final richiesto = await android.requestNotificationsPermission();
        debugPrint('Permesso notifiche richiesto: $richiesto');
      } catch (e) {
        debugPrint('Errore richiesta permesso notifiche: $e');
      }
      abilitate = await notificheAbilitate();
    }
    return abilitate;
  }

  DateTime? _parseDataScadenza(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(text);
    } catch (_) {
      return null;
    }
  }

  int _notificationId(int preventivoId, int indice) =>
      100000 + preventivoId * 1000 + indice + 1;

  Future<void> cancellaNotifichePreventivo(int preventivoId) async {
    final richieste = await _notifications.pendingNotificationRequests();
    final minId = 100000 + preventivoId * 1000;
    final maxId = minId + 999;
    for (final richiesta in richieste) {
      if (richiesta.id >= minId && richiesta.id <= maxId) {
        await _notifications.cancel(richiesta.id);
      }
    }
  }

  Future<int> programmaNotificheRate({
    required int preventivoId,
    required String cliente,
    required List<Map<String, dynamic>> acconti,
  }) async {
    // Prima elimina SEMPRE le vecchie notifiche del preventivo.
    await cancellaNotifichePreventivo(preventivoId);

    // Se l'utente ha negato il permesso non fingiamo di aver programmato nulla.
    final abilitate = await preparaPermessi();
    if (!abilitate) {
      debugPrint('Notifiche Android non abilitate: programmazione annullata.');
      return 0;
    }

    final now = tz.TZDateTime.now(tz.local);
    final dettagli = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        enableVibration: true,
        playSound: true,
        autoCancel: true,
      ),
    );

    for (var i = 0; i < acconti.length; i++) {
      final rata = acconti[i];
      final data = _parseDataScadenza((rata['data'] ?? '').toString());
      final importo = (rata['importo'] as num?)?.toDouble() ?? 0;
      if (data == null || importo <= 0) continue;

      // Giorno precedente alla scadenza, ore 09:00 Europe/Rome.
      final scadenza = tz.TZDateTime(
        tz.local,
        data.year,
        data.month,
        data.day,
        9,
      );
      final quando = scadenza.subtract(const Duration(days: 1));
      if (!quando.isAfter(now)) continue;

      final id = _notificationId(preventivoId, i);
      try {
        await _notifications.zonedSchedule(
          id,
          'Rata in scadenza domani',
          'Domani scade la rata di €${importo.toStringAsFixed(2)} per $cliente.',
          quando,
          dettagli,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        debugPrint('Notifica $id programmata per $quando');
      } catch (e, st) {
        debugPrint('Errore programmazione notifica $id: $e\n$st');
      }
    }

    final pending = await _notifications.pendingNotificationRequests();
    final ids = <int>{
      for (var i = 0; i < acconti.length; i++) _notificationId(preventivoId, i),
    };
    final result = pending.where((n) => ids.contains(n.id)).length;
    debugPrint('Notifiche realmente pending per preventivo $preventivoId: $result');
    return result;
  }

  Future<List<PendingNotificationRequest>> programmate() async =>
      _notifications.pendingNotificationRequests();

  Future<void> apriImpostazioniNotifiche() async {
    try {
      await launchUrl(Uri.parse('app-settings:'));
    } catch (e) {
      debugPrint('Impossibile aprire le impostazioni notifiche: $e');
    }
  }
}

class PdfGenerator {
  static Future<void> generaECondividiPreventivo({
    required String numero,
    required String cliente,
    required List<Map<String, dynamic>> articoli,
    required double ivaPercent,
    required bool accettato,
    required List<Map<String, dynamic>> acconti,
    required double scontoPercent,
  }) async {
    // Il font predefinito del pacchetto PDF non contiene il carattere euro (€).
    // Carichiamo quindi un font Unicode con supporto completo al simbolo €.
    final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(fontData),
        bold: pw.Font.ttf(boldFontData),
      ),
    );
    pw.MemoryImage? logo;
    Map<String, dynamic>? datiCliente;

    try {
      final bytes = await rootBundle.load('assets/logo.png');
      logo = pw.MemoryImage(Uint8List.fromList(bytes.buffer.asUint8List()));
    } catch (_) {}

    // Recupera l'anagrafica completa per stampare tutti i dati del cliente.
    try {
      final clienti = await DatabaseHelper.instance.getClienti();
      final matches = clienti.where(
        (c) => (c['nome'] ?? '').toString().trim() == cliente.trim(),
      );
      if (matches.isNotEmpty) {
        datiCliente = Map<String, dynamic>.from(matches.first);
      }
    } catch (_) {}

    final imponibile = articoli.fold<double>(
      0,
      (sum, x) {
        final prezzo = (x['prezzo'] as num?)?.toDouble() ?? 0;
        final quantita = (x['quantita'] as num?)?.toDouble() ?? 1;
        return sum + (prezzo * quantita);
      },
    );
    final sconto = imponibile * scontoPercent / 100;
    final imponibileScontato = (imponibile - sconto).clamp(0, double.infinity).toDouble();
    final iva = imponibileScontato * ivaPercent / 100;
    final totale = imponibileScontato + iva;
    final data = DateFormat('dd/MM/yyyy').format(DateTime.now());

    final gold = PdfColor.fromHex('#B8860B');
    final dark = gold;

    String value(String key) => (datiCliente?[key] ?? '').toString().trim();

    final indirizzo = value('indirizzo');
    final telefono = value('telefono');
    final email = value('email');
    final partitaIva = value('partita_iva');
    final codiceFiscale = value('codice_fiscale');
    final parrocchia = value('parrocchia');

    final clientRows = <pw.Widget>[
      pw.Text(
        'CLIENTE',
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: gold,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
        cliente,
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      if (indirizzo.isNotEmpty) pw.Text('Indirizzo: $indirizzo'),
      if (telefono.isNotEmpty) pw.Text('Telefono: $telefono'),
      if (email.isNotEmpty) pw.Text('Email: $email'),
      if (partitaIva.isNotEmpty) pw.Text('Partita IVA: $partitaIva'),
      if (codiceFiscale.isNotEmpty) pw.Text('Codice Fiscale: $codiceFiscale'),
      if (parrocchia.isNotEmpty) pw.Text('Parrocchia: $parrocchia'),
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
        build: (_) => [
          // Logo ingrandito: circa il doppio rispetto alla versione precedente.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.SizedBox(
                  width: 285,
                  height: 190,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                )
              else
                pw.SizedBox(
                  width: 285,
                  height: 150,
                  child: pw.Text(
                    'BTS',
                    style: pw.TextStyle(
                      fontSize: 38,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(width: 18),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      accettato ? 'RICEVUTA' : 'PREVENTIVO',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: dark,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Divider(color: gold),
                    pw.SizedBox(height: 8),
                    pw.Text('N. $numero', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Data: $data', style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: gold),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: clientRows,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['N.', 'Prodotto / Servizio', 'Q.tà', 'Prezzo unit. (€)', 'Totale (€)'],
            data: [
              for (var i = 0; i < articoli.length; i++)
                [
                  '${i + 1}',
                  (articoli[i]['nome'] ?? '').toString(),
                  ((articoli[i]['quantita'] as num?)?.toDouble() ?? 1).toStringAsFixed(2),
                  '€ ${((articoli[i]['prezzo'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                  '€ ${(((articoli[i]['prezzo'] as num?)?.toDouble() ?? 0) * ((articoli[i]['quantita'] as num?)?.toDouble() ?? 1)).toStringAsFixed(2)}',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(color: gold),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(25),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FixedColumnWidth(42),
              3: const pw.FixedColumnWidth(75),
              4: const pw.FixedColumnWidth(75),
            },
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Imponibile: € ${imponibile.toStringAsFixed(2)}'),
                if (scontoPercent > 0) ...[
                  pw.Text(
                    'Sconto ${scontoPercent.toStringAsFixed(0)}%: -€ ${sconto.toStringAsFixed(2)}',
                    style: pw.TextStyle(color: gold, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Imponibile scontato: € ${imponibileScontato.toStringAsFixed(2)}'),
                ],
                if (ivaPercent == 0)
                  pw.Text(
                    'FUORI CAMPO IVA FCI',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  )
                else
                  pw.Text(
                    'IVA ${ivaPercent.toStringAsFixed(0)}%: € ${iva.toStringAsFixed(2)}',
                  ),
                pw.SizedBox(height: 5),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: gold,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  ),
                  child: pw.Text(
                    'TOTALE: € ${totale.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (acconti.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: gold),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ACCONTI',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: gold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  ...acconti.asMap().entries.map((entry) {
                    final a = entry.value;
                    final importo = (a['importo'] as num?)?.toDouble() ?? 0;
                    final dataAcconto = (a['data'] ?? '').toString();
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Text(
                        'Acconto ${entry.key + 1}: € ${importo.toStringAsFixed(2)}'
                        '${dataAcconto.isEmpty ? '' : '  •  $dataAcconto'}',
                      ),
                    );
                  }),
                  pw.Divider(color: gold),
                  pw.Text(
                    'Totale acconti: € ${acconti.fold<double>(0, (s, a) => s + ((a['importo'] as num?)?.toDouble() ?? 0)).toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Saldo residuo: € ${(totale - acconti.fold<double>(0, (s, a) => s + ((a['importo'] as num?)?.toDouble() ?? 0))).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 25),
          pw.Divider(color: gold),
          pw.SizedBox(height: 6),
          pw.Text(
            'Documento generato da Gestione Preventivi.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${accettato ? 'Ricevuta' : 'Preventivo'}_$numero.pdf',
    );
  }

  static Future<void> generaECondividiFattura({
    required String numero,
    required String cliente,
    required List<Map<String, dynamic>> articoli,
    required double ivaPercent,
    required String pagamento,
    String? iban,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(fontData),
        bold: pw.Font.ttf(boldFontData),
      ),
    );
    pw.MemoryImage? logo;
    Map<String, dynamic>? datiCliente;
    try {
      final bytes = await rootBundle.load('assets/logo.png');
      logo = pw.MemoryImage(Uint8List.fromList(bytes.buffer.asUint8List()));
    } catch (_) {}
    try {
      final clienti = await DatabaseHelper.instance.getClienti();
      final matches = clienti.where(
        (c) => (c['nome'] ?? '').toString().trim() == cliente.trim(),
      );
      if (matches.isNotEmpty) datiCliente = Map<String, dynamic>.from(matches.first);
    } catch (_) {}

    final imponibile = articoli.fold<double>(0, (sum, x) {
      final prezzo = (x['prezzo'] as num?)?.toDouble() ?? 0;
      final quantita = (x['quantita'] as num?)?.toDouble() ?? 1;
      return sum + prezzo * quantita;
    });
    final iva = imponibile * ivaPercent / 100;
    final totale = imponibile + iva;
    final data = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final gold = PdfColor.fromHex('#B8860B');

    String value(String key) => (datiCliente?[key] ?? '').toString().trim();

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F7F1DC')),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('Descrizione', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('Qtà', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('Prezzo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('Totale', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        ],
      ),
    ];
    for (final a in articoli) {
      final prezzo = (a['prezzo'] as num?)?.toDouble() ?? 0;
      final q = (a['quantita'] as num?)?.toDouble() ?? 1;
      rows.add(pw.TableRow(children: [
        pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text((a['nome'] ?? '').toString())),
        pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(q.toStringAsFixed(q == q.roundToDouble() ? 0 : 2))),
        pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('${prezzo.toStringAsFixed(2)} €')),
        pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text('${(prezzo*q).toStringAsFixed(2)} €')),
      ]));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null)
                    pw.SizedBox(
                      width: 285,
                      height: 125,
                      child: pw.Image(logo, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.SizedBox(
                      width: 285,
                      height: 90,
                      child: pw.Text(
                        'BTS',
                        style: pw.TextStyle(fontSize: 38, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'FATTURA',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: gold,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('N. $numero', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Data: $data'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('CLIENTE', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: gold)),
          pw.SizedBox(height: 4),
          pw.Text(cliente, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          if (value('indirizzo').isNotEmpty) pw.Text('Indirizzo: ${value('indirizzo')}'),
          if (value('telefono').isNotEmpty) pw.Text('Telefono: ${value('telefono')}'),
          if (value('email').isNotEmpty) pw.Text('Email: ${value('email')}'),
          if (value('partita_iva').isNotEmpty) pw.Text('Partita IVA: ${value('partita_iva')}'),
          if (value('codice_fiscale').isNotEmpty) pw.Text('Codice Fiscale: ${value('codice_fiscale')}'),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromHex('#D8C98A')),
            columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1.7)},
            children: rows,
          ),
          pw.SizedBox(height: 18),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              child: pw.Column(children: [
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Imponibile'), pw.Text('${imponibile.toStringAsFixed(2)} €')]),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('IVA ${ivaPercent.toStringAsFixed(2)}%'), pw.Text('${iva.toStringAsFixed(2)} €')]),
                pw.Divider(color: gold),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('TOTALE', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${totale.toStringAsFixed(2)} €', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: gold)),
                ]),
              ]),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#D8C98A'))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('DATI AZIENDA', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: gold)),
                pw.SizedBox(height: 4),
                pw.Text('di CARPENTIERI ALFONSO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('Sede legale: via Ugo Pirro, 9 - 84100 Salerno'),
                pw.Text('Cell. 328 697 2865'),
                pw.Text('P. IVA 06051430657'),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#D8C98A'))),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Metodo di pagamento: $pagamento', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (pagamento == 'Bonifico' && (iban ?? '').trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text('IBAN: ${iban!.trim()}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Fattura_$numero.pdf',
    );
  }

}

class CreaFatturaScreen extends StatefulWidget {
  final Map<String, dynamic>? preventivo;

  const CreaFatturaScreen({super.key, this.preventivo});

  @override
  State<CreaFatturaScreen> createState() => _CreaFatturaScreenState();
}

class _CreaFatturaScreenState extends State<CreaFatturaScreen> {
  final _numero = TextEditingController();
  final _iva = TextEditingController(text: '0');
  final _cliente = TextEditingController();
  final _iban = TextEditingController();
  String? cliente;
  String pagamento = 'Contanti';
  final List<Map<String, dynamic>> articoli = [];
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    _precompila();
  }

  Future<void> _precompila() async {
    _numero.text = await DatabaseHelper.instance.prossimoNumeroFattura();
    final p = widget.preventivo;
    if (p != null) {
      cliente = (p['cliente'] ?? '').toString();
      _cliente.text = cliente ?? '';
      _iva.text = ((p['iva_percent'] as num?)?.toDouble() ?? 0).toString();
      try {
        final raw = jsonDecode((p['articoli'] ?? '[]').toString());
        if (raw is List) {
          articoli.addAll(raw.map((e) => {
            'nome': (e['nome'] ?? '').toString(),
            'prezzo': (e['prezzo'] as num?)?.toDouble() ?? 0,
            'quantita': (e['quantita'] as num?)?.toDouble() ?? 1,
          }));
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  double get imponibile => articoli.fold<double>(0, (sum, x) {
        final p = (x['prezzo'] as num?)?.toDouble() ?? 0;
        final q = (x['quantita'] as num?)?.toDouble() ?? 1;
        return sum + p * q;
      });

  double get ivaPercent => double.tryParse(_iva.text.replaceAll(',', '.')) ?? 0;
  double get totale => imponibile + imponibile * ivaPercent / 100;

  Future<void> _aggiungiProdotto() async {
    final nome = TextEditingController();
    final prezzo = TextEditingController();
    final quantita = TextEditingController(text: '1');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aggiungi prodotto / servizio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nome,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Descrizione',
                  hintText: 'Inserisci anche un materiale non presente in archivio',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: prezzo,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Prezzo unitario €'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: quantita,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantità'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ANNULLA')),
          FilledButton(
            onPressed: () {
              final n = nome.text.trim();
              final p = double.tryParse(prezzo.text.replaceAll(',', '.')) ?? 0;
              final q = double.tryParse(quantita.text.replaceAll(',', '.')) ?? 1;
              if (n.isEmpty || p < 0 || q <= 0) return;
              Navigator.pop(ctx, {'nome': n, 'prezzo': p, 'quantita': q});
            },
            child: const Text('AGGIUNGI'),
          ),
        ],
      ),
    );
    nome.dispose();
    prezzo.dispose();
    quantita.dispose();
    if (result != null && mounted) {
      setState(() => articoli.add(result));
    }
  }

  Future<void> _salva() async {
    if ((_numero.text.trim()).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il numero della fattura.')),
      );
      return;
    }
    cliente = _cliente.text.trim();
    if (pagamento == 'Bonifico' && _iban.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci l\'IBAN per il pagamento con bonifico.')),
      );
      return;
    }

    setState(() => salvando = true);
    try {
      final numero = _numero.text.trim();
      await DatabaseHelper.instance.insertFattura(
        numero: numero,
        cliente: cliente!,
        articoli: articoli,
        ivaPercent: ivaPercent,
        totale: totale,
        pagamento: pagamento,
        iban: pagamento == 'Bonifico' ? _iban.text.trim() : null,
      );
      await PdfGenerator.generaECondividiFattura(
        numero: numero,
        cliente: cliente!,
        articoli: articoli,
        ivaPercent: ivaPercent,
        pagamento: pagamento,
        iban: pagamento == 'Bonifico' ? _iban.text.trim() : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fattura salvata e PDF pronto per la condivisione.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  void dispose() {
    _numero.dispose();
    _iva.dispose();
    _cliente.dispose();
    _iban.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    const darkGold = Color(0xFF9A7000);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.preventivo == null ? 'Crea fattura' : 'Fattura da preventivo'),
        actions: [
          IconButton(
            tooltip: 'Salva fattura',
            onPressed: salvando ? null : _salva,
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          if (widget.preventivo != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Creata dal preventivo'),
                subtitle: Text((widget.preventivo!['numero'] ?? '').toString()),
              ),
            ),
          if (widget.preventivo != null) const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _numero,
                    decoration: const InputDecoration(
                      labelText: 'Numero fattura',
                      helperText: 'Progressivo modificabile e digitabile',
                      prefixIcon: Icon(Icons.numbers_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cliente,
                    onChanged: (v) => cliente = v,
                    decoration: const InputDecoration(
                      labelText: 'Cliente',
                      hintText: 'Inserisci il cliente oppure digita un nominativo',
                      prefixIcon: Icon(Icons.person_outline, color: darkGold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final c = await selezionaCliente(context);
                        if (c != null) {
                          setState(() {
                            cliente = c;
                            _cliente.text = c;
                          });
                        }
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('Scegli dall\'archivio clienti (facoltativo)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Prodotti / servizi',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (articoli.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('Nessun articolo aggiunto.'),
                    ),
                  ...List.generate(articoli.length, (i) {
                    final a = articoli[i];
                    final prezzo = (a['prezzo'] as num?)?.toDouble() ?? 0;
                    final q = (a['quantita'] as num?)?.toDouble() ?? 1;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(a['nome'].toString()),
                      subtitle: Text('${q.toStringAsFixed(q == q.roundToDouble() ? 0 : 2)} × ${prezzo.toStringAsFixed(2)} €'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => articoli.removeAt(i)),
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: _aggiungiProdotto,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Aggiungi prodotto / servizio'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _iva,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'IVA %',
                      prefixIcon: Icon(Icons.percent_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: pagamento,
                    decoration: const InputDecoration(
                      labelText: 'Pagamento',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Contanti', child: Text('Contanti')),
                      DropdownMenuItem(value: 'Bonifico', child: Text('Bonifico')),
                    ],
                    onChanged: (v) => setState(() => pagamento = v ?? 'Contanti'),
                  ),
                  if (pagamento == 'Bonifico') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _iban,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'IBAN',
                        hintText: 'Inserisci IBAN',
                        prefixIcon: Icon(Icons.account_balance),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Imponibile'),
                      Text('${imponibile.toStringAsFixed(2)} €'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('IVA (${ivaPercent.toStringAsFixed(2)}%)'),
                      Text('${(totale - imponibile).toStringAsFixed(2)} €'),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTALE',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('${totale.toStringAsFixed(2)} €',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: gold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: darkGold),
            onPressed: salvando ? null : _salva,
            icon: salvando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.receipt_long_rounded),
            label: const Text('CREA FATTURA E PDF'),
          ),
        ],
      ),
    );
  }
}

class ListaFattureScreen extends StatefulWidget {
  const ListaFattureScreen({super.key});

  @override
  State<ListaFattureScreen> createState() => _ListaFattureScreenState();
}

class _ListaFattureScreenState extends State<ListaFattureScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> fatture = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _carica();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => loading = true);
    final dati = await DatabaseHelper.instance.getFatture();
    if (!mounted) return;
    setState(() {
      fatture = dati;
      loading = false;
    });
  }

  List<Map<String, dynamic>> get filtrate {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return fatture;
    return fatture.where((f) =>
      (f['numero'] ?? '').toString().toLowerCase().contains(q) ||
      (f['cliente'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  List<Map<String, dynamic>> _articoli(Map<String, dynamic> f) {
    try {
      final raw = jsonDecode((f['articoli'] ?? '[]').toString());
      if (raw is! List) return [];
      return raw.map((e) => {
        'nome': (e['nome'] ?? '').toString(),
        'prezzo': (e['prezzo'] as num?)?.toDouble() ?? 0,
        'quantita': (e['quantita'] as num?)?.toDouble() ?? 1,
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _elimina(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la fattura?'),
        content: Text('${f['numero']}\n${f['cliente']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ANNULLA')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ELIMINA')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteFattura((f['id'] as num).toInt());
    await _carica();
  }

  void _mostra(Map<String, dynamic> f) {
    final data = DateTime.tryParse((f['data'] ?? '').toString()) ?? DateTime.now();
    final articoli = _articoli(f);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const CircleAvatar(child: Icon(Icons.receipt_long)),
                const SizedBox(width: 12),
                Expanded(child: Text((f['numero'] ?? '').toString(), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              const Divider(height: 24),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline), title: const Text('Cliente'), subtitle: Text((f['cliente'] ?? '').toString())),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.calendar_today_outlined), title: const Text('Data'), subtitle: Text(DateFormat('dd/MM/yyyy').format(data))),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.payments_outlined), title: const Text('Totale'), subtitle: Text('€ ${((f['totale'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}')),
              if (articoli.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text('Articoli', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                ...articoli.map((a) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(a['nome'].toString()),
                  trailing: Text('${((a['prezzo'] as num).toDouble() * (a['quantita'] as num).toDouble()).toStringAsFixed(2)} €'),
                )),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: FilledButton.icon(
                  onPressed: () async {
                    await PdfGenerator.generaECondividiFattura(
                      numero: f['numero'].toString(),
                      cliente: f['cliente'].toString(),
                      articoli: articoli,
                      ivaPercent: (f['iva_percent'] as num?)?.toDouble() ?? 0,
                      pagamento: f['pagamento'].toString(),
                      iban: (f['iban'] ?? '').toString(),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                )),
                const SizedBox(width: 10),
                OutlinedButton.icon(onPressed: () async { Navigator.pop(ctx); await _elimina(f); }, icon: const Icon(Icons.delete_outline), label: const Text('ELIMINA')),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = filtrate;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fatture'),
        actions: [
          IconButton(onPressed: _carica, icon: const Icon(Icons.refresh_rounded)),
          IconButton(onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreaFatturaScreen()));
            _carica();
          }, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carica,
        child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Cerca fattura o cliente'),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Nessuna fattura salvata.')))
                else
                  ...items.map((f) {
                    final data = DateTime.tryParse((f['data'] ?? '').toString()) ?? DateTime.now();
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
                        title: Text((f['numero'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${f['cliente']}\n${DateFormat('dd/MM/yyyy').format(data)} • ${f['pagamento']}'),
                        isThreeLine: true,
                        trailing: Text('€ ${((f['totale'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () => _mostra(f),
                      ),
                    );
                  }),
              ],
            ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int preventivi = 0;
  int clienti = 0;
  int prodotti = 0;
  int acconti = 0;
  int fatture = 0;
  bool loading = true;

  static const _gold = Color(0xFFD4AF37);
  static const _darkGold = Color(0xFF9A7000);
  static const _cream = Color(0xFFFFF9E8);

  @override
  void initState() {
    super.initState();
    caricaStatistiche();
  }

  Future<void> caricaStatistiche() async {
    final db = DatabaseHelper.instance;
    final results = await Future.wait([
      db.getPreventivi(),
      db.getClienti(),
      db.getProdotti(),
      db.getAcconti(),
      db.getFatture(),
    ]);
    if (!mounted) return;
    setState(() {
      preventivi = results[0].length;
      clienti = results[1].length;
      prodotti = results[2].length;
      acconti = results[3].length;
      fatture = results[4].length;
      loading = false;
    });
  }

  Future<void> apri(Widget pagina) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => pagina),
    );
    caricaStatistiche();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PREVENTIVI',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: caricaStatistiche,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _darkGold,
        onRefresh: caricaStatistiche,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            // Azione principale sempre immediatamente disponibile.
            Card(
              color: _gold,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .20),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gestione Preventivi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Crea e gestisci i tuoi preventivi',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _darkGold,
                        minimumSize: const Size(52, 52),
                      ),
                      tooltip: 'Nuovo preventivo',
                      onPressed: () => apri(const NuovoPreventivoScreen()),
                      icon: const Icon(Icons.add_rounded, size: 30),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                'Riepilogo e accesso rapido',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.38,
              children: [
                _statCard(
                  Icons.receipt_long_rounded,
                  'Preventivi',
                  preventivi,
                  () => apri(const ListaPreventiviScreen()),
                ),
                _statCard(
                  Icons.receipt_long_rounded,
                  'Fatture',
                  fatture,
                  () => apri(const ListaFattureScreen()),
                ),
                _statCard(
                  Icons.people_alt_rounded,
                  'Clienti',
                  clienti,
                  () => apri(const ClientiScreen()),
                ),
                _statCard(
                  Icons.inventory_2_rounded,
                  'Prodotti / Servizi',
                  prodotti,
                  () => apri(const ProdottiScreen()),
                ),
                _statCard(
                  Icons.payments_rounded,
                  'Acconti',
                  acconti,
                  () => apri(const AccontiScreen()),
                ),
                _actionCard(
                  Icons.request_quote_rounded,
                  'Crea fattura',
                  () => apri(const CreaFatturaScreen()),
                ),
                _actionCard(
                  Icons.notifications_active_rounded,
                  'Notifiche',
                  () => apri(const NotificheScreen()),
                ),
                _actionCard(
                  Icons.backup_rounded,
                  'Backup e dati',
                  () => apri(const BackupScreen()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    IconData icon,
    String label,
    int value,
    VoidCallback onTap,
  ) {
    return Card(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _cream,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _darkGold, size: 29),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? '…' : '$value',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard(IconData icon, String title, VoidCallback onTap) {
    return Card(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _cream,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 31, color: _darkGold),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


Future<String?> selezionaCliente(BuildContext context) async {
  final clienti = await DatabaseHelper.instance.getClienti();
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final filtrati = clienti.where((c) {
            final q = query.toLowerCase();
            final nome = (c['nome'] ?? '').toString().toLowerCase();
            final piva = (c['partita_iva'] ?? '').toString().toLowerCase();
            final cf = (c['codice_fiscale'] ?? '').toString().toLowerCase();
            final parrocchia = (c['parrocchia'] ?? '').toString().toLowerCase();
            return nome.contains(q) || piva.contains(q) || cf.contains(q) || parrocchia.contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Seleziona cliente'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setDialogState(() => query = v),
                    decoration: const InputDecoration(
                      labelText: 'Cerca cliente',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: filtrati.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Nessun cliente trovato.'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtrati.length,
                            itemBuilder: (_, i) => ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_outline),
                              ),
                              title: Text(filtrati[i]['nome']),
                              subtitle: Text(
                                [
                                  filtrati[i]['telefono'],
                                  filtrati[i]['email'],
                                  if ((filtrati[i]['parrocchia'] ?? '').toString().isNotEmpty) 'Parrocchia: ${filtrati[i]['parrocchia']}',
                                ]
                                    .where((x) => (x ?? '').toString().isNotEmpty)
                                    .join(' • '),
                              ),
                              onTap: () => Navigator.pop(
                                dialogContext,
                                filtrati[i]['nome'].toString(),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ANNULLA'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<Map<String, dynamic>?> selezionaProdotto(BuildContext context) async {
  final prodotti = await DatabaseHelper.instance.getProdotti();
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      String query = '';
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final filtrati = prodotti.where((p) {
            final nome = (p['nome'] ?? '').toString().toLowerCase();
            return nome.contains(query.toLowerCase());
          }).toList();
          return AlertDialog(
            title: const Text('Seleziona prodotto / servizio'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setDialogState(() => query = v),
                    decoration: const InputDecoration(
                      labelText: 'Cerca servizio',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: filtrati.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Nessun servizio trovato.'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filtrati.length,
                            itemBuilder: (_, i) => ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(filtrati[i]['nome']),
                              trailing: Text(
                                '€ ${(filtrati[i]['prezzo'] as num).toDouble().toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () => Navigator.pop(
                                dialogContext,
                                Map<String, dynamic>.from(filtrati[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ANNULLA'),
              ),
            ],
          );
        },
      );
    },
  );
}

class NuovoPreventivoScreen extends StatefulWidget {
  const NuovoPreventivoScreen({super.key});

  @override
  State<NuovoPreventivoScreen> createState() => _NuovoPreventivoScreenState();
}

class _NuovoPreventivoScreenState extends State<NuovoPreventivoScreen> {
  final clienteController = TextEditingController();
  final prodottoController = TextEditingController();
  final prezzoController = TextEditingController();
  final quantitaController = TextEditingController(text: '1');
  final scontoController = TextEditingController(text: '0');

  final List<Map<String, dynamic>> articoli = [];

  final List<Map<String, dynamic>> acconti = [];
  double ivaPercent = 22;
  bool accettato = false;
  bool busy = false;

  double get imponibile => articoli.fold<double>(
        0,
        (sum, x) {
          final prezzo = (x['prezzo'] as num?)?.toDouble() ?? 0;
          final quantita = (x['quantita'] as num?)?.toDouble() ?? 1;
          return sum + (prezzo * quantita);
        },
      );

  double get scontoPercent =>
      double.tryParse(scontoController.text.trim().replaceAll(',', '.')) ?? 0;

  double get sconto =>
      (imponibile * scontoPercent.clamp(0, 100) / 100);

  double get imponibileScontato =>
      (imponibile - sconto).clamp(0, double.infinity).toDouble();

  double get iva => imponibileScontato * ivaPercent / 100;

  double get totale => imponibileScontato + iva;

  Future<void> scegliCliente() async {
    final nome = await selezionaCliente(context);
    if (nome != null && mounted) {
      setState(() => clienteController.text = nome);
    }
  }

  Future<void> scegliServizio() async {
    final prodotto = await selezionaProdotto(context);
    if (prodotto != null && mounted) {
      setState(() {
        prodottoController.text = prodotto['nome'].toString();
        prezzoController.text =
            (prodotto['prezzo'] as num).toDouble().toStringAsFixed(2);
        quantitaController.text = '1';
      });
    }
  }

Future<void> aggiungiAcconto() async {
    final importoController = TextEditingController();
    final dataController = TextEditingController();
    final nuoviAcconti = <Map<String, dynamic>>[];

    try {
      final risultato = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              void aggiungiEContinua() {
                final importo = double.tryParse(
                  importoController.text.trim().replaceAll(',', '.'),
                );
                final data = dataController.text.trim();

                if (importo == null || importo <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Inserisci un importo acconto valido.'),
                    ),
                  );
                  return;
                }

                try {
                  DateFormat('dd/MM/yyyy').parseStrict(data);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Inserisci una data valida nel formato gg/mm/aaaa.')),
                  );
                  return;
                }

                nuoviAcconti.add({
                  'importo': importo,
                  'data': data,
                });

                importoController.clear();
                dataController.clear();
                setDialogState(() {});
              }

              void conferma() {
                final testoImporto = importoController.text.trim();
                if (testoImporto.isNotEmpty) {
                  final primaLunghezza = nuoviAcconti.length;
                  aggiungiEContinua();
                  if (nuoviAcconti.length == primaLunghezza) return;
                }

                if (nuoviAcconti.isNotEmpty) {
                  Navigator.pop(dialogContext, List<Map<String, dynamic>>.from(nuoviAcconti));
                }
              }

              return AlertDialog(
                title: const Text('Aggiungi acconti'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nuoviAcconti.isEmpty
                            ? 'Inserisci uno o più acconti.'
                            : 'Acconti da aggiungere: ${nuoviAcconti.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (nuoviAcconti.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...nuoviAcconti.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${entry.key + 1}. € ${(entry.value['importo'] as double).toStringAsFixed(2)}'
                              '${(entry.value['data'] as String).isEmpty ? '' : ' • ${entry.value['data']}'}',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: importoController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Importo acconto (€)',
                          prefixIcon: Icon(Icons.euro),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dataController,
                        decoration: const InputDecoration(
                          labelText: 'Data scadenza rata (gg/mm/aaaa)',
                          hintText: 'gg/mm/aaaa',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('ANNULLA'),
                  ),
                  OutlinedButton.icon(
                    onPressed: aggiungiEContinua,
                    icon: const Icon(Icons.add),
                    label: const Text('AGGIUNGI ALTRO'),
                  ),
                  FilledButton(
                    onPressed: conferma,
                    child: const Text('SALVA ACCONTI'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (risultato != null && risultato.isNotEmpty && mounted) {
        setState(() {
          acconti.addAll(risultato);
        });
      }
    } finally {
      importoController.dispose();
      dataController.dispose();
    }
  }

  double get totaleAcconti => acconti.fold<double>(
        0,
        (sum, a) => sum + ((a['importo'] as num?)?.toDouble() ?? 0),
      );

  double get saldoResiduo => totale - totaleAcconti;

  @override
  void dispose() {
    clienteController.dispose();
    prodottoController.dispose();
    prezzoController.dispose();
    quantitaController.dispose();
    super.dispose();
  }

  void aggiungiProdotto() {
    final nome = prodottoController.text.trim();
    final prezzo = double.tryParse(
      prezzoController.text.trim().replaceAll(',', '.'),
    );
    final quantita = double.tryParse(
      quantitaController.text.trim().replaceAll(',', '.'),
    );

    if (nome.isEmpty || prezzo == null || prezzo < 0 || quantita == null || quantita <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci descrizione, prezzo e quantità validi.'),
        ),
      );
      return;
    }

    setState(() {
      articoli.add({'nome': nome, 'prezzo': prezzo, 'quantita': quantita});
      prodottoController.clear();
      prezzoController.clear();
      quantitaController.text = '1';
    });
  }

  Future<void> generaPreventivo() async {
    if (busy) return;

    final cliente = clienteController.text.trim();

    if (cliente.isEmpty || articoli.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci il cliente e almeno un prodotto.'),
        ),
      );
      return;
    }

    setState(() => busy = true);

    try {
      final db = DatabaseHelper.instance;
      final numero = await db.prossimoNumeroPreventivo();

      final id = await db.insertPreventivo(
        numero: numero,
        cliente: cliente,
        totale: totale,
        articoli: articoli,
        ivaPercent: ivaPercent,
        accettato: accettato,
        acconti: acconti,
        scontoPercent: scontoPercent,
      );

      final clienti = await db.getClienti();

      if (!clienti.any(
        (c) =>
            (c['nome'] as String).toLowerCase() ==
            cliente.toLowerCase(),
      )) {
        await db.insertCliente(nome: cliente);
      }

      await PdfGenerator.generaECondividiPreventivo(
        numero: numero,
        cliente: cliente,
        articoli: articoli,
        ivaPercent: ivaPercent,
        accettato: accettato,
        acconti: acconti,
        scontoPercent: scontoPercent,
      );

      final notificheProgrammate = await NotificationService().programmaNotificheRate(
        preventivoId: id,
        cliente: cliente,
        acconti: acconti,
      );
      final notificheOk = await NotificationService().notificheAbilitate();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notificheOk
                  ? 'Preventivo $numero salvato: $notificheProgrammate notifiche programmate.'
                  : 'Preventivo $numero salvato. Abilita le notifiche per ricevere gli avvisi.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget _riepilogoRiga(
    String label,
    double value, {
    bool bold = false,
    double size = 16,
  }) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('€ ${value.toStringAsFixed(2)}', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nuovo Preventivo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dati Cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: clienteController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome / Ragione Sociale',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliCliente,
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('SELEZIONA DALL’ANAGRAFICA'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Prodotti / Servizi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: prodottoController,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: quantitaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantità',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: prezzoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo unitario €',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: aggiungiProdotto,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliServizio,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('SCEGLI DA PRODOTTI / SERVIZI'),
              ),
            ),
            const SizedBox(height: 12),
            if (articoli.isNotEmpty)
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: articoli.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final prezzo = (articoli[i]['prezzo'] as num?)?.toDouble() ?? 0;
                    final quantita = (articoli[i]['quantita'] as num?)?.toDouble() ?? 1;
                    final riga = prezzo * quantita;
                    return ListTile(
                      title: Text(articoli[i]['nome'].toString()),
                      subtitle: Text(
                        'Quantità: ${quantita.toStringAsFixed(2)}  •  Prezzo unitario: € ${prezzo.toStringAsFixed(2)}  •  Totale: € ${riga.toStringAsFixed(2)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => articoli.removeAt(i));
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: scontoController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Sconto (%)',
                        hintText: 'Inserisci la percentuale di sconto',
                        prefixIcon: Icon(Icons.percent),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _riepilogoRiga('Imponibile', imponibile),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'IVA',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        DropdownButton<double>(
                          value: ivaPercent,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Esente / 0%')),
                            DropdownMenuItem(value: 4, child: Text('4%')),
                            DropdownMenuItem(value: 5, child: Text('5%')),
                            DropdownMenuItem(value: 10, child: Text('10%')),
                            DropdownMenuItem(value: 22, child: Text('22%')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => ivaPercent = v);
                          },
                        ),
                        Text(ivaPercent == 0 ? 'FUORI CAMPO IVA FCI' : '€ ${iva.toStringAsFixed(2)}'),
                      ],
                    ),
                    const Divider(),
                    if (scontoPercent > 0)
                      _riepilogoRiga('Sconto ${scontoPercent.toStringAsFixed(0)}%', -sconto),
                    if (scontoPercent > 0)
                      _riepilogoRiga('Imponibile scontato', imponibileScontato),
                    _riepilogoRiga(
                      'TOTALE',
                      totale,
                      bold: true,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Acconti',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        OutlinedButton.icon(
                          onPressed: aggiungiAcconto,
                          icon: const Icon(Icons.add),
                          label: const Text('AGGIUNGI'),
                        ),
                      ],
                    ),
                    if (acconti.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Nessun acconto inserito.'),
                      )
                    else
                      ...acconti.asMap().entries.map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.payments_outlined),
                          title: Text('Acconto ${entry.key + 1}'),
                          subtitle: Text(
                            (entry.value['data'] ?? '').toString().isEmpty
                                ? 'Data non indicata'
                                : entry.value['data'].toString(),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '€ ${((entry.value['importo'] as num).toDouble()).toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                onPressed: () => setState(() => acconti.removeAt(entry.key)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (acconti.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Totale acconti'),
                          Text('€ ${totaleAcconti.toStringAsFixed(2)}'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Saldo residuo', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('€ ${saldoResiduo.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: CheckboxListTile(
                value: accettato,
                onChanged: (v) => setState(() => accettato = v ?? false),
                title: const Text(
                  'Preventivo accettato dal cliente',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Se selezionato, il PDF verrà generato con la dicitura RICEVUTA.',
                ),
                secondary: const Icon(Icons.check_circle_outline),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: busy ? null : generaPreventivo,
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  busy
                      ? 'SALVATAGGIO...'
                      : 'GENERA PDF CON ACCONTI',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ListaPreventiviScreen extends StatefulWidget {
  const ListaPreventiviScreen({super.key});

  @override
  State<ListaPreventiviScreen> createState() =>
      _ListaPreventiviScreenState();
}

class _ListaPreventiviScreenState extends State<ListaPreventiviScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> preventivi = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _carica();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => loading = true);
    final data = await DatabaseHelper.instance.getPreventivi();

    if (mounted) {
      setState(() {
        preventivi = data;
        loading = false;
      });
    }
  }

  Future<void> _elimina(Map<String, dynamic> preventivo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare preventivo?'),
        content: Text(
          'Vuoi eliminare ${preventivo['numero']} '
          'del cliente "${preventivo['cliente']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final db = await DatabaseHelper.instance.database;

      await db.delete(
        'preventivi',
        where: 'id = ?',
        whereArgs: [preventivo['id']],
      );

      await _carica();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preventivo eliminato.')),
        );
      }
    }
  }

  void _mostraDettagli(Map<String, dynamic> x) {
    final data = DateTime.parse(x['data']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 25,
                    child: Icon(Icons.receipt_long),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      x['numero'],
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 28),
              _detailRow(Icons.person_outline, 'Cliente', x['cliente']),
              _detailRow(
                Icons.calendar_today_outlined,
                'Data',
                DateFormat('dd/MM/yyyy').format(data),
              ),
              _detailRow(
                Icons.payments_outlined,
                'Totale',
                '€ ${(x['totale'] as num).toStringAsFixed(2)}',
              ),
              _detailRow(
                Icons.check_circle_outline,
                'Stato',
                (x['accettato'] as num?)?.toInt() == 1 ? 'ACCETTATO / RICEVUTA' : 'IN ATTESA',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ModificaPreventivoScreen(preventivo: x),
                          ),
                        ).then((_) => _carica());
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('MODIFICA'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _elimina(x);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('ELIMINA'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreaFatturaScreen(preventivo: x),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('CREA FATTURA DA PREVENTIVO'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await PdfGenerator.generaECondividiPreventivo(
                      numero: x['numero'],
                      cliente: x['cliente'],
                      articoli: _articoliDaPreventivo(x),
                      ivaPercent: (x['iva_percent'] as num?)?.toDouble() ?? 0,
                      accettato: (x['accettato'] as num?)?.toInt() == 1,
                      acconti: _accontiDaPreventivo(x),
                      scontoPercent: (x['sconto_percent'] as num?)?.toDouble() ?? 0,
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('RIGENERA / CONDIVIDI PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _articoliDaPreventivo(
    Map<String, dynamic> x,
  ) {
    try {
      final raw = jsonDecode((x['articoli'] ?? '[]').toString());

      return (raw as List).map((e) {
        return {
          'nome': e['nome'].toString(),
          'prezzo': (e['prezzo'] as num).toDouble(),
          'quantita': (e['quantita'] as num?)?.toDouble() ?? 1,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _accontiDaPreventivo(Map<String, dynamic> x) {
    try {
      final raw = jsonDecode((x['acconti'] ?? '[]').toString());
      return (raw as List).map((e) => {
        'importo': (e['importo'] as num?)?.toDouble() ?? 0,
        'data': (e['data'] ?? '').toString(),
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(value, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    final filtrati = preventivi.where((x) {
      if (q.isEmpty) return true;

      final numero = (x['numero'] ?? '').toString().toLowerCase();
      final cliente = (x['cliente'] ?? '').toString().toLowerCase();

      return numero.contains(q) || cliente.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Lista Preventivi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _carica,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carica,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Cerca numero o cliente',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (filtrati.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${filtrati.length} '
                        '${filtrati.length == 1 ? 'preventivo' : 'preventivi'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (filtrati.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isEmpty
                                ? 'Nessun preventivo salvato.'
                                : 'Nessun preventivo trovato.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ...filtrati.map((x) {
                    final data = DateTime.parse(x['data']);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 9),
                      child: ListTile(
                        onTap: () => _mostraDettagli(x),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long),
                        ),
                        title: Text(
                          x['numero'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${x['cliente']}\n'
                            '${DateFormat('dd/MM/yyyy').format(data)}',
                          ),
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '€ ${(x['totale'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Modifica preventivo',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ModificaPreventivoScreen(
                                          preventivo: x,
                                        ),
                                      ),
                                    ).then((_) => _carica());
                                  },
                                  icon: const Icon(Icons.edit_outlined, size: 22),
                                ),
                                const Icon(Icons.chevron_right, size: 20),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class ModificaPreventivoScreen extends StatefulWidget {
  final Map<String, dynamic> preventivo;

  const ModificaPreventivoScreen({
    super.key,
    required this.preventivo,
  });

  @override
  State<ModificaPreventivoScreen> createState() =>
      _ModificaPreventivoScreenState();
}

class _ModificaPreventivoScreenState
    extends State<ModificaPreventivoScreen> {
  late final TextEditingController clienteController;

  final prodottoController = TextEditingController();
  final prezzoController = TextEditingController();
  final quantitaController = TextEditingController(text: '1');
  late final TextEditingController scontoController;

  late List<Map<String, dynamic>> articoli;
  late List<Map<String, dynamic>> acconti;
  late double ivaPercent;
  late bool accettato;

  bool busy = false;

  double get imponibile => articoli.fold<double>(
        0,
        (sum, x) {
          final prezzo = (x['prezzo'] as num?)?.toDouble() ?? 0;
          final quantita = (x['quantita'] as num?)?.toDouble() ?? 1;
          return sum + (prezzo * quantita);
        },
      );

  double get scontoPercent =>
      double.tryParse(scontoController.text.trim().replaceAll(',', '.')) ?? 0;

  double get sconto =>
      (imponibile * scontoPercent.clamp(0, 100) / 100);

  double get imponibileScontato =>
      (imponibile - sconto).clamp(0, double.infinity).toDouble();

  double get iva => imponibileScontato * ivaPercent / 100;

  double get totale => imponibileScontato + iva;

  Future<void> scegliCliente() async {
    final nome = await selezionaCliente(context);
    if (nome != null && mounted) {
      setState(() => clienteController.text = nome);
    }
  }

  Future<void> scegliServizio() async {
    final prodotto = await selezionaProdotto(context);
    if (prodotto != null && mounted) {
      setState(() {
        prodottoController.text = prodotto['nome'].toString();
        prezzoController.text =
            (prodotto['prezzo'] as num).toDouble().toStringAsFixed(2);
        quantitaController.text = '1';
      });
    }
  }

  List<Map<String, dynamic>> _parseAcconti(dynamic rawValue) {
    try {
      final raw = jsonDecode((rawValue ?? '[]').toString());
      return (raw as List).map((e) => {
        'importo': (e['importo'] as num?)?.toDouble() ?? 0,
        'data': (e['data'] ?? '').toString(),
      }).toList();
    } catch (_) {
      return [];
    }
  }

Future<void> aggiungiAcconto() async {
    final importoController = TextEditingController();
    final dataController = TextEditingController();
    final nuoviAcconti = <Map<String, dynamic>>[];

    try {
      final risultato = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              void aggiungiEContinua() {
                final importo = double.tryParse(
                  importoController.text.trim().replaceAll(',', '.'),
                );
                final data = dataController.text.trim();

                if (importo == null || importo <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Inserisci un importo acconto valido.'),
                    ),
                  );
                  return;
                }

                try {
                  DateFormat('dd/MM/yyyy').parseStrict(data);
                } catch (_) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Inserisci una data valida nel formato gg/mm/aaaa.')),
                  );
                  return;
                }

                nuoviAcconti.add({
                  'importo': importo,
                  'data': data,
                });

                importoController.clear();
                dataController.clear();
                setDialogState(() {});
              }

              void conferma() {
                final testoImporto = importoController.text.trim();
                if (testoImporto.isNotEmpty) {
                  final primaLunghezza = nuoviAcconti.length;
                  aggiungiEContinua();
                  if (nuoviAcconti.length == primaLunghezza) return;
                }

                if (nuoviAcconti.isNotEmpty) {
                  Navigator.pop(dialogContext, List<Map<String, dynamic>>.from(nuoviAcconti));
                }
              }

              return AlertDialog(
                title: const Text('Aggiungi acconti'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nuoviAcconti.isEmpty
                            ? 'Inserisci uno o più acconti.'
                            : 'Acconti da aggiungere: ${nuoviAcconti.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (nuoviAcconti.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...nuoviAcconti.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${entry.key + 1}. € ${(entry.value['importo'] as double).toStringAsFixed(2)}'
                              '${(entry.value['data'] as String).isEmpty ? '' : ' • ${entry.value['data']}'}',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: importoController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Importo acconto (€)',
                          prefixIcon: Icon(Icons.euro),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dataController,
                        decoration: const InputDecoration(
                          labelText: 'Data scadenza rata (gg/mm/aaaa)',
                          hintText: 'gg/mm/aaaa',
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('ANNULLA'),
                  ),
                  OutlinedButton.icon(
                    onPressed: aggiungiEContinua,
                    icon: const Icon(Icons.add),
                    label: const Text('AGGIUNGI ALTRO'),
                  ),
                  FilledButton(
                    onPressed: conferma,
                    child: const Text('SALVA ACCONTI'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (risultato != null && risultato.isNotEmpty && mounted) {
        final aggiunti = List<Map<String, dynamic>>.from(risultato);
        try {
          final preventivoId = (widget.preventivo['id'] as num).toInt();
          final nuovaLista = <Map<String, dynamic>>[
            ...acconti,
            ...aggiunti,
          ];

          // Salvataggio diretto degli acconti: non dipende dalla generazione
          // del PDF e non riscrive gli altri dati del preventivo.
          final updated = await DatabaseHelper.instance.updateAccontiPreventivo(
            id: preventivoId,
            acconti: nuovaLista,
          );

          if (updated == 0) {
            throw Exception('Preventivo non trovato nel database.');
          }

          final notificheProgrammate = await NotificationService().programmaNotificheRate(
            preventivoId: preventivoId,
            cliente: clienteController.text.trim(),
            acconti: nuovaLista,
          );

          if (mounted) {
            setState(() {
              acconti = List<Map<String, dynamic>>.from(nuovaLista);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  aggiunti.length == 1
                      ? 'Acconto aggiunto e salvato. $notificheProgrammate notifica/e programmate.'
                      : '${aggiunti.length} acconti aggiunti e salvati. $notificheProgrammate notifiche programmate.',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Impossibile salvare l'acconto: $e")),
            );
          }
        }
      }
    } finally {
      importoController.dispose();
      dataController.dispose();
    }
  }

  double get totaleAcconti => acconti.fold<double>(
        0, (sum, a) => sum + ((a['importo'] as num?)?.toDouble() ?? 0));
  double get saldoResiduo => totale - totaleAcconti;

  @override
  void initState() {
    super.initState();

    clienteController = TextEditingController(
      text: widget.preventivo['cliente'],
    );
    scontoController = TextEditingController(
      text: ((widget.preventivo['sconto_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(0),
    );

    acconti = _parseAcconti(widget.preventivo['acconti']);
    ivaPercent =
        (widget.preventivo['iva_percent'] as num?)?.toDouble() ?? 0;
    accettato = (widget.preventivo['accettato'] as num?)?.toInt() == 1;

    try {
      final raw = jsonDecode(
        (widget.preventivo['articoli'] ?? '[]').toString(),
      );

      articoli = (raw as List).map((e) {
        return {
          'nome': e['nome'].toString(),
          'prezzo': (e['prezzo'] as num?)?.toDouble() ?? 0,
          'quantita': (e['quantita'] as num?)?.toDouble() ?? 1,
        };
      }).toList();
    } catch (_) {
      articoli = [];
    }
  }

  @override
  void dispose() {
    clienteController.dispose();
    prodottoController.dispose();
    prezzoController.dispose();
    quantitaController.dispose();
    scontoController.dispose();
    super.dispose();
  }

  void aggiungi() {
    final nome = prodottoController.text.trim();
    final prezzo = double.tryParse(
      prezzoController.text.trim().replaceAll(',', '.'),
    );
    final quantita = double.tryParse(
      quantitaController.text.trim().replaceAll(',', '.'),
    );

    if (nome.isEmpty || prezzo == null || prezzo < 0 || quantita == null || quantita <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci descrizione, prezzo e quantità validi.'),
        ),
      );
      return;
    }

    setState(() {
      articoli.add({'nome': nome, 'prezzo': prezzo, 'quantita': quantita});
      prodottoController.clear();
      prezzoController.clear();
      quantitaController.text = '1';
    });
  }

  Future<void> salva() async {
    if (busy) return;

    final cliente = clienteController.text.trim();

    if (cliente.isEmpty || articoli.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci il cliente e almeno un prodotto.'),
        ),
      );
      return;
    }

    setState(() => busy = true);

    try {
      final db = DatabaseHelper.instance;
      final preventivoId =
          (widget.preventivo['id'] as num).toInt();

      final updated = await db.updatePreventivo(
        id: preventivoId,
        cliente: cliente,
        totale: totale,
        articoli: articoli,
        ivaPercent: ivaPercent,
        accettato: accettato,
        acconti: acconti,
        scontoPercent: scontoPercent,
      );

      if (updated == 0) {
        throw Exception('Preventivo non trovato nel database.');
      }

      await PdfGenerator.generaECondividiPreventivo(
        numero: widget.preventivo['numero'],
        cliente: cliente,
        articoli: articoli,
        ivaPercent: ivaPercent,
        accettato: accettato,
        acconti: acconti,
        scontoPercent: scontoPercent,
      );

      final notificheProgrammate = await NotificationService().programmaNotificheRate(
        preventivoId: preventivoId,
        cliente: cliente,
        acconti: acconti,
      );
      final notificheOk = await NotificationService().notificheAbilitate();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notificheOk
                  ? 'Preventivo modificato: $notificheProgrammate notifiche programmate.'
                  : 'Preventivo modificato. Abilita le notifiche per ricevere gli avvisi.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget _riepilogoRiga(
    String label,
    double value, {
    bool bold = false,
    double size = 16,
  }) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.w500,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('€ ${value.toStringAsFixed(2)}', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Modifica ${widget.preventivo['numero']}'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dati Cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: clienteController,
              decoration: const InputDecoration(
                labelText: 'Nome / Ragione Sociale',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliCliente,
                icon: const Icon(Icons.people_alt_outlined),
                label: const Text('SELEZIONA DALL’ANAGRAFICA'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Prodotti / Servizi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: prodottoController,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: quantitaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantità',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: prezzoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo unitario €',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: aggiungi,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: scegliServizio,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('SCEGLI DA PRODOTTI / SERVIZI'),
              ),
            ),
            const SizedBox(height: 12),
            if (articoli.isNotEmpty)
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: articoli.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final prezzo = (articoli[i]['prezzo'] as num?)?.toDouble() ?? 0;
                    final quantita = (articoli[i]['quantita'] as num?)?.toDouble() ?? 1;
                    final riga = prezzo * quantita;
                    return ListTile(
                      title: Text(articoli[i]['nome'].toString()),
                      subtitle: Text(
                        'Quantità: ${quantita.toStringAsFixed(2)}  •  Prezzo unitario: € ${prezzo.toStringAsFixed(2)}  •  Totale: € ${riga.toStringAsFixed(2)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => articoli.removeAt(i));
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: scontoController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Sconto (%)',
                        hintText: 'Inserisci la percentuale di sconto',
                        prefixIcon: Icon(Icons.percent),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _riepilogoRiga('Imponibile', imponibile),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'IVA',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        DropdownButton<double>(
                          value: ivaPercent,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Esente / 0%')),
                            DropdownMenuItem(value: 4, child: Text('4%')),
                            DropdownMenuItem(value: 5, child: Text('5%')),
                            DropdownMenuItem(value: 10, child: Text('10%')),
                            DropdownMenuItem(value: 22, child: Text('22%')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => ivaPercent = v);
                          },
                        ),
                        Text(ivaPercent == 0 ? 'FUORI CAMPO IVA FCI' : '€ ${iva.toStringAsFixed(2)}'),
                      ],
                    ),
                    const Divider(),
                    if (scontoPercent > 0)
                      _riepilogoRiga('Sconto ${scontoPercent.toStringAsFixed(0)}%', -sconto),
                    if (scontoPercent > 0)
                      _riepilogoRiga('Imponibile scontato', imponibileScontato),
                    _riepilogoRiga(
                      'TOTALE',
                      totale,
                      bold: true,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Acconti', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        OutlinedButton.icon(
                          onPressed: aggiungiAcconto,
                          icon: const Icon(Icons.add),
                          label: const Text('AGGIUNGI'),
                        ),
                      ],
                    ),
                    if (acconti.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Nessun acconto inserito.'),
                      )
                    else
                      ...acconti.asMap().entries.map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.payments_outlined),
                          title: Text('Acconto ${entry.key + 1}'),
                          subtitle: Text(
                            (entry.value['data'] ?? '').toString().isEmpty
                                ? 'Data non indicata'
                                : entry.value['data'].toString(),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('€ ${((entry.value['importo'] as num).toDouble()).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                onPressed: () => setState(() => acconti.removeAt(entry.key)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (acconti.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Totale acconti'),
                          Text('€ ${totaleAcconti.toStringAsFixed(2)}'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Saldo residuo', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('€ ${saldoResiduo.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: CheckboxListTile(
                value: accettato,
                onChanged: (v) => setState(() => accettato = v ?? false),
                title: const Text(
                  'Preventivo accettato dal cliente',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Se selezionato, il PDF verrà generato con la dicitura RICEVUTA.',
                ),
                secondary: const Icon(Icons.check_circle_outline),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: busy ? null : salva,
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  busy
                      ? 'SALVATAGGIO...'
                      : 'SALVA E RIGENERA PDF',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClientiScreen extends StatefulWidget {
  const ClientiScreen({super.key});

  @override
  State<ClientiScreen> createState() => _ClientiScreenState();
}

class _ClientiScreenState extends State<ClientiScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> clienti = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => loading = true);
    final data = await DatabaseHelper.instance.getClienti();

    if (mounted) {
      setState(() {
        clienti = data;
        loading = false;
      });
    }
  }

  Future<void> _formCliente([Map<String, dynamic>? cliente]) async {
    final nome = TextEditingController(text: cliente?['nome'] ?? '');
    final telefono =
        TextEditingController(text: cliente?['telefono'] ?? '');
    final email = TextEditingController(text: cliente?['email'] ?? '');
    final indirizzo =
        TextEditingController(text: cliente?['indirizzo'] ?? '');
    final partitaIva =
        TextEditingController(text: cliente?['partita_iva'] ?? '');
    final codiceFiscale =
        TextEditingController(text: cliente?['codice_fiscale'] ?? '');
    final parrocchia =
        TextEditingController(text: cliente?['parrocchia'] ?? '');
    final key = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente == null ? 'Nuovo cliente' : 'Modifica cliente',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: nome,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome / Ragione Sociale',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Inserisci il nome'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: parrocchia,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Parrocchia',
                    prefixIcon: Icon(Icons.church_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefono',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: indirizzo,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Indirizzo',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: partitaIva,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Partita IVA',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: codiceFiscale,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Codice Fiscale',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (!key.currentState!.validate()) return;

                      if (cliente == null) {
                        await DatabaseHelper.instance.insertCliente(
                          nome: nome.text.trim(),
                          telefono: telefono.text.trim(),
                          email: email.text.trim(),
                          indirizzo: indirizzo.text.trim(),
                          partitaIva: partitaIva.text.trim(),
                          codiceFiscale: codiceFiscale.text.trim(),
                          parrocchia: parrocchia.text.trim(),
                        );
                      } else {
                        await DatabaseHelper.instance.updateCliente(
                          id: cliente['id'],
                          nome: nome.text.trim(),
                          telefono: telefono.text.trim(),
                          email: email.text.trim(),
                          indirizzo: indirizzo.text.trim(),
                          partitaIva: partitaIva.text.trim(),
                          codiceFiscale: codiceFiscale.text.trim(),
                          parrocchia: parrocchia.text.trim(),
                        );
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      await _carica();
                    },
                    icon: const Icon(Icons.save),
                    label: Text(
                      cliente == null
                          ? 'SALVA CLIENTE'
                          : 'SALVA MODIFICHE',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nome.dispose();
    telefono.dispose();
    email.dispose();
    indirizzo.dispose();
    partitaIva.dispose();
    codiceFiscale.dispose();
    parrocchia.dispose();
  }

  Future<void> _apriMaps(String indirizzo) async {
    final query = indirizzo.trim();
    if (query.isEmpty) return;

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );

    try {
      final aperto = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!aperto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire Google Maps.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire Google Maps.')),
        );
      }
    }
  }

  Future<void> _elimina(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare cliente?'),
        content: Text('Vuoi eliminare "${c['nome']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DatabaseHelper.instance.deleteCliente(c['id']);
      await _carica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    final filtrati = clienti.where((c) {
      return '${c['nome']} ${c['telefono']} ${c['email']} ${c['parrocchia'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clienti'),
        actions: [
          IconButton(
            onPressed: _carica,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formCliente(),
        icon: const Icon(Icons.add),
        label: const Text('Nuovo cliente'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carica,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Cerca cliente',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (filtrati.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.people_alt_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isEmpty
                                ? 'Nessun cliente salvato.'
                                : 'Nessun cliente trovato.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ...filtrati.map((c) {
                    final dettagli = [
                      if ((c['telefono'] ?? '').toString().isNotEmpty)
                        c['telefono'],
                      if ((c['email'] ?? '').toString().isNotEmpty)
                        c['email'],
                      if ((c['indirizzo'] ?? '').toString().isNotEmpty)
                        c['indirizzo'],
                      if ((c['parrocchia'] ?? '').toString().isNotEmpty)
                        'Parrocchia: ${c['parrocchia']}',
                    ].join('\n');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(
                          c['nome'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(dettagli),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((c['indirizzo'] ?? '').toString().trim().isNotEmpty)
                              IconButton(
                                tooltip: 'Apri in Google Maps',
                                icon: const Icon(Icons.map_outlined),
                                onPressed: () => _apriMaps(c['indirizzo'].toString()),
                              ),
                            PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _formCliente(c);
                                } else {
                                  _elimina(c);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Modifica'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Elimina'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}

class ProdottiScreen extends StatefulWidget {
  const ProdottiScreen({super.key});

  @override
  State<ProdottiScreen> createState() => _ProdottiScreenState();
}

class _ProdottiScreenState extends State<ProdottiScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> prodotti = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => loading = true);
    final data = await DatabaseHelper.instance.getProdotti();

    if (mounted) {
      setState(() {
        prodotti = data;
        loading = false;
      });
    }
  }

  Future<void> _formProdotto([Map<String, dynamic>? prodotto]) async {
    final nome = TextEditingController(text: prodotto?['nome'] ?? '');

    final prezzo = TextEditingController(
      text: prodotto == null
          ? ''
          : (prodotto['prezzo'] as num).toStringAsFixed(2),
    );

    final key = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prodotto == null
                      ? 'Nuovo prodotto / servizio'
                      : 'Modifica prodotto / servizio',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: nome,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nome prodotto / servizio',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Inserisci il nome'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: prezzo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Prezzo €',
                    prefixIcon: Icon(Icons.euro),
                  ),
                  validator: (v) {
                    final value = double.tryParse(
                      (v ?? '').trim().replaceAll(',', '.'),
                    );

                    if (value == null || value < 0) {
                      return 'Inserisci un prezzo valido';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (!key.currentState!.validate()) return;

                      final value = double.parse(
                        prezzo.text.trim().replaceAll(',', '.'),
                      );

                      if (prodotto == null) {
                        await DatabaseHelper.instance.insertProdotto(
                          nome: nome.text.trim(),
                          prezzo: value,
                        );
                      } else {
                        await DatabaseHelper.instance.updateProdotto(
                          id: prodotto['id'],
                          nome: nome.text.trim(),
                          prezzo: value,
                        );
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      await _carica();
                    },
                    icon: const Icon(Icons.save),
                    label: Text(
                      prodotto == null
                          ? 'SALVA PRODOTTO'
                          : 'SALVA MODIFICHE',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nome.dispose();
    prezzo.dispose();
  }

  Future<void> _elimina(Map<String, dynamic> prodotto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare prodotto?'),
        content: Text('Vuoi eliminare "${prodotto['nome']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANNULLA'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINA'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await DatabaseHelper.instance.deleteProdotto(prodotto['id']);
      await _carica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();

    final filtrati = prodotti.where((prodotto) {
      return (prodotto['nome'] ?? '')
          .toString()
          .toLowerCase()
          .contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prodotti / Servizi'),
        actions: [
          IconButton(
            onPressed: _carica,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formProdotto(),
        icon: const Icon(Icons.add),
        label: const Text('Nuovo prodotto / servizio'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carica,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Cerca prodotto / servizio',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (q.isEmpty && filtrati.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${filtrati.length} prodotti / servizi',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (filtrati.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isEmpty
                                ? 'Nessun prodotto o servizio salvato.'
                                : 'Nessun prodotto trovato.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          if (q.isEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _formProdotto(),
                              icon: const Icon(Icons.add),
                              label: const Text(
                                'Aggiungi il primo prodotto',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ...filtrati.map((prodotto) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(
                          prodotto['nome'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text('Prezzo di listino'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '€ ${(prodotto['prezzo'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _formProdotto(prodotto);
                                } else {
                                  _elimina(prodotto);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Modifica'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Elimina'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}



class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool busy = false;
  String? lastMessage;

  Future<void> _esporta() async {
    setState(() => busy = true);
    try {
      final file = await DatabaseHelper.instance.exportBackup();
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Backup Preventivi',
        text: 'Backup clienti, servizi e preventivi.',
      );
      if (mounted) setState(() => lastMessage = 'Backup esportato correttamente.');
    } catch (e) {
      if (mounted) setState(() => lastMessage = 'Errore esportazione: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _importa() async {
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) {
        setState(() => busy = false);
        return;
      }
      if (!mounted) return;
      final conferma = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importa backup'),
          content: const Text(
            'L’importazione sostituirà i dati attuali di clienti, servizi, preventivi e acconti. Continuare?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULLA')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('IMPORTA')),
          ],
        ),
      );
      if (conferma != true) return;
      await DatabaseHelper.instance.importBackup(File(result.files.single.path!));
      if (mounted) setState(() => lastMessage = 'Backup importato correttamente.');
    } catch (e) {
      if (mounted) setState(() => lastMessage = 'Backup non valido: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _creaAutomatico() async {
    setState(() => busy = true);
    try {
      final file = await DatabaseHelper.instance.createAutomaticBackup();
      if (mounted) setState(() => lastMessage = 'Backup automatico aggiornato.');
      debugPrint('Backup automatico: ${file.path}');
    } catch (e) {
      if (mounted) setState(() => lastMessage = 'Errore backup automatico: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup e dati')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: const Text('Backup automatico'),
              subtitle: const Text('Viene aggiornato automaticamente dopo ogni modifica dei dati.'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: busy ? null : _creaAutomatico,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : _esporta,
            icon: const Icon(Icons.ios_share),
            label: const Text('ESPORTA BACKUP'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : _importa,
            icon: const Icon(Icons.file_open),
            label: const Text('IMPORTA BACKUP'),
          ),
          if (busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (lastMessage != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(lastMessage!),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Il backup contiene clienti, prodotti/servizi, preventivi e acconti. L’importazione sostituisce i dati presenti sul dispositivo.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class NotificheScreen extends StatefulWidget {
  const NotificheScreen({super.key});

  @override
  State<NotificheScreen> createState() => _NotificheScreenState();
}

class _NotificheScreenState extends State<NotificheScreen> {
  bool? abilitate;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _aggiorna();
  }

  Future<void> _aggiorna() async {
    final stato = await NotificationService().notificheAbilitate();
    if (!mounted) return;
    setState(() {
      abilitate = stato;
      loading = false;
    });
  }

  Future<void> _abilita() async {
    setState(() => loading = true);
    await NotificationService().preparaPermessi();
    await _aggiorna();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifiche e scadenze')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              abilitate == true
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              size: 70,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              loading
                  ? 'Controllo autorizzazioni...'
                  : abilitate == true
                      ? 'Notifiche abilitate'
                      : 'Notifiche non abilitate',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              abilitate == true
                  ? 'Le scadenze delle acconti possono essere segnalate automaticamente.'
                  : 'Per ricevere gli avvisi delle acconti, abilita le notifiche per questa app nelle impostazioni di Android.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FutureBuilder<List<PendingNotificationRequest>>(
              future: NotificationService().programmate(),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Notifiche programmate'),
                    subtitle: Text(
                      count == 0
                          ? 'Nessuna scadenza attualmente programmata.'
                          : '$count avviso/i programmato/i.',
                    ),
                    trailing: IconButton(
                      tooltip: 'Aggiorna',
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: loading ? null : _abilita,
              icon: const Icon(Icons.notifications_active),
              label: const Text('ABILITA / RICHIEDI PERMESSI'),
            ),
            if (abilitate == false) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await NotificationService().apriImpostazioniNotifiche();
                  if (mounted) _aggiorna();
                },
                icon: const Icon(Icons.settings),
                label: const Text('APRI IMPOSTAZIONI ANDROID'),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Le notifiche delle rate vengono inviate alle 09:00 del giorno precedente alla scadenza. Non è necessario attivare gli allarmi esatti.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class AccontiScreen extends StatelessWidget {
  const AccontiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acconti'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getAcconti(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final acconti = snapshot.data!;

          if (acconti.isEmpty) {
            return const _EmptyState(
              icon: Icons.payments_outlined,
              text: 'Nessun acconto inserito.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: acconti.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final x = acconti[index];
              final data = (x['data'] ?? '').toString();

              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.payments_outlined),
                  ),
                  title: Text(
                    '${x['cliente']} • Acconto ${x['indice']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    data.isEmpty
                        ? 'Preventivo: ${x['preventivo']} • Data non indicata'
                        : 'Preventivo: ${x['preventivo']} • Data: $data',
                  ),
                  trailing: Text(
                    '€ ${(x['importo'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 15),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
