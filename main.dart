import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef M = Map<String, dynamic>;

double n(dynamic v) => v is num ? v.toDouble() : 0.0;
double pd(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0.0;
String f(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
int _lastId = 0;
int nid() {
  var t = DateTime.now().microsecondsSinceEpoch;
  if (t <= _lastId) t = _lastId + 1;
  _lastId = t;
  return t;
}
String newCode() =>
    (DateTime.now().millisecondsSinceEpoch % 1000000000000).toString().padLeft(12, '0');

class Db extends ChangeNotifier {
  static final Db i = Db._();
  Db._();
  static const keys = ['products', 'customers', 'sales', 'repairs', 'expenses', 'users', 'suppliers', 'purchases', 'closings', 'logs', 'returns', 'payments', 'moves'];
  final Map<String, List<M>> t = {for (final k in keys) k: <M>[]};
  SharedPreferences? p;
  M? me;
  List<M> get products => t['products']!;
  List<M> get customers => t['customers']!;
  List<M> get sales => t['sales']!;
  List<M> get repairs => t['repairs']!;
  List<M> get expenses => t['expenses']!;
  List<M> get users => t['users']!;
  List<M> get suppliers => t['suppliers']!;
  List<M> get purchases => t['purchases']!;
  List<M> get closings => t['closings']!;
  List<M> get logs => t['logs']!;
  List<M> get returns => t['returns']!;
  List<M> get payments => t['payments']!;
  List<M> get moves => t['moves']!;
  void move(M p, String type, num delta, [String note = '']) {
    moves.add({
      'id': nid(),
      'date': DateTime.now().toIso8601String(),
      'pid': p['id'],
      'name': p['name'],
      'type': type,
      'delta': delta,
      'after': n(p['qty']),
      'by': me?['name'] ?? '-',
      'note': note
    });
    if (moves.length > 3000) moves.removeAt(0);
  }
  String? lastBackup;
  void log(String x) {
    logs.add({'id': nid(), 'date': DateTime.now().toIso8601String(), 'by': me?['name'] ?? '-', 'text': x});
    if (logs.length > 500) logs.removeAt(0);
  }

  Database? sdb;
  final Map<String, Map<int, String>> snap = {
    for (final k in keys) k: <int, String>{}
  };
  Future<void> q = Future<void>.value();

  List<M> decode(String s) => (jsonDecode(s) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    lastBackup = p!.getString('lastBackup');
    final d = await openDatabase('${await getDatabasesPath()}/itqan.db',
        version: 1,
        onCreate: (x, v) => x.execute(
            'CREATE TABLE docs(tbl TEXT NOT NULL, id INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY(tbl, id))'));
    sdb = d;
    final rows = await d.query('docs', orderBy: 'id');
    for (final r in rows) {
      final k = r['tbl'] as String;
      final j = r['json'] as String;
      if (t.containsKey(k)) {
        t[k]!.add(Map<String, dynamic>.from(jsonDecode(j) as Map));
        snap[k]![r['id'] as int] = j;
      }
    }
    if (p!.getBool('migrated') != true) {
      if (rows.isEmpty) {
        for (final k in keys) {
          final s = p!.getString(k);
          if (s != null) t[k] = decode(s);
        }
        await flush();
      }
      await p!.setBool('migrated', true);
    }
  }

  Future<void> flush() async {
    final d = sdb;
    if (d == null) return;
    final b = d.batch();
    final ns = <String, Map<int, String>>{};
    var any = false;
    for (final k in keys) {
      final old = snap[k]!;
      final cur = <int, String>{};
      for (final m in t[k]!) {
        final id = (m['id'] as num).toInt();
        final j = jsonEncode(m);
        cur[id] = j;
        if (old[id] != j) {
          b.insert('docs', {'tbl': k, 'id': id, 'json': j},
              conflictAlgorithm: ConflictAlgorithm.replace);
          any = true;
        }
      }
      for (final id in old.keys) {
        if (!cur.containsKey(id)) {
          b.delete('docs', where: 'tbl = ? AND id = ?', whereArgs: [k, id]);
          any = true;
        }
      }
      ns[k] = cur;
    }
    if (any) await b.commit(noResult: true);
    snap.addAll(ns);
  }

  void save() {
    q = q.then((_) => flush()).catchError((_) {});
    notifyListeners();
  }

  void markBackup() {
    lastBackup = DateTime.now().toIso8601String();
    p?.setString('lastBackup', lastBackup!);
    notifyListeners();
  }

  void logout() {
    me = null;
    notifyListeners();
  }

  String export() => jsonEncode(t);

  bool restore(String s) {
    try {
      final d = jsonDecode(s) as Map;
      final nt = <String, List<M>>{};
      for (final k in keys) {
        if (d[k] is List) {
          nt[k] = (d[k] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
      if (nt.isEmpty) return false;
      t.addAll(nt);
      me = null;
      save();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final db = Db.i;
bool get isAdmin => db.me?['role'] == 'admin';

String hashPw(String salt, String p) =>
    sha256.convert(utf8.encode('$salt|$p')).toString();
void setPw(M u, String p) {
  final salt = nid().toString();
  u['salt'] = salt;
  u['hash'] = hashPw(salt, p);
  u.remove('pass');
}

bool checkPw(M u, String p) =>
    u['hash'] != null ? u['hash'] == hashPw('${u['salt']}', p) : u['pass'] == p;

Future<List<String>?> form(BuildContext c, String title, List<String> labels,
    List<String>? init, Set<int> nums,
    {int? scanIdx}) {
  final cs = List.generate(labels.length,
      (i) => TextEditingController(text: init != null ? init[i] : ''));
  return showDialog<List<String>>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            TextField(
              controller: cs[i],
              decoration: InputDecoration(
                labelText: labels[i],
                suffixIcon: i == scanIdx
                    ? IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () async {
                          final v = await scan(c);
                          if (v != null) cs[i].text = v;
                        })
                    : null,
              ),
              keyboardType:
                  nums.contains(i) ? TextInputType.number : TextInputType.text,
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
        ElevatedButton(
            onPressed: () =>
                Navigator.pop(d, cs.map((e) => e.text.trim()).toList()),
            child: const Text('حفظ')),
      ],
    ),
  );
}

Future<bool> ask(BuildContext c, String t) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(t),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('نعم')),
        ],
      ),
    ) ??
    false;

Future<bool> sure(BuildContext c) => ask(c, 'تأكيد الحذف؟');

void msg(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

Widget empty() => const Center(child: Text('لا توجد بيانات'));

final la = LocalAuthentication();
Future<bool> deviceAuth(BuildContext c, bool bioOnly) async {
  try {
    if (!await la.isDeviceSupported()) {
      if (c.mounted) msg(c, 'فعّل قفل الشاشة أو البصمة في إعدادات هاتفك أولاً');
      return false;
    }
    return await la.authenticate(
        localizedReason: 'تأكيد الهوية',
        options: AuthenticationOptions(biometricOnly: bioOnly, stickyAuth: true));
  } catch (_) {
    return false;
  }
}

final ValueNotifier<int> goto = ValueNotifier<int>(-1);

Future<String?> scan(BuildContext c) => Navigator.push<String>(
    c, MaterialPageRoute(builder: (_) => const ScanPage()));

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanState();
}

class _ScanState extends State<ScanPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('وجّه الكاميرا نحو الباركود')),
        body: MobileScanner(onDetect: (cap) {
          if (done) return;
          final v = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
          if (v == null || v.isEmpty) return;
          done = true;
          Navigator.pop(context, v);
        }),
      );
}

Future<void> printLabels(BuildContext c, M p) async {
  final r = await form(c, 'طباعة ملصق باركود', ['عدد الملصقات'], ['1'], {0});
  if (r == null) return;
  var cnt = pd(r[0]).toInt();
  if (cnt < 1) cnt = 1;
  if (cnt > 200) cnt = 200;
  final doc = pw.Document();
  final fmt = PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm,
      marginAll: 2 * PdfPageFormat.mm);
  for (var i = 0; i < cnt; i++) {
    doc.addPage(pw.Page(
      pageFormat: fmt,
      build: (_) => pw.Column(children: [
        pw.Expanded(
            child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: '${p['imei']}',
                drawText: true)),
        pw.Text(f(n(p['price'])),
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ]),
    ));
  }
  await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'labels');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await db.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Al Itqan Store',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1A237E), useMaterial3: true),
        builder: (c, w) =>
            Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const Gate(),
      );
}

