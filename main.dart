import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef M = Map<String, dynamic>;

double n(dynamic v) => v is num ? v.toDouble() : 0.0;
double pd(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0.0;
String f(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
int nid() => DateTime.now().microsecondsSinceEpoch;

class Db extends ChangeNotifier {
  static final Db i = Db._();
  Db._();
  static const keys = ['products', 'customers', 'sales', 'repairs', 'expenses'];
  final Map<String, List<M>> t = {for (final k in keys) k: <M>[]};
  SharedPreferences? p;
  List<M> get products => t['products']!;
  List<M> get customers => t['customers']!;
  List<M> get sales => t['sales']!;
  List<M> get repairs => t['repairs']!;
  List<M> get expenses => t['expenses']!;

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
}

final db = Db.i;

Future<List<String>?> form(BuildContext c, String title, List<String> labels,
    List<String>? init, Set<int> nums) {
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
              decoration: InputDecoration(labelText: labels[i]),
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

Future<bool> sure(BuildContext c) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('تأكيد الحذف؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لا')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('نعم')),
        ],
      ),
    ) ??
    false;

void msg(BuildContext c, String s) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

Widget empty() => const Center(child: Text('لا توجد بيانات'));

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
        home: const Home(),
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
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: i, children: const [
          Dash(),
          ProductsPage(),
          PosPage(),
          CustomersPage(),
          RepairsPage(),
          ExpensesPage(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.phone_android), label: 'المخزون'),
            NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'البيع'),
            NavigationDestination(icon: Icon(Icons.people), label: 'العملاء'),
            NavigationDestination(icon: Icon(Icons.build), label: 'الصيانة'),
            NavigationDestination(icon: Icon(Icons.money_off), label: 'المصروفات'),
          ],
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
      ['الاسم', 'التصنيف', 'IMEI / باركود', 'سعر الشراء', 'سعر البيع', 'الكمية'],
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
    );
    if (r == null || r[0].isEmpty) return;
    final m = p ?? <String, dynamic>{'id': nid()};
    m['name'] = r[0];
    m['cat'] = r[1];
    m['imei'] = r[2];
    m['cost'] = pd(r[3]);
    m['price'] = pd(r[4]);
    m['qty'] = pd(r[5]).toInt();
    if (p == null) db.products.add(m);
    db.save();
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
          return Scaffold(
            appBar: AppBar(title: const Text('المخزون')),
            floatingActionButton: FloatingActionButton(
                onPressed: () => edit(), child: const Icon(Icons.add)),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'بحث بالاسم أو IMEI',
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
                                '${p['cat']} • IMEI: ${p['imei']}\nشراء ${f(n(p['cost']))} | بيع ${f(n(p['price']))}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                if (await sure(c)) {
                                  db.products.remove(p);
                                  db.save();
                                }
                              },
                            ),
                            onTap: () => edit(p),
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

  M prod(int id) => db.products.firstWhere((p) => p['id'] == id);

  double get sub =>
      cart.entries.fold<double>(0, (a, e) => a + n(prod(e.key)['price']) * e.value);

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
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'بحث عن منتج',
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
  @override
  Widget build(BuildContext context) {
    final list = db.sales.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المبيعات')),
      body: list.isEmpty
          ? empty()
          : ListView(children: [
              for (final s in list)
                ListTile(
                  title: Text('${s['customer']} - ${f(n(s['total']))}'),
                  subtitle: Text((s['date'] as String)
                      .substring(0, 16)
                      .replaceFirst('T', ' ')),
                  trailing: n(s['debt']) > 0
                      ? Text('دين ${f(n(s['debt']))}',
                          style: const TextStyle(color: Colors.red))
                      : const Icon(Icons.check_circle, color: Colors.green),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('تفاصيل الفاتورة'),
                      content: Text((s['items'] as List)
                              .map((i) =>
                                  '${i['name']} × ${i['qty']} = ${f(n(i['price']) * n(i['qty']))}')
                              .join('\n') +
                          '\n\nالخصم: ${f(n(s['discount']))}\nالإجمالي: ${f(n(s['total']))}\nالمدفوع: ${f(n(s['paid']))}\nالمتبقي: ${f(n(s['debt']))}'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('إغلاق'))
                      ],
                    ),
                  ),
                ),
            ]),
    );
  }
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
                      subtitle: Text(
                          '${m['phone']}\nالدين: ${f(n(m['debt']))}'),
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
                      subtitle: Text((e['date'] as String)
                          .substring(0, 10)),
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
