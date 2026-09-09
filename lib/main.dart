None
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
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package0/url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
void main() async {
 WidgetsFlutterBinding.ensureInitialized();
 await NotificationService.instance.initialize();
 await DatabaseHelper.instance.createAutomaticBackup();
 await NotificationService.instance.refreshMonthlyReminder();
 runApp(const PreventiviApp());
}
class DatabaseHelper {
 static final DatabaseHelper instance = DatabaseHelper._init();
 static Database? _database;
 DatabaseHelper._init(); Future<Database> get database async {
 if (_database != null) return _database!;
 _database = await _initDB('preventivi_full.db');
 return _database!;
 }
 Future<Database> _initDB(String fileName) async {
 final dbPath = await getDatabasesPath();
 return openDatabase(
 p.join(dbPath, fileName),
 version: 11,
 );
 }
 Future<List<Map<String, dynamic>>> getPreventiviDaSaldare() async {
 final preventivi = await getPreventivi();
 final risultato = <Map<String, dynamic>>[];
 for (final p in preventivi) {
 if ((p['accettato'] as num?)?.toInt() != 1) continue;
 if ((p['pagato'] as num?)?.toInt() == 1) continue;
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
 } catch (_) {} final saldo = totale - totaleAcconti;
 if (saldo > 0.005) {
 risultato.add({
 ...p,
 'saldo': saldo,
 });
 }
 }
 return risultato;
 }
 Future<List<Map<String, dynamic>>> getAcconti() async {
 final preventivi = await getPreventivi();
 final risultato = <Map<String, dynamic>>[];
 for (final p in preventivi) {
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
 } return risultato;
 }
 Future<List<Map<String, dynamic>>> getPreventivi() async {
 return (await database).query('preventivi', orderBy: 'id DESC');
 }
}
i dati in formato JSON.import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart'; import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
void main() async {
 WidgetsFlutterBinding.ensureInitialized();
 await NotificationService.instance.initialize();
 await DatabaseHelper.instance.createAutomaticBackup();
 await NotificationService.instance.refreshMonthlyReminder();
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
 useMaterial3: true, colorScheme: ColorScheme.fromSeed(
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
 elevation: 1.5, shape: RoundedRectangleBorder(
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
 ), ),
 ),
 home: const DashboardScreen(),
 );
 }
}
class NotificationService {
 NotificationService._();
 static final NotificationService instance = NotificationService._();
 final FlutterLocalNotificationsPlugin _plugin =
 FlutterLocalNotificationsPlugin();
 static const _enabledKey = 'monthly_acconti_notifications_enabled';
 static const _notificationId = 7001;
 Future<void> initialize() async {
 tz.initializeTimeZones();
 tz.setLocalLocation(tz.getLocation('Europe/Rome'));
 const android = AndroidInitializationSettings('@mipmap/ic_launcher');
 const darwin = DarwinInitializationSettings();
 const settings = InitializationSettings( android: android,
 iOS: darwin,
 macOS: darwin,
 );
 await _plugin.initialize(settings);
 }
 Future<bool> requestPermission() async {
 final android = _plugin.resolvePlatformSpecificImplementation<
 AndroidFlutterLocalNotificationsPlugin>();
 final granted = await android?.requestNotificationsPermission();
 return granted ?? true;
 }
 Future<bool> isEnabled() async {
 final prefs = await SharedPreferences.getInstance();
 return prefs.getBool(_enabledKey) ?? false;
 }
 Future<void> setEnabled(bool enabled) async {
 final prefs = await SharedPreferences.getInstance();
 await prefs.setBool(_enabledKey, enabled);
 if (!enabled) { await _plugin.cancel(_notificationId);
 return;
 }
 await requestPermission();
 await refreshMonthlyReminder();
 }
 Future<void> refreshMonthlyReminder() async {
 if (!await isEnabled()) return;
 final saldi = await DatabaseHelper.instance.getPreventiviDaSaldare();
 await _plugin.cancel(_notificationId);
 if (saldi.isEmpty) return;
 final totale = saldi.fold<double>(
 0,
 (sum, p) => sum + ((p['saldo'] as num?)?.toDouble() ?? 0),
 );
 final now = tz.TZDateTime.now(tz.local);
 var next = tz.TZDateTime(tz.local, now.year, now.month, 1, 9);
 if (!next.isAfter(now)) {
 final nextMonth = now.month == 12 ? 1 : now.month + 1; final nextYear = now.month == 12 ? now.year + 1 : now.year;
 next = tz.TZDateTime(tz.local, nextYear, nextMonth, 1, 9);
 }
 const details = NotificationDetails(
 android: AndroidNotificationDetails(
 'acconti_mensili',
 'Acconti non saldati',
 channelDescription:
 'Promemoria mensile per i preventivi con saldo ancora da incassare.',
 importance: Importance.high,
 priority: Priority.high,
 ),
 iOS: DarwinNotificationDetails(),
 macOS: DarwinNotificationDetails(),
 );
 await _plugin.zonedSchedule(
 _notificationId,
 'Acconti da saldare',
 saldi.length == 1
 ? 'Hai 1 preventivo con saldo di € ${totale.toStringAsFixed(2)} da
incassare.' : 'Hai ${saldi.length} preventivi con saldo totale di €
${totale.toStringAsFixed(2)} da incassare.',
 next,
 details,
 androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
 matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
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
 final dbPath = await getDatabasesPath(); return openDatabase(
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
 nome TEXT NOT NULL, prezzo REAL NOT NULL
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
 await db.execute(''' CREATE TABLE fatture (
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
 pagata INTEGER NOT NULL DEFAULT 0 )
''');
 },
 onUpgrade: (db, oldVersion, newVersion) async {
 if (oldVersion < 2) {
 await db.execute(
 "ALTER TABLE preventivi ADD COLUMN articoli TEXT NOT NULL
DEFAULT '[]'",
 );
 }
 if (oldVersion < 3) {
 await db.execute(
 "ALTER TABLE preventivi ADD COLUMN iva_percent REAL NOT NULL
DEFAULT 0",
 );
 }
 if (oldVersion < 4) {
 await db.execute(
 "ALTER TABLE clienti ADD COLUMN partita_iva TEXT",
 );
 await db.execute( "ALTER TABLE clienti ADD COLUMN codice_fiscale TEXT",
 );
 }
 if (oldVersion < 5) {
 await db.execute(
 "ALTER TABLE clienti ADD COLUMN parrocchia TEXT",
 );
 }
 if (oldVersion < 6) {
 await db.execute(
 "ALTER TABLE preventivi ADD COLUMN accettato INTEGER NOT NULL
DEFAULT 0",
 );
 }
 if (oldVersion < 7) {
 await db.execute(
 "ALTER TABLE preventivi ADD COLUMN acconti TEXT NOT NULL
DEFAULT '[]'",
 );
 }
 if (oldVersion < 8) { await db.execute(
 "ALTER TABLE preventivi ADD COLUMN sconto_percent REAL NOT
NULL DEFAULT 0",
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
 if (oldVersion < 10) { await db.execute("ALTER TABLE fatture ADD COLUMN iban TEXT");
 }
 if (oldVersion < 11) {
 await db.execute("ALTER TABLE preventivi ADD COLUMN pagato
INTEGER NOT NULL DEFAULT 0");
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
 Future<List<Map<String, dynamic>>> getPreventiviDaSaldare() async {
 final preventivi = await getPreventivi();
 final risultato = <Map<String, dynamic>>[];
 for (final p in preventivi) {
 if ((p['accettato'] as num?)?.toInt() != 1) continue; if ((p['pagato'] as num?)?.toInt() == 1) continue;
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
 } }
 return risultato;
 }
 Future<List<Map<String, dynamic>>> getProdotti() async {
 return (await database).query('prodotti', orderBy: 'nome COLLATE
NOCASE');
 }
 Future<List<Map<String, dynamic>>> getAcconti() async {
 final preventivi = await getPreventivi();
 final risultato = <Map<String, dynamic>>[];
 for (final p in preventivi) {
 if ((p['accettato'] as num?)?.toInt() != 1) continue;
 try {
 final raw = jsonDecode((p['acconti'] ?? '[]').toString());
 if (raw is List) {
 for (var i = 0; i < raw.length; i++) {
 final a = Map<String, dynamic>.from(raw[i] as Map);
 risultato.add({
 'preventivo_id': p['id'],
 'preventivo': p['numero'], 'cliente': p['cliente'],
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
 await autoBackup(); return id;
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
 where: 'id = ?', whereArgs: [id],
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
 'partita_iva': partitaIva, 'codice_fiscale': codiceFiscale,
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
 'nome': nome, 'email': email,
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
 await autoBackup(); return result;
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
 'iva_percent': ivaPercent, 'totale': totale,
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
 final rows = await (await database).rawQuery('SELECT COUNT(*) AS n
FROM fatture');
 final n = (rows.first['n'] as int? ?? 0) + 1; return 'FAT-${DateTime.now().year}-${n.toString().padLeft(4, '0')}';
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
 final id = await (await database).insert('preventivi', { 'numero': numero,
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
 required bool pagato, }) async {
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
 required double totale, required List<Map<String, dynamic>> articoli,
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
 }, where: 'id = ?',
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
 Future<File> createAutomaticBackup() async { final dir = await getApplicationDocumentsDirectory();
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
 if (decoded is! Map<String, dynamic>) { throw const FormatException('Backup non valido.');
 }
 final clienti = List<Map<String, dynamic>>.from(
 (decoded['clienti'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
 );
 final prodotti = List<Map<String, dynamic>>.from(
 (decoded['prodotti'] as List? ?? []).map((e) => Map<String,
dynamic>.from(e)),
 );
 final preventivi = List<Map<String, dynamic>>.from(
 (decoded['preventivi'] as List? ?? []).map((e) => Map<String,
dynamic>.from(e)),
 );
 final fatture = List<Map<String, dynamic>>.from(
 (decoded['fatture'] as List? ?? []).map((e) => Map<String,
dynamic>.from(e)),
 );
 final db = await database;
 await db.transaction((txn) async {
 await txn.delete('preventivi');
 await txn.delete('prodotti');
 await txn.delete('clienti'); await txn.delete('fatture');
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