class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          if (db.users.isEmpty) return const AuthPage(true);
          if (db.me == null) return const AuthPage(false);
          return Home(key: ValueKey(db.me!['id']));
        },
      );
}

class AuthPage extends StatefulWidget {
  final bool setup;
  const AuthPage(this.setup, {super.key});
  @override
  State<AuthPage> createState() => _AuthState();
}

class _AuthState extends State<AuthPage> {
  final nm = TextEditingController();
  final us = TextEditingController();
  final ps = TextEditingController();
  int fails = 0;
  DateTime? lockUntil;

  void go() {
    final u = us.text.trim();
    if (widget.setup) {
      if (nm.text.trim().isEmpty || u.isEmpty || ps.text.length < 4) {
        msg(context, 'أكمل البيانات (كلمة المرور 4 أحرف على الأقل)');
        return;
      }
      final m = <String, dynamic>{
        'id': nid(),
        'name': nm.text.trim(),
        'user': u,
        'role': 'admin'
      };
      setPw(m, ps.text);
      db.users.add(m);
      db.me = m;
      db.save();
    } else {
      final l = db.users.where((x) => x['user'] == u && checkPw(x, ps.text)).toList();
      if (lockUntil != null && DateTime.now().isBefore(lockUntil!)) {
        msg(context, 'محاولات كثيرة خاطئة، انتظر دقيقة');
        return;
      }
      if (l.isEmpty) {
        fails++;
        if (fails >= 5) {
          fails = 0;
          lockUntil = DateTime.now().add(const Duration(minutes: 1));
        }
        msg(context, 'بيانات الدخول غير صحيحة');
        return;
      }
      if (l.first['hash'] == null) setPw(l.first, ps.text);
      fails = 0;
      db.me = l.first;
      db.save();
    }
  }

  Future<M?> pickUser(List<M> l) async {
    if (l.length == 1) return l.first;
    return showDialog<M>(
        context: context,
        builder: (d) => SimpleDialog(title: const Text('اختر الحساب'), children: [
              for (final x in l)
                SimpleDialogOption(onPressed: () => Navigator.pop(d, x), child: Text('${x['name']}'))
            ]));
  }

  Future<void> bioLogin() async {
    final l = db.users.where((u) => u['bio'] == true).toList();
    if (l.isEmpty || !await deviceAuth(context, true) || !mounted) return;
    final u = await pickUser(l);
    if (u == null) return;
    db.me = u;
    db.log('دخول بالبصمة/الوجه');
    db.save();
  }

  Future<void> forgot() async {
    if (!await deviceAuth(context, false) || !mounted) return;
    final u = await pickUser(db.users.where((x) => x['role'] == 'admin').toList());
    if (u == null || !mounted) return;
    final r = await form(context, 'كلمة مرور جديدة لـ ${u['name']}', ['كلمة المرور الجديدة'], null, {});
    if (r == null || !mounted) return;
    if (r[0].length < 4) {
      msg(context, 'كلمة المرور 4 أحرف على الأقل');
      return;
    }
    setPw(u, r[0]);
    db.log('إعادة تعيين كلمة مرور ${u['name']}');
    db.save();
    msg(context, 'تم تغيير كلمة المرور، سجّل الدخول الآن');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.phone_android, size: 72, color: Color(0xFF1A237E)),
              const Text('Al Itqan Store', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              const SizedBox(height: 8),
              Text(widget.setup ? 'إنشاء حساب المدير (صاحب المحل)' : 'تسجيل الدخول',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (widget.setup)
                TextField(
                    controller: nm,
                    decoration: const InputDecoration(labelText: 'الاسم')),
              TextField(
                  controller: us,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم')),
              TextField(
                  controller: ps,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور')),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: go, child: Text(widget.setup ? 'إنشاء ودخول' : 'دخول')),
              if (!widget.setup) ...[
                if (db.users.any((u) => u['bio'] == true))
                  OutlinedButton.icon(
                      onPressed: bioLogin,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('الدخول بالبصمة / الوجه')),
                TextButton(onPressed: forgot, child: const Text('نسيت كلمة المرور؟')),
              ],
            ]),
          ),
        ),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int i = 0;
  void jump() {
    if (goto.value >= 0 && mounted) {
      setState(() => i = goto.value);
    }
    goto.value = -1;
  }

  @override
  void initState() {
    super.initState();
    goto.addListener(jump);
    WidgetsBinding.instance.addObserver(this);
  }

  DateTime? away;

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.paused) {
      away = DateTime.now();
    } else if (st == AppLifecycleState.resumed && away != null) {
      if (DateTime.now().difference(away!).inSeconds > 120) db.logout();
      away = null;
    }
  }

  @override
  void dispose() {
    goto.removeListener(jump);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = isAdmin;
    final pages = <Widget>[
      if (a) const Dash(),
      const ProductsPage(),
      const PosPage(),
      const CustomersPage(),
      const RepairsPage(),
      const MorePage(),
    ];
    final dest = <NavigationDestination>[
      if (a) const NavigationDestination(icon: Icon(Icons.dashboard), label: 'الرئيسية'),
      const NavigationDestination(icon: Icon(Icons.phone_android), label: 'المخزون'),
      const NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'البيع'),
      const NavigationDestination(icon: Icon(Icons.people), label: 'العملاء'),
      const NavigationDestination(icon: Icon(Icons.build), label: 'الصيانة'),
      const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد'),
    ];
    return Scaffold(
      body: IndexedStack(index: i, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: dest,
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text('الحساب: ${db.me?['name'] ?? ''}')),
        body: ListView(children: [
          ListTile(
            leading: const Icon(Icons.lock_clock),
            title: const Text('إقفال الصندوق اليومي'),
            onTap: () => Navigator.push(
                c, MaterialPageRoute(builder: (_) => const CashPage())),
          ),
          if (isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.fact_check),
              title: const Text('الجرد الدوري'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const InventoryPage())),
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('حركات المخزون'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const MovesPage())),
            ),
            ListTile(
              leading: const Icon(Icons.archive),
              title: const Text('الأرشيف (منتجات وعملاء)'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const ArchivePage())),
            ),
            ListTile(
              leading: const Icon(Icons.history_edu),
              title: const Text('سجل العمليات'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const LogsPage())),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('التقارير'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const ReportsPage())),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('الموردون وفواتير الشراء'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const SuppliersPage())),
            ),
            ListTile(
              leading: const Icon(Icons.money_off),
              title: const Text('المصروفات'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const ExpensesPage())),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('إدارة الحسابات'),
              onTap: () => Navigator.push(
                  c, MaterialPageRoute(builder: (_) => const UsersPage())),
            ),
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('نسخ احتياطي'),
              subtitle: const Text('يصدّر ملفاً تحفظه أو ترسله لواتساب'),
              onTap: () async {
                try {
                  final name = 'itqan_backup_${ds(DateTime.now())}.json';
                  await Share.shareXFiles([
                    XFile.fromData(Uint8List.fromList(utf8.encode(db.export())),
                        mimeType: 'application/json', name: name)
                  ], fileNameOverrides: [name], subject: name);
                  db.markBackup();
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: db.export()));
                  db.markBackup();
                  if (c.mounted) msg(c, 'تعذّر إنشاء الملف، نُسخت البيانات للحافظة بدلاً منه');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('استعادة من ملف'),
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(withData: true);
                final b = r?.files.single.bytes;
                if (b == null || !c.mounted) return;
                if (!await ask(c, 'سيتم استبدال كل البيانات الحالية. متابعة؟')) return;
                var done = false;
                try {
                  done = db.restore(utf8.decode(b));
                } catch (_) {}
                if (!done && c.mounted) msg(c, 'الملف غير صالح');
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('استعادة نسخة احتياطية'),
              onTap: () async {
                final tc = TextEditingController();
                final ok = await showDialog<bool>(
                  context: c,
                  builder: (d) => AlertDialog(
                    title: const Text('الصق النسخة (ستستبدل البيانات الحالية)'),
                    content: TextField(controller: tc, maxLines: 5),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('إلغاء')),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('استعادة')),
                    ],
                  ),
                );
                if (ok != true) return;
                final done = db.restore(tc.text.trim());
                if (!done && c.mounted) msg(c, 'النسخة غير صالحة');
              },
            ),
          ],
          ListenableBuilder(
            listenable: db,
            builder: (c, _) => SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('الدخول بالبصمة / الوجه'),
              value: db.me?['bio'] == true,
              onChanged: (v) async {
                if (v && !await deviceAuth(c, true)) return;
                db.me?['bio'] = v;
                db.save();
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('تسجيل الخروج'),
            onTap: () => db.logout(),
          ),
        ]),
      );
}

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  Future<void> add(BuildContext c) async {
    final nm = TextEditingController();
    final us = TextEditingController();
    final ps = TextEditingController();
    var adm = false;
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('إضافة حساب'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nm,
                  decoration: const InputDecoration(labelText: 'الاسم')),
              TextField(
                  controller: us,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم')),
              TextField(
                  controller: ps,
                  decoration: const InputDecoration(labelText: 'كلمة المرور')),
              SwitchListTile(
                  title: const Text('صلاحية مدير'),
                  value: adm,
                  onChanged: (v) => set(() => adm = v)),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
            ElevatedButton(
                onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final u = us.text.trim();
    if (u.isEmpty || ps.text.length < 4 || nm.text.trim().isEmpty) {
      if (c.mounted) msg(c, 'أكمل البيانات (كلمة المرور 4 أحرف على الأقل)');
      return;
    }
    if (db.users.any((x) => x['user'] == u)) {
      if (c.mounted) msg(c, 'اسم المستخدم مستخدم مسبقاً');
      return;
    }
    db.log('إضافة حساب ${nm.text.trim()}');
    final nu = <String, dynamic>{
      'id': nid(),
      'name': nm.text.trim(),
      'user': u,
      'role': adm ? 'admin' : 'staff'
    };
    setPw(nu, ps.text);
    db.users.add(nu);
    db.save();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: const Text('إدارة الحسابات')),
          floatingActionButton: FloatingActionButton(
              onPressed: () => add(c), child: const Icon(Icons.person_add)),
          body: ListView(children: [
            for (final u in db.users)
              ListTile(
                leading: Icon(u['role'] == 'admin'
                    ? Icons.admin_panel_settings
                    : Icons.person),
                title: Text('${u['name']} (${u['user']})'),
                subtitle: Text(u['role'] == 'admin' ? 'مدير' : 'موظف مبيعات'),
                onTap: () async {
                  final r = await form(
                      c, 'كلمة مرور جديدة', ['كلمة المرور'], null, {});
                  if (r == null || r[0].length < 4) return;
                  setPw(u, r[0]);
                  db.save();
                },
                trailing: u['id'] == db.me?['id']
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (await sure(c)) {
                            db.log('حذف حساب ${u['name']}');
                            db.users.remove(u);
                            db.save();
                          }
                        },
                      ),
              ),
          ]),
        ),
      );
}

