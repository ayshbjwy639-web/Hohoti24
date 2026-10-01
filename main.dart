import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef M = Map<String, dynamic>;

double n(dynamic v) => v is num ? v.toDouble() : 0.0;
double pd(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0.0;
String f(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
int nid() => DateTime.now().microsecondsSinceEpoch;
String newCode() =>
    (DateTime.now().millisecondsSinceEpoch % 1000000000000).toString().padLeft(12, '0');

class Db extends ChangeNotifier {
  static final Db i = Db._();
  Db._();
  static const keys = ['products', 'customers', 'sales', 'repairs', 'expenses', 'users', 'suppliers', 'purchases', 'closings'];
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

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    for (final k in keys) {
      final s = p!.getString(k);
      if (s != null) {
        t[k] = (jsonDecode(s) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    }
  }

  void save() {
    for (final k in keys) {
      p?.setString(k, jsonEncode(t[k]));
    }
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
        title: 'محل الهواتف',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
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
        'pass': ps.text,
        'role': 'admin'
      };
      db.users.add(m);
      db.me = m;
      db.save();
    } else {
      final l = db.users.where((x) => x['user'] == u && x['pass'] == ps.text).toList();
      if (l.isEmpty) {
        msg(context, 'بيانات الدخول غير صحيحة');
        return;
      }
      db.me = l.first;
      db.save();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.phone_android, size: 72, color: Colors.indigo),
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

class _HomeState extends State<Home> {
  int i = 0;
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
              subtitle: const Text('ينسخ كل البيانات، الصقها في واتساب أو ملاحظات'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: db.export()));
                if (c.mounted) msg(c, 'تم نسخ البيانات، الصقها في مكان آمن');
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
    db.users.add({
      'id': nid(),
      'name': nm.text.trim(),
      'user': u,
      'pass': ps.text,
      'role': adm ? 'admin' : 'staff'
    });
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
                  u['pass'] = r[0];
                  db.save();
                },
                trailing: u['id'] == db.me?['id']
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (await sure(c)) {
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
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: db,
        builder: (c, _) {
          final now = DateTime.now();
          double ts = 0, tp = 0, sales = 0, profit = 0;
          for (final s in db.sales) {
            final d = DateTime.parse(s['date'] as String);
            sales += n(s['total']);
            profit += n(s['profit']);
            if (d.year == now.year && d.month == now.month && d.day == now.day) {
              ts += n(s['total']);
              tp += n(s['profit']);
            }
          }
          final exp = db.expenses.fold<double>(0, (a, e) => a + n(e['amount']));
          final rep = db.repairs
              .where((r) => n(r['status']) == 2)
              .fold<double>(0, (a, r) => a + n(r['cost']));
          final debts = db.customers.fold<double>(0, (a, e) => a + n(e['debt']));
          final stock = db.products
              .fold<double>(0, (a, e) => a + n(e['cost']) * n(e['qty']));
          final low = db.products.where((p) => n(p['qty']) <= 2).toList();
          final cards = <(String, double, IconData, Color)>[
            ('مبيعات اليوم', ts, Icons.today, Colors.blue),
            ('ربح اليوم', tp, Icons.trending_up, Colors.green),
            ('إجمالي المبيعات', sales, Icons.shopping_cart, Colors.indigo),
            ('إجمالي الربح', profit, Icons.savings, Colors.teal),
            ('دخل الصيانة', rep, Icons.build, Colors.orange),
            ('المصروفات', exp, Icons.money_off, Colors.red),
            ('صافي الربح', profit + rep - exp, Icons.account_balance, Colors.purple),
            ('ديون العملاء', debts, Icons.warning, Colors.deepOrange),
            ('قيمة المخزون', stock, Icons.inventory, Colors.brown),
          ];
          return Scaffold(
            appBar: AppBar(title: const Text('لوحة التحكم')),
            body: ListView(padding: const EdgeInsets.all(8), children: [
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
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(k.$3, color: k.$4),
                              Text(k.$1),
                              Text(f(k.$2),
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold)),
                            ]),
                      ),
                    ),
                ],
              ),
              if (low.isNotEmpty)
                Card(
                  color: Colors.red.shade50,
                  child: Column(children: [
                    const ListTile(
                        leading: Icon(Icons.error, color: Colors.red),
                        title: Text('تنبيه: منتجات قاربت على النفاد')),
                    for (final p in low)
                      ListTile(
                          dense: true,
                          title: Text('${p['name']}'),
                          trailing: Text('الكمية: ${f(n(p['qty']))}')),
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
      ['الاسم', 'التصنيف', 'الباركود / IMEI (فارغ = توليد تلقائي)', 'سعر الشراء', 'سعر البيع', 'الكمية'],
      p == null
          ? null
          : [
              '${p['name']}',
              '${p['cat']}',
              '${p['imei']}',
              f(n(p['cost'])),
              f(n(p['price'])),
              f(n(p['qty']))
            ],
      {3, 4, 5},
      scanIdx: 2,
    );
    if (r == null || r[0].isEmpty) return;
    final m = p ?? <String, dynamic>{'id': nid()};
    m['name'] = r[0];
    m['cat'] = r[1];
    m['imei'] = r[2].isEmpty ? newCode() : r[2];
    m['cost'] = pd(r[3]);
    m['price'] = pd(r[4]);
    m['qty'] = pd(r[5]).toInt();
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
              .where((p) => '${p['name']} ${p['imei']} ${p['cat']}'
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
                                  n(p['qty']) <= 2 ? Colors.red : Colors.green,
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
                                        if (await sure(c)) {
                                          db.products.remove(p);
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
    final l = db.products.where((p) => '${p['imei']}' == code).toList();
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
                  for (final cu in db.customers)
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
    }
    String cname = 'عميل نقدي';
    if (cid != null) {
      final cu = db.customers.firstWhere((x) => x['id'] == cid);
      cu['debt'] = n(cu['debt']) + debt;
      cname = '${cu['name']}';
    }
    db.sales.add({
      'id': nid(),
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
                  n(p['qty']) > 0 &&
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

  Future<void> returnSale(BuildContext c, M s) async {
    if (!await ask(c, 'إرجاع الفاتورة بالكامل؟ ستعود الكميات للمخزون')) return;
    for (final i in s['items'] as List) {
      final l = db.products
          .where((p) =>
              p['id'] == i['pid'] || (i['pid'] == null && p['name'] == i['name']))
          .toList();
      if (l.isNotEmpty) {
        l.first['qty'] = n(l.first['qty']).toInt() + n(i['qty']).toInt();
      }
    }
    if (s['cid'] != null) {
      final l = db.customers.where((x) => x['id'] == s['cid']).toList();
      if (l.isNotEmpty) {
        final left = n(l.first['debt']) - n(s['debt']);
        l.first['debt'] = left < 0 ? 0.0 : left;
      }
    }
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
                        title: Text('${s['customer']} - ${f(n(s['total']))}'),
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
                  for (final m in db.customers)
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
                              if (await sure(c)) {
                                db.customers.remove(m);
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
        ['الجهاز', 'اسم العميل', 'المشكلة', 'التكلفة'],
        m == null
            ? null
            : ['${m['device']}', '${m['customer']}', '${m['problem']}', f(n(m['cost']))],
        {3});
    if (r == null || r[0].isEmpty) return;
    final x = m ?? <String, dynamic>{'id': nid(), 'status': 0};
    x['device'] = r[0];
    x['customer'] = r[1];
    x['problem'] = r[2];
    x['cost'] = pd(r[3]);
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
                      title: Text('${r['device']} - ${r['customer']}'),
                      subtitle: Text(
                          '${r['problem']}\n${f(n(r['cost']))} | ${st[n(r['status']).toInt()]}'),
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
    int? pid = db.products.first['id'] as int;
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
                  for (final p in db.products)
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
        e += n(s['paid']);
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
                  row('المتوقع في الدرج اليوم (المدفوع نقداً)', f(expected())),
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