class Dash extends StatelessWidget {
  const Dash({super.key});

  String cmp(double a, double b) =>
      b == 0 ? '-' : '${a >= b ? '▲' : '▼'} ${f(((a - b) / b * 100).abs())}%';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final days = List<double>.filled(7, 0);
          double tp = 0, lw = 0, sales = 0, profit = 0;
          for (final s in db.sales) {
            final d = DateTime.parse(s['date'] as String);
            final k = today.difference(DateTime(d.year, d.month, d.day)).inDays;
            sales += n(s['total']);
            profit += n(s['profit']);
            if (k == 0) tp += n(s['profit']);
            if (k == 7) lw += n(s['total']);
            if (k >= 0 && k < 7) days[6 - k] += n(s['total']);
          }
          final mx = days.reduce((a, b) => a > b ? a : b);
          final exp = db.expenses.fold<double>(0, (a, e) => a + n(e['amount']));
          final rep = db.repairs
              .where((r) => n(r['status']) == 2)
              .fold<double>(0, (a, r) => a + n(r['cost']));
          final debts = db.customers.fold<double>(0, (a, e) => a + n(e['debt']));
          final act = db.products.where((p) => p['archived'] != true).toList();
          final stock = act.fold<double>(0, (a, e) => a + n(e['cost']) * n(e['qty']));
          final sellVal = act.fold<double>(0, (a, e) => a + n(e['price']) * n(e['qty']));
          final units = act.fold<double>(0, (a, e) => a + n(e['qty']));
          final low = act
              .where((p) => n(p['qty']) <= (p['min'] == null ? 2 : n(p['min'])))
              .toList();
          final overdue = db.customers
              .where((x) =>
                  n(x['debt']) > 0 &&
                  x['due'] != null &&
                  DateTime.parse(x['due'] as String).isBefore(now))
              .toList();
          final ready = db.repairs.where((r) => n(r['status']) == 1).toList();
          final stale = db.lastBackup == null
              ? db.sales.isNotEmpty
              : now.difference(DateTime.parse(db.lastBackup!)).inDays >= 7;
          final cards = <(String, double, IconData, Color)>[
            ('ربح اليوم', tp, Icons.trending_up, Colors.green),
            ('إجمالي المبيعات', sales, Icons.shopping_cart, Colors.indigo),
            ('إجمالي الربح', profit, Icons.savings, Colors.teal),
            ('دخل الصيانة', rep, Icons.build, Colors.orange),
            ('المصروفات', exp, Icons.money_off, Colors.red),
            ('صافي الربح', profit + rep - exp, Icons.account_balance, Colors.purple),
            ('ديون العملاء', debts, Icons.warning, Colors.deepOrange),
          ];
          return Scaffold(
            appBar: AppBar(title: const Text('Al Itqan Store')),
            body: ListView(padding: const EdgeInsets.all(8), children: [
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white),
                  onPressed: () => goto.value = 2,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('بيع جديد', style: TextStyle(fontSize: 18)),
                ),
              ),
              Wrap(spacing: 8, children: [
                for (final q in <(String, IconData, Widget)>[
                  ('المصروفات', Icons.money_off, const ExpensesPage()),
                  ('سجل المبيعات', Icons.receipt_long, const SalesPage()),
                  ('التقارير', Icons.bar_chart, const ReportsPage()),
                  ('الموردون', Icons.local_shipping, const SuppliersPage()),
                ])
                  ActionChip(
                    avatar: Icon(q.$2, size: 18),
                    label: Text(q.$1),
                    onPressed: () => Navigator.push(
                        c, MaterialPageRoute(builder: (_) => q.$3)),
                  ),
              ]),
              Card(
                child: Column(children: [
                  row('مبيعات اليوم', f(days[6])),
                  row('مقارنة بأمس', cmp(days[6], days[5]),
                      c: days[6] >= days[5] ? Colors.green : Colors.red),
                  row('مقارنة بنفس اليوم الأسبوع الماضي', cmp(days[6], lw),
                      c: days[6] >= lw ? Colors.green : Colors.red),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SizedBox(
                      height: 110,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                              Text(f(days[i]), style: const TextStyle(fontSize: 9)),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                height: mx == 0 ? 2 : 2 + days[i] / mx * 70,
                                decoration: BoxDecoration(
                                    color: i == 6 ? Colors.indigo : Colors.indigo.shade200,
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                              Text(ds(today.subtract(Duration(days: 6 - i))).substring(8),
                                  style: const TextStyle(fontSize: 10)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ),
              Card(
                color: Colors.indigo.shade50,
                child: ListTile(
                  leading: const Icon(Icons.inventory, color: Colors.indigo),
                  title: const Text('رأس المال (المخزون بسعر الشراء)'),
                  subtitle: const Text('اضغط لعرض إجمالي سعر البيع'),
                  trailing: Text(f(stock),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  onTap: () => showDialog<void>(
                    context: c,
                    builder: (d) => AlertDialog(
                      title: const Text('رأس المال والمخزون'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          row('إجمالي رأس المال (سعر الشراء)', f(stock)),
                          row('إجمالي سعر بيع المنتجات', f(sellVal), c: Colors.indigo),
                          row('الربح المتوقع إذا بيع كله', f(sellVal - stock), c: Colors.green),
                          row('عدد القطع في المخزون', f(units)),
                        ]),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق'))
                      ],
                    ),
                  ),
                ),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final k in cards)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(k.$3, color: k.$4),
                          Text(k.$1),
                          Text(f(k.$2),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                ],
              ),
              Card(
                color: Colors.amber.shade50,
                child: Column(children: [
                  const ListTile(
                      leading: Icon(Icons.notifications_active, color: Colors.orange),
                      title: Text('يحتاج انتباه')),
                  if (low.isEmpty && overdue.isEmpty && ready.isEmpty && !stale)
                    const ListTile(dense: true, title: Text('لا شيء يحتاج انتباه حالياً ✅')),
                  if (stale)
                    ListTile(
                        dense: true,
                        leading: const Icon(Icons.backup, color: Colors.orange),
                        title: Text(db.lastBackup == null
                            ? 'لم تأخذ نسخة احتياطية بعد'
                            : 'مرّ 7 أيام أو أكثر على آخر نسخة احتياطية'),
                        subtitle: const Text('المزيد ← نسخ احتياطي')),
                  for (final p in low)
                    ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2, color: Colors.red),
                        title: Text('مخزون منخفض: ${p['name']}'),
                        trailing: Text('${f(n(p['qty']))}')),
                  for (final x in overdue)
                    ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning, color: Colors.deepOrange),
                        title: Text('دين متأخر: ${x['name']}'),
                        trailing: Text(f(n(x['debt'])))),
                  for (final r in ready)
                    ListTile(
                        dense: true,
                        leading: const Icon(Icons.build_circle, color: Colors.green),
                        title: Text('صيانة جاهزة للتسليم: ${r['device']}'),
                        trailing: Text('${r['customer']}')),
                ]),
              ),
            ]),
          );
        },
      );
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsState();
}

class _ProductsState extends State<ProductsPage> {
  String q = '';

  Future<void> edit([M? p]) async {
    final r = await form(
      context,
      p == null ? 'إضافة منتج' : 'تعديل منتج',
      ['الاسم', 'التصنيف', 'الباركود / IMEI (فارغ = توليد تلقائي)', 'سعر الشراء', 'سعر البيع', 'الكمية', 'حد تنبيه المخزون'],
      p == null
          ? null
          : [
              '${p['name']}',
              '${p['cat']}',
              '${p['imei']}',
              f(n(p['cost'])),
              f(n(p['price'])),
              f(n(p['qty'])),
              f(p['min'] == null ? 2 : n(p['min']))
            ],
      {3, 4, 5, 6},
      scanIdx: 2,
    );
    if (r == null || r[0].isEmpty) return;
    final m = p ?? <String, dynamic>{'id': nid()};
    final oldQty = n(m['qty']).toInt();
    m['name'] = r[0];
    m['cat'] = r[1];
    m['imei'] = r[2].isEmpty ? newCode() : r[2];
    m['cost'] = pd(r[3]);
    m['price'] = pd(r[4]);
    m['qty'] = pd(r[5]).toInt();
    final dq = (m['qty'] as int) - oldQty;
    if (dq != 0) db.move(m, p == null ? 'رصيد افتتاحي' : 'تعديل يدوي', dq);
    m['min'] = r[6].isEmpty ? 2 : pd(r[6]).toInt();
    if (p == null) db.products.add(m);
    db.save();
    if (p == null && mounted) {
      if (await ask(context, 'طباعة ملصق باركود لهذا المنتج الآن؟') && mounted) {
        await printLabels(context, m);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          final list = db.products
              .where((p) => p['archived'] != true && '${p['name']} ${p['imei']} ${p['cat']}'
                  .toLowerCase()
                  .contains(q.toLowerCase()))
              .toList();
          final a = isAdmin;
          return Scaffold(
            appBar: AppBar(title: const Text('المخزون')),
            floatingActionButton: a
                ? FloatingActionButton(
                    onPressed: () => edit(), child: const Icon(Icons.add))
                : null,
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'بحث بالاسم أو الباركود',
                      border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => q = v),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? empty()
                    : ListView(children: [
                        for (final p in list)
                          ListTile(
                            isThreeLine: true,
                            leading: CircleAvatar(
                              backgroundColor:
                                  n(p['qty']) <= (p['min'] == null ? 2 : n(p['min'])) ? Colors.red : Colors.green,
                              foregroundColor: Colors.white,
                              child: Text(f(n(p['qty']))),
                            ),
                            title: Text('${p['name']}'),
                            subtitle: Text(
                                '${p['cat']} • ${p['imei']}\n${a ? 'شراء ${f(n(p['cost']))} | ' : ''}بيع ${f(n(p['price']))}'),
                            trailing: a
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                      icon: const Icon(Icons.qr_code_2),
                                      onPressed: () => printLabels(c, p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () async {
                                        if (await ask(c, 'أرشفة المنتج؟ يختفي من القوائم ويمكن استرجاعه من المزيد ← الأرشيف')) {
                                          db.log('أرشفة منتج ${p['name']}');
                                          p['archived'] = true;
                                          db.save();
                                        }
                                      },
                                    ),
                                  ])
                                : null,
                            onTap: a ? () => edit(p) : null,
                          ),
                      ]),
              ),
            ]),
          );
        },
      );
}

class PosPage extends StatefulWidget {
  const PosPage({super.key});
  @override
  State<PosPage> createState() => _PosState();
}

class _PosState extends State<PosPage> {
  String q = '';
  final Map<int, int> cart = {};
  final qc = TextEditingController();
  final fn = FocusNode();

  M prod(int id) => db.products.firstWhere((p) => p['id'] == id);

  double get sub =>
      cart.entries.fold<double>(0, (a, e) => a + n(prod(e.key)['price']) * e.value);

  void addByCode(String v) {
    final code = v.trim();
    if (code.isEmpty) return;
    final l = db.products.where((p) => p['archived'] != true && '${p['imei']}' == code).toList();
    if (l.isEmpty) {
      msg(context, 'لا يوجد منتج بهذا الباركود');
      return;
    }
    final id = l.first['id'] as int;
    if ((cart[id] ?? 0) >= n(l.first['qty'])) {
      msg(context, 'الكمية المتوفرة لا تكفي');
      return;
    }
    setState(() => cart[id] = (cart[id] ?? 0) + 1);
  }

  Future<void> checkout() async {
    if (cart.isEmpty) return;
    final total0 = sub;
    int? cid;
    String method = 'نقدي';
    final due = TextEditingController(text: '30');
    final disc = TextEditingController();
    final paid = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('الإجمالي: ${f(total0)}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<int?>(
                isExpanded: true,
                value: cid,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('عميل نقدي')),
                  for (final cu in db.customers.where((x) => x['archived'] != true))
                    DropdownMenuItem<int?>(
                        value: cu['id'] as int, child: Text('${cu['name']}')),
                ],
                onChanged: (v) => set(() => cid = v),
              ),
              TextField(
                  controller: disc,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الخصم')),
              TextField(
                  controller: paid,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'المبلغ المدفوع (فارغ = كامل)')),
              DropdownButton<String>(
                isExpanded: true,
                value: method,
                items: const [
                  DropdownMenuItem(value: 'نقدي', child: Text('الدفع: نقدي')),
                  DropdownMenuItem(value: 'تحويل', child: Text('الدفع: تحويل / بطاقة')),
                ],
                onChanged: (v) => set(() => method = v ?? 'نقدي'),
              ),
              TextField(
                  controller: due,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'مهلة سداد الدين بالأيام')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد البيع')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    var dsc = pd(disc.text);
    if (dsc > total0) dsc = total0;
    final total = total0 - dsc;
    var pay = paid.text.trim().isEmpty ? total : pd(paid.text);
    if (pay > total) pay = total;
    final debt = total - pay;
    if (debt > 0 && cid == null) {
      msg(context, 'اختر عميلاً لتسجيل الدين');
      return;
    }
    double cost = 0;
    final items = <M>[];
    for (final e in cart.entries) {
      final p = prod(e.key);
      cost += n(p['cost']) * e.value;
      items.add({
        'pid': p['id'],
        'name': p['name'],
        'qty': e.value,
        'price': n(p['price']),
        'cost': n(p['cost'])
      });
      p['qty'] = n(p['qty']).toInt() - e.value;
      db.move(p, 'بيع', -e.value);
    }
    String cname = 'عميل نقدي';
    if (cid != null) {
      final cu = db.customers.firstWhere((x) => x['id'] == cid);
      cu['debt'] = n(cu['debt']) + debt;
      if (debt > 0) {
        cu['due'] = DateTime.now().add(Duration(days: pd(due.text).toInt())).toIso8601String();
      }
      cname = '${cu['name']}';
    }
    final no = db.sales.fold<int>(0, (a, s) => n(s['no']).toInt() > a ? n(s['no']).toInt() : a) + 1;
    db.log('بيع فاتورة رقم $no بقيمة ${f(total)}');
    db.sales.add({
      'id': nid(),
      'no': no,
      'method': method,
      'date': DateTime.now().toIso8601String(),
      'customer': cname,
      'cid': cid,
      'by': db.me?['name'],
      'items': items,
      'total': total,
      'discount': dsc,
      'paid': pay,
      'debt': debt,
      'profit': total0 - cost - dsc,
    });
    cart.clear();
    db.save();
    setState(() {});
    msg(context, 'تمت عملية البيع بنجاح');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          cart.removeWhere((id, _) => !db.products.any((p) => p['id'] == id));
          final list = db.products
              .where((p) =>
                  p['archived'] != true && n(p['qty']) > 0 &&
                  '${p['name']} ${p['imei']}'
                      .toLowerCase()
                      .contains(q.toLowerCase()))
              .toList();
          return Scaffold(
            appBar: AppBar(title: const Text('نقطة البيع'), actions: [
              IconButton(
                icon: const Icon(Icons.receipt_long),
                onPressed: () => Navigator.push(
                    c, MaterialPageRoute(builder: (_) => const SalesPage())),
              ),
            ]),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: qc,
                  focusNode: fn,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'ابحث أو امسح الباركود (قارئ/كاميرا)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () async {
                        final v = await scan(c);
                        if (v != null) addByCode(v);
                      },
                    ),
                  ),
                  onChanged: (v) => setState(() => q = v),
                  onSubmitted: (v) {
                    addByCode(v);
                    qc.clear();
                    setState(() => q = '');
                    fn.requestFocus();
                  },
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? empty()
                    : ListView(children: [
                        for (final p in list)
                          ListTile(
                            title: Text('${p['name']}'),
                            subtitle: Text(
                                'السعر ${f(n(p['price']))} • المتوفر ${f(n(p['qty']))}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () {
                                  final id = p['id'] as int;
                                  final x = (cart[id] ?? 0) - 1;
                                  setState(() {
                                    if (x <= 0) {
                                      cart.remove(id);
                                    } else {
                                      cart[id] = x;
                                    }
                                  });
                                },
                              ),
                              Text('${cart[p['id'] as int] ?? 0}'),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () {
                                  final id = p['id'] as int;
                                  if ((cart[id] ?? 0) < n(p['qty'])) {
                                    setState(() => cart[id] = (cart[id] ?? 0) + 1);
                                  }
                                },
                              ),
                            ]),
                          ),
                      ]),
              ),
              Container(
                color: Colors.indigo.shade50,
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: Text('الإجمالي: ${f(sub)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold))),
                  ElevatedButton(
                      onPressed: cart.isEmpty ? null : checkout,
                      child: const Text('إتمام البيع')),
                ]),
              ),
            ]),
          );
        },
      );
}

class SalesPage extends StatelessWidget {
  const SalesPage({super.key});

  void custDebt(M s, double amt) {
    if (s['cid'] == null || amt <= 0) return;
    final l = db.customers.where((x) => x['id'] == s['cid']).toList();
    if (l.isNotEmpty) {
      final left = n(l.first['debt']) - amt;
      l.first['debt'] = left < 0 ? 0.0 : left;
    }
  }

  Future<void> partialReturn(BuildContext c, M s) async {
    final items = (s['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final cs = [for (final _ in items) TextEditingController()];
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('مرتجع جزئي: الكمية المرجعة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < items.length; i++)
              TextField(
                controller: cs[i],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: '${items[i]['name']} (المباع ${items[i]['qty']})'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد المرتجع')),
        ],
      ),
    );
    if (ok != true) return;
    final total0 = items.fold<double>(0, (a, i) => a + n(i['price']) * n(i['qty']));
    double v = 0, margin = 0;
    final back = <M>[];
    for (var i = 0; i < items.length; i++) {
      final sold = n(items[i]['qty']).toInt();
      var q = pd(cs[i].text).toInt();
      if (q > sold) q = sold;
      if (q <= 0) continue;
      v += n(items[i]['price']) * q;
      margin += (n(items[i]['price']) - n(items[i]['cost'])) * q;
      back.add({...items[i], 'qty': q});
      items[i]['qty'] = sold - q;
      final l = db.products
          .where((p) => p['id'] == items[i]['pid'] || (items[i]['pid'] == null && p['name'] == items[i]['name']))
          .toList();
      if (l.isNotEmpty) {
        l.first['qty'] = n(l.first['qty']).toInt() + q;
        db.move(l.first, 'مرتجع جزئي', q);
      }
    }
    if (back.isEmpty) return;
    final ratio = total0 == 0 ? 0.0 : v / total0;
    final dsc = n(s['discount']);
    final refund = (total0 - dsc) * ratio;
    final lost = margin - dsc * ratio;
    items.removeWhere((i) => n(i['qty']) <= 0);
    db.returns.add({
      'id': nid(),
      'date': DateTime.now().toIso8601String(),
      'no': s['no'],
      'customer': s['customer'],
      'total': refund,
      'profit': lost,
      'by': db.me?['name'],
      'items': back,
      'partial': true,
    });
    db.log('مرتجع جزئي من فاتورة ${s['no'] ?? ''} بقيمة ${f(refund)}');
    if (items.isEmpty) {
      custDebt(s, n(s['debt']));
      db.sales.remove(s);
    } else {
      final debt = n(s['debt']);
      final fromDebt = refund < debt ? refund : debt;
      s['items'] = items;
      s['total'] = n(s['total']) - refund;
      s['discount'] = dsc - dsc * ratio;
      s['profit'] = n(s['profit']) - lost;
      s['debt'] = debt - fromDebt;
      s['paid'] = n(s['paid']) - (refund - fromDebt);
      custDebt(s, fromDebt);
    }
    db.save();
  }

  Future<void> returnSale(BuildContext c, M s) async {
    if (!await ask(c, 'إرجاع الفاتورة بالكامل؟ ستعود الكميات للمخزون')) return;
    for (final i in s['items'] as List) {
      final l = db.products
          .where((p) =>
              p['id'] == i['pid'] || (i['pid'] == null && p['name'] == i['name']))
          .toList();
      if (l.isNotEmpty) {
        l.first['qty'] = n(l.first['qty']).toInt() + n(i['qty']).toInt();
        db.move(l.first, 'مرتجع', n(i['qty']).toInt());
      }
    }
    if (s['cid'] != null) {
      final l = db.customers.where((x) => x['id'] == s['cid']).toList();
      if (l.isNotEmpty) {
        final left = n(l.first['debt']) - n(s['debt']);
        l.first['debt'] = left < 0 ? 0.0 : left;
      }
    }
    db.log('إرجاع فاتورة ${s['no'] ?? ''}');
    db.returns.add({
      'id': nid(),
      'date': DateTime.now().toIso8601String(),
      'no': s['no'],
      'customer': s['customer'],
      'total': n(s['total']),
      'profit': n(s['profit']),
      'by': db.me?['name'],
      'items': s['items'],
    });
    db.sales.remove(s);
    db.save();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          final list = db.sales.reversed.toList();
          return Scaffold(
            appBar: AppBar(title: const Text('سجل المبيعات')),
            body: list.isEmpty
                ? empty()
                : ListView(children: [
                    for (final s in list)
                      ListTile(
                        title: Text('#${s['no'] ?? ''} ${s['customer']} - ${f(n(s['total']))}'),
                        subtitle: Text(
                            '${(s['date'] as String).substring(0, 16).replaceFirst('T', ' ')} • ${s['by'] ?? ''}'),
                        trailing: n(s['debt']) > 0
                            ? Text('دين ${f(n(s['debt']))}',
                                style: const TextStyle(color: Colors.red))
                            : const Icon(Icons.check_circle, color: Colors.green),
                        onTap: () => showDialog<void>(
                          context: c,
                          builder: (d) => AlertDialog(
                            title: const Text('تفاصيل الفاتورة'),
                            content: Text((s['items'] as List)
                                    .map((i) =>
                                        '${i['name']} × ${i['qty']} = ${f(n(i['price']) * n(i['qty']))}')
                                    .join('\n') +
                                '\n\nالخصم: ${f(n(s['discount']))}\nالإجمالي: ${f(n(s['total']))}\nالمدفوع: ${f(n(s['paid']))}\nالمتبقي: ${f(n(s['debt']))}'),
                            actions: [
                              if (isAdmin)
                                TextButton(
                                    onPressed: () {
                                      Navigator.pop(d);
                                      partialReturn(c, s);
                                    },
                                    child: const Text('مرتجع جزئي')),
                              if (isAdmin)
                                TextButton(
                                    onPressed: () {
                                      Navigator.pop(d);
                                      returnSale(c, s);
                                    },
                                    child: const Text('إرجاع الفاتورة',
                                        style: TextStyle(color: Colors.red))),
                              TextButton(
                                  onPressed: () => Navigator.pop(d),
                                  child: const Text('إغلاق')),
                            ],
                          ),
                        ),
                      ),
                  ]),
          );
        },
      );
}

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  Future<void> edit(BuildContext c, [M? m]) async {
    final r = await form(
        c,
        m == null ? 'إضافة عميل' : 'تعديل عميل',
        ['الاسم', 'الهاتف'],
        m == null ? null : ['${m['name']}', '${m['phone']}'],
        {1});
    if (r == null || r[0].isEmpty) return;
    final x = m ?? <String, dynamic>{'id': nid(), 'debt': 0.0};
    x['name'] = r[0];
    x['phone'] = r[1];
    if (m == null) db.customers.add(x);
    db.save();
  }

  Future<void> pay(BuildContext c, M m) async {
    final r = await form(
        c, 'تسديد دين ${m['name']}', ['المبلغ'], [f(n(m['debt']))], {0});
    if (r == null) return;
    final a = pd(r[0]);
    if (a <= 0) return;
    db.payments.add({
      'id': nid(),
      'date': DateTime.now().toIso8601String(),
      'kind': 'customer',
      'name': m['name'],
      'amount': a > n(m['debt']) ? n(m['debt']) : a,
      'by': db.me?['name'],
    });
    db.log('تسديد دين ${m['name']}: ${f(a > n(m['debt']) ? n(m['debt']) : a)}');
    final left = n(m['debt']) - a;
    m['debt'] = left < 0 ? 0.0 : left;
    db.save();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: const Text('العملاء')),
          floatingActionButton: FloatingActionButton(
              onPressed: () => edit(c), child: const Icon(Icons.person_add)),
          body: db.customers.isEmpty
              ? empty()
              : ListView(children: [
                  for (final m in db.customers.where((x) => x['archived'] != true))
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text('${m['name']}'),
                      subtitle: Text('${m['phone']}\nالدين: ${f(n(m['debt']))}'),
                      isThreeLine: true,
                      onTap: () => edit(c, m),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (n(m['debt']) > 0)
                          IconButton(
                              icon: const Icon(Icons.payments, color: Colors.green),
                              onPressed: () => pay(c, m)),
                        if (isAdmin)
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              if (n(m['debt']) > 0) {
                                msg(c, 'لا يمكن أرشفة عميل عليه دين');
                              } else if (await ask(c, 'أرشفة العميل؟ يمكن استرجاعه من المزيد ← الأرشيف')) {
                                db.log('أرشفة عميل ${m['name']}');
                                m['archived'] = true;
                                db.save();
                              }
                            },
                          ),
                      ]),
                    ),
                ]),
        ),
      );
}

class RepairsPage extends StatelessWidget {
  const RepairsPage({super.key});
  static const st = ['قيد الصيانة', 'جاهز', 'تم التسليم'];

  Future<void> edit(BuildContext c, [M? m]) async {
    final r = await form(
        c,
        m == null ? 'جهاز جديد للصيانة' : 'تعديل',
        ['الجهاز', 'اسم العميل', 'المشكلة', 'التكلفة', 'العربون المدفوع'],
        m == null
            ? null
            : ['${m['device']}', '${m['customer']}', '${m['problem']}', f(n(m['cost'])), f(n(m['deposit']))],
        {3, 4});
    if (r == null || r[0].isEmpty) return;
    final x = m ?? <String, dynamic>{'id': nid(), 'status': 0, 'no': db.repairs.fold<int>(0, (a, r) => n(r['no']).toInt() > a ? n(r['no']).toInt() : a) + 1};
    x['device'] = r[0];
    x['customer'] = r[1];
    x['problem'] = r[2];
    x['cost'] = pd(r[3]);
    x['deposit'] = pd(r[4]);
    if (m == null) db.repairs.add(x);
    db.save();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: const Text('الصيانة')),
          floatingActionButton: FloatingActionButton(
              onPressed: () => edit(c), child: const Icon(Icons.add)),
          body: db.repairs.isEmpty
              ? empty()
              : ListView(children: [
                  for (final r in db.repairs.reversed.toList())
                    ListTile(
                      isThreeLine: true,
                      leading: Icon(Icons.build,
                          color: n(r['status']) == 2
                              ? Colors.green
                              : n(r['status']) == 1
                                  ? Colors.orange
                                  : Colors.grey),
                      title: Text('#${r['no'] ?? ''} ${r['device']} - ${r['customer']}'),
                      subtitle: Text(
                          '${r['problem']}\n${f(n(r['cost']))} (عربون ${f(n(r['deposit']))} • متبقي ${f(n(r['cost']) - n(r['deposit']))}) | ${st[n(r['status']).toInt()]}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'next') {
                            r['status'] = n(r['status']).toInt() + 1;
                            db.save();
                          } else if (v == 'edit') {
                            await edit(c, r);
                          } else if (v == 'del') {
                            if (await sure(c)) {
                              db.repairs.remove(r);
                              db.save();
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          if (n(r['status']) < 2)
                            PopupMenuItem(
                                value: 'next',
                                child: Text('نقل إلى: ${st[n(r['status']).toInt() + 1]}')),
                          const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          if (isAdmin)
                            const PopupMenuItem(value: 'del', child: Text('حذف')),
                        ],
                      ),
                    ),
                ]),
        ),
      );
}

class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});

  Future<void> add(BuildContext c) async {
    final r = await form(c, 'إضافة مصروف', ['البيان', 'المبلغ'], null, {1});
    if (r == null || r[0].isEmpty) return;
    db.expenses.add({
      'id': nid(),
      'title': r[0],
      'amount': pd(r[1]),
      'date': DateTime.now().toIso8601String()
    });
    db.save();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: const Text('المصروفات')),
          floatingActionButton: FloatingActionButton(
              onPressed: () => add(c), child: const Icon(Icons.add)),
          body: db.expenses.isEmpty
              ? empty()
              : ListView(children: [
                  for (final e in db.expenses.reversed.toList())
                    ListTile(
                      title: Text('${e['title']}'),
                      subtitle: Text((e['date'] as String).substring(0, 10)),
                      leading: Text(f(n(e['amount'])),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.red)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          if (await sure(c)) {
                            db.expenses.remove(e);
                            db.save();
                          }
                        },
                      ),
                    ),
                ]),
        ),
      );
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String ds(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Widget row(String a, String b, {Color? c}) => ListTile(
    dense: true,
    title: Text(a),
    trailing:
        Text(b, style: TextStyle(fontWeight: FontWeight.bold, color: c)));

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  Future<void> edit(BuildContext c, [M? m]) async {
    final r = await form(c, m == null ? 'إضافة مورد' : 'تعديل مورد',
        ['الاسم', 'الهاتف'], m == null ? null : ['${m['name']}', '${m['phone']}'], {1});
    if (r == null || r[0].isEmpty) return;
    final x = m ?? <String, dynamic>{'id': nid(), 'debt': 0.0};
    x['name'] = r[0];
    x['phone'] = r[1];
    if (m == null) db.suppliers.add(x);
    db.save();
  }

  Future<void> pay(BuildContext c, M m) async {
    final r = await form(
        c, 'تسديد للمورد ${m['name']}', ['المبلغ'], [f(n(m['debt']))], {0});
    if (r == null) return;
    final a = pd(r[0]);
    if (a <= 0) return;
    db.payments.add({
      'id': nid(),
      'date': DateTime.now().toIso8601String(),
      'kind': 'supplier',
      'name': m['name'],
      'amount': a > n(m['debt']) ? n(m['debt']) : a,
      'by': db.me?['name'],
    });
    db.log('تسديد للمورد ${m['name']}: ${f(a > n(m['debt']) ? n(m['debt']) : a)}');
    final left = n(m['debt']) - a;
    m['debt'] = left < 0 ? 0.0 : left;
    db.save();
  }

  Future<void> purchase(BuildContext c) async {
    if (db.suppliers.isEmpty || db.products.isEmpty) {
      msg(c, 'أضف مورداً ومنتجاً أولاً');
      return;
    }
    int? sid = db.suppliers.first['id'] as int;
    int? pid = db.products.firstWhere((x) => x['archived'] != true, orElse: () => db.products.first)['id'] as int;
    final qc = TextEditingController();
    final cc = TextEditingController();
    final pc = TextEditingController();
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('فاتورة شراء'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<int?>(
                isExpanded: true,
                value: sid,
                items: [
                  for (final s in db.suppliers)
                    DropdownMenuItem<int?>(
                        value: s['id'] as int, child: Text('${s['name']}'))
                ],
                onChanged: (v) => set(() => sid = v),
              ),
              DropdownButton<int?>(
                isExpanded: true,
                value: pid,
                items: [
                  for (final p in db.products.where((x) => x['archived'] != true))
                    DropdownMenuItem<int?>(
                        value: p['id'] as int, child: Text('${p['name']}'))
                ],
                onChanged: (v) => set(() => pid = v),
              ),
              TextField(
                  controller: qc,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الكمية')),
              TextField(
                  controller: cc,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'سعر شراء الوحدة (فارغ = الحالي)')),
              TextField(
                  controller: pc,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'المدفوع للمورد (فارغ = كامل)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = pd(qc.text).toInt();
    if (q <= 0) {
      if (c.mounted) msg(c, 'أدخل كمية صحيحة');
      return;
    }
    final sup = db.suppliers.firstWhere((x) => x['id'] == sid);
    final p = db.products.firstWhere((x) => x['id'] == pid);
    final cost = cc.text.trim().isEmpty ? n(p['cost']) : pd(cc.text);
    final total = cost * q;
    var paid = pc.text.trim().isEmpty ? total : pd(pc.text);
    if (paid > total) paid = total;
    p['qty'] = n(p['qty']).toInt() + q;
    db.move(p, 'شراء', q);
    p['cost'] = cost;
    sup['debt'] = n(sup['debt']) + (total - paid);
    db.purchases.add({
      'id': nid(),
      'date': DateTime.now().toIso8601String(),
      'supplier': sup['name'],
      'product': p['name'],
      'qty': q,
      'cost': cost,
      'total': total,
      'paid': paid,
      'by': db.me?['name'],
    });
    db.save();
    if (c.mounted) msg(c, 'تم تسجيل الشراء وإضافة الكمية للمخزون');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: const Text('الموردون'), actions: [
            IconButton(
                tooltip: 'فاتورة شراء جديدة',
                icon: const Icon(Icons.add_shopping_cart),
                onPressed: () => purchase(c)),
            IconButton(
                tooltip: 'سجل المشتريات',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.push(c,
                    MaterialPageRoute(builder: (_) => const PurchasesPage()))),
          ]),
          floatingActionButton: FloatingActionButton(
              onPressed: () => edit(c), child: const Icon(Icons.add)),
          body: db.suppliers.isEmpty
              ? empty()
              : ListView(children: [
                  for (final m in db.suppliers)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                      title: Text('${m['name']}'),
                      subtitle: Text('${m['phone']}\nمستحق له: ${f(n(m['debt']))}'),
                      isThreeLine: true,
                      onTap: () => edit(c, m),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (n(m['debt']) > 0)
                          IconButton(
                              icon: const Icon(Icons.payments, color: Colors.green),
                              onPressed: () => pay(c, m)),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            if (await sure(c)) {
                              db.suppliers.remove(m);
                              db.save();
                            }
                          },
                        ),
                      ]),
                    ),
                ]),
        ),
      );
}

class PurchasesPage extends StatelessWidget {
  const PurchasesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final list = db.purchases.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المشتريات')),
      body: list.isEmpty
          ? empty()
          : ListView(children: [
              for (final p in list)
                ListTile(
                  title: Text('${p['product']} × ${p['qty']}'),
                  subtitle: Text(
                      '${p['supplier']} • ${(p['date'] as String).substring(0, 10)}\nالمدفوع ${f(n(p['paid']))}'),
                  isThreeLine: true,
                  trailing: Text(f(n(p['total'])),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
            ]),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsState();
}

class _ReportsState extends State<ReportsPage> {
  late DateTime from;
  late DateTime to;
  int mode = 0;

  @override
  void initState() {
    super.initState();
    setRange(0);
  }

  void setRange(int m) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    mode = m;
    if (m == 0) {
      from = today;
    } else if (m == 1) {
      from = today.subtract(const Duration(days: 6));
    } else {
      from = DateTime(now.year, now.month, 1);
    }
    to = today;
  }

  Future<void> pick() async {
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)));
    if (r == null) return;
    setState(() {
      mode = 3;
      from = DateTime(r.start.year, r.start.month, r.start.day);
      to = DateTime(r.end.year, r.end.month, r.end.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final end = to.add(const Duration(days: 1));
    bool inR(String s) {
      final d = DateTime.parse(s);
      return !d.isBefore(from) && d.isBefore(end);
    }

    final ss = db.sales.where((s) => inR(s['date'] as String)).toList();
    double total = 0, profit = 0, disc = 0, debt = 0;
    final qty = <String, double>{};
    final emp = <String, double>{};
    for (final s in ss) {
      total += n(s['total']);
      profit += n(s['profit']);
      disc += n(s['discount']);
      debt += n(s['debt']);
      for (final i in s['items'] as List) {
        final k = '${i['name']}';
        qty[k] = (qty[k] ?? 0) + n(i['qty']);
      }
      final e = '${s['by'] ?? '-'}';
      emp[e] = (emp[e] ?? 0) + n(s['total']);
    }
    final exp = db.expenses
        .where((e) => inR(e['date'] as String))
        .fold<double>(0, (a, e) => a + n(e['amount']));
    final buy = db.purchases
        .where((e) => inR(e['date'] as String))
        .fold<double>(0, (a, e) => a + n(e['total']));
    final ret = db.returns
        .where((e) => inR(e['date'] as String))
        .fold<double>(0, (a, e) => a + n(e['total']));
    final coll = db.payments
        .where((e) => e['kind'] == 'customer' && inR(e['date'] as String))
        .fold<double>(0, (a, e) => a + n(e['amount']));
    final top = qty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    const labels = ['اليوم', 'آخر 7 أيام', 'هذا الشهر'];
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        Wrap(spacing: 8, children: [
          for (var i = 0; i < 3; i++)
            ChoiceChip(
                label: Text(labels[i]),
                selected: mode == i,
                onSelected: (_) => setState(() => setRange(i))),
          ChoiceChip(label: const Text('مخصص'), selected: mode == 3, onSelected: (_) => pick()),
        ]),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('من ${ds(from)} إلى ${ds(to)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Card(
          child: Column(children: [
            row('عدد الفواتير', '${ss.length}'),
            row('إجمالي المبيعات', f(total)),
            row('ربح المبيعات', f(profit), c: Colors.green),
            row('الخصومات', f(disc)),
            row('ديون جديدة على العملاء', f(debt), c: Colors.deepOrange),
            row('المصروفات', f(exp), c: Colors.red),
            row('صافي الربح (الربح - المصروفات)', f(profit - exp), c: Colors.purple),
            row('مشتريات بضاعة (للعلم)', f(buy)),
            row('مرتجعات (حُذفت من المبيعات)', f(ret), c: Colors.red),
            row('تحصيل ديون العملاء', f(coll), c: Colors.green),
          ]),
        ),
        const Padding(
            padding: EdgeInsets.all(8),
            child: Text('الأكثر مبيعاً', style: TextStyle(fontWeight: FontWeight.bold))),
        Card(
          child: Column(children: [
            if (top.isEmpty) const ListTile(title: Text('لا توجد مبيعات')),
            for (final e in top.take(5)) row(e.key, 'الكمية ${f(e.value)}'),
          ]),
        ),
        const Padding(
            padding: EdgeInsets.all(8),
            child: Text('المبيعات حسب الموظف', style: TextStyle(fontWeight: FontWeight.bold))),
        Card(
          child: Column(children: [
            if (emp.isEmpty) const ListTile(title: Text('لا توجد مبيعات')),
            for (final e in emp.entries) row(e.key, f(e.value)),
          ]),
        ),
        const Padding(
            padding: EdgeInsets.all(8),
            child: Text('ملاحظة: دخل الصيانة غير مشمول في هذا التقرير.',
                style: TextStyle(color: Colors.grey))),
      ]),
    );
  }
}

class CashPage extends StatelessWidget {
  const CashPage({super.key});

  double expected() {
    final now = DateTime.now();
    double e = 0;
    for (final s in db.sales) {
      if (s['by'] == db.me?['name'] && sameDay(DateTime.parse(s['date'] as String), now)) {
        if (s['method'] != 'تحويل') e += n(s['paid']);
      }
    }
    for (final x in db.payments) {
      if (x['kind'] == 'customer' &&
          x['by'] == db.me?['name'] &&
          sameDay(DateTime.parse(x['date'] as String), now)) {
        e += n(x['amount']);
      }
    }
    return e;
  }

  Future<void> close(BuildContext c) async {
    final e = expected();
    final r = await form(c, 'إقفال الصندوق - المتوقع ${f(e)}',
        ['المبلغ الموجود فعلياً في الدرج'], null, {0});
    if (r == null || r[0].isEmpty) return;
    final act = pd(r[0]);
    db.closings.add({
      'id': nid(),
      'date': DateTime.now().toIso8601String(),
      'by': db.me?['name'],
      'expected': e,
      'actual': act,
      'diff': act - e,
    });
    db.save();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          final list = db.closings
              .where((x) => isAdmin || x['by'] == db.me?['name'])
              .toList()
              .reversed
              .toList();
          return Scaffold(
            appBar: AppBar(title: const Text('إقفال الصندوق اليومي')),
            body: ListView(padding: const EdgeInsets.all(8), children: [
              Card(
                child: Column(children: [
                  row('الموظف', '${db.me?['name']}'),
                  row('المتوقع في الدرج (مبيعات نقدية + تحصيل ديون)', f(expected())),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: ElevatedButton.icon(
                        onPressed: () => close(c),
                        icon: const Icon(Icons.lock_clock),
                        label: const Text('إقفال الصندوق')),
                  ),
                ]),
              ),
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('سجل الإقفالات', style: TextStyle(fontWeight: FontWeight.bold))),
              if (list.isEmpty) empty(),
              for (final x in list)
                ListTile(
                  title: Text(
                      '${x['by']} • ${(x['date'] as String).substring(0, 16).replaceFirst('T', ' ')}'),
                  subtitle: Text(
                      'المتوقع ${f(n(x['expected']))} | الفعلي ${f(n(x['actual']))}'),
                  trailing: Text(
                    n(x['diff']) == 0
                        ? 'مطابق'
                        : n(x['diff']) > 0
                            ? 'زيادة ${f(n(x['diff']))}'
                            : 'عجز ${f(-n(x['diff']))}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: n(x['diff']) == 0
                            ? Colors.green
                            : n(x['diff']) > 0
                                ? Colors.blue
                                : Colors.red),
                  ),
                ),
            ]),
          );
        },
      );
}

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final list = db.logs.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('سجل العمليات')),
      body: list.isEmpty
          ? empty()
          : ListView(children: [
              for (final l in list)
                ListTile(
                  dense: true,
                  title: Text('${l['text']}'),
                  subtitle: Text(
                      '${l['by']} • ${(l['date'] as String).substring(0, 16).replaceFirst('T', ' ')}'),
                ),
            ]),
    );
  }
}

class MovesPage extends StatelessWidget {
  const MovesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final list = db.moves.reversed.take(300).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('حركات المخزون')),
      body: list.isEmpty
          ? empty()
          : ListView(children: [
              for (final m in list)
                ListTile(
                  dense: true,
                  title: Text('${m['name']} • ${m['type']}'),
                  subtitle: Text(
                      '${(m['date'] as String).substring(0, 16).replaceFirst('T', ' ')} • ${m['by']} • الرصيد بعد: ${f(n(m['after']))}'),
                  trailing: Text(
                    '${n(m['delta']) > 0 ? '+' : ''}${f(n(m['delta']))}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: n(m['delta']) < 0 ? Colors.red : Colors.green),
                  ),
                ),
            ]),
    );
  }
}

class ArchivePage extends StatelessWidget {
  const ArchivePage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          final ps = db.products.where((x) => x['archived'] == true).toList();
          final cu = db.customers.where((x) => x['archived'] == true).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('الأرشيف')),
            body: ps.isEmpty && cu.isEmpty
                ? empty()
                : ListView(children: [
                    for (final x in ps)
                      ListTile(
                        leading: const Icon(Icons.phone_android),
                        title: Text('${x['name']}'),
                        subtitle: Text('منتج • الكمية ${f(n(x['qty']))}'),
                        trailing: TextButton(
                            onPressed: () {
                              x.remove('archived');
                              db.log('استرجاع منتج ${x['name']}');
                              db.save();
                            },
                            child: const Text('استرجاع')),
                      ),
                    for (final x in cu)
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text('${x['name']}'),
                        subtitle: const Text('عميل'),
                        trailing: TextButton(
                            onPressed: () {
                              x.remove('archived');
                              db.log('استرجاع عميل ${x['name']}');
                              db.save();
                            },
                            child: const Text('استرجاع')),
                      ),
                  ]),
          );
        },
      );
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InvState();
}

class _InvState extends State<InventoryPage> {
  final cs = <int, TextEditingController>{};
  String q = '';

  TextEditingController ctl(int id) =>
      cs.putIfAbsent(id, () => TextEditingController());

  Future<void> apply() async {
    if (!await ask(context, 'اعتماد الجرد وتعديل الكميات في النظام؟')) return;
    final diffs = <String>[];
    double val = 0;
    for (final p in db.products.where((x) => x['archived'] != true)) {
      final t = ctl(p['id'] as int).text.trim();
      if (t.isEmpty) continue;
      final cnt = pd(t).toInt();
      final sys = n(p['qty']).toInt();
      if (cnt == sys) continue;
      diffs.add('${p['name']}: النظام $sys ← الفعلي $cnt');
      val += (cnt - sys) * n(p['cost']);
      p['qty'] = cnt;
      db.move(p, 'جرد', cnt - sys, 'تسوية جرد');
    }
    if (!mounted) return;
    if (diffs.isEmpty) {
      msg(context, 'لا توجد فروقات في المنتجات المُدخلة');
      return;
    }
    db.log('اعتماد جرد: ${diffs.length} فروقات بقيمة ${f(val)}');
    db.save();
    for (final x in cs.values) {
      x.clear();
    }
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('نتيجة الجرد (${diffs.length} فروقات)'),
        content: SingleChildScrollView(
            child: Text('${diffs.join('\n')}\n\nفرق القيمة بسعر الشراء: ${f(val)}')),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = db.products
        .where((p) =>
            p['archived'] != true &&
            '${p['name']} ${p['imei']}'.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('الجرد الدوري')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث بالاسم أو الباركود',
                border: OutlineInputBorder()),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('أدخل الكمية الفعلية للمنتجات التي عددتها فقط، واترك الباقي فارغاً.')),
        Expanded(
          child: list.isEmpty
              ? empty()
              : ListView(children: [
                  for (final p in list)
                    ListTile(
                      title: Text('${p['name']}'),
                      subtitle: Text('النظام: ${f(n(p['qty']))}'),
                      trailing: SizedBox(
                        width: 90,
                        child: TextField(
                          controller: ctl(p['id'] as int),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'الفعلي'),
                        ),
                      ),
                    ),
                ]),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          child: ElevatedButton(onPressed: apply, child: const Text('اعتماد الجرد')),
        ),
      ]),
    );
  }
}
