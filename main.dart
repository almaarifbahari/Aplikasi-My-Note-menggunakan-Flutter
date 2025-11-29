import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'web_download.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    const MethodChannel('open_txt_channel').setMethodCallHandler((call) async {
      if (call.method == 'openFile') {}
    });
  }
  runApp(const MyNoteApp());
}

// Enum untuk metode pengurutan
enum SortOrder { newest, oldest, nameAZ, nameZA }

class MyNoteApp extends StatelessWidget {
  const MyNoteApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'My Note',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.white,
          textTheme: GoogleFonts.poppinsTextTheme(),
          colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.deepPurple),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            backgroundColor: Color(0xFF6A5AE0),
            foregroundColor: Colors.white,
          ),
        ),
        home: const HomeScreen(),
      );
}

class Note {
  String id;
  String name;
  String content;
  int lastModifiedMillis;

  Note({
    required this.id,
    required this.name,
    required this.content,
    required this.lastModifiedMillis,
  });

  factory Note.createNew({required String name}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Note(id: '$now', name: name, content: '', lastModifiedMillis: now);
  }

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        name: j['name'] as String,
        content: j['content'] as String,
        lastModifiedMillis: (j['lastModifiedMillis'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
        'lastModifiedMillis': lastModifiedMillis,
      };

  DateTime get lastModified => DateTime.fromMillisecondsSinceEpoch(lastModifiedMillis);
}

class NotesRepository {
  static const _key = 'my_notes_v1';
  static const _sortOrderKey = 'sort_order_preference';

  Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveAll(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(notes.map((n) => n.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> addOrUpdate(Note note) async {
    final notes = await loadNotes();
    final idx = notes.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      notes[idx] = note;
    } else {
      notes.insert(0, note);
    }
    await saveAll(notes);
  }

  Future<void> deleteById(String id) async {
    final notes = await loadNotes();
    notes.removeWhere((n) => n.id == id);
    await saveAll(notes);
  }

  Future<void> rename(String id, String newName) async {
    final notes = await loadNotes();
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx >= 0) {
      notes[idx].name = newName;
      notes[idx].lastModifiedMillis = DateTime.now().millisecondsSinceEpoch;
      await saveAll(notes);
    }
  }

  Future<String> nextDefaultName() async {
    final notes = await loadNotes();
    int i = 1;
    String candidate;
    final names = notes.map((n) => n.name).toSet();
    do {
      candidate = 'mynote$i';
      i++;
    } while (names.contains(candidate));
    return candidate;
  }

  Future<void> saveSortOrder(SortOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortOrderKey, order.toString());
  }

  Future<SortOrder> loadSortOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_sortOrderKey) ?? SortOrder.newest.toString();
    try {
      return SortOrder.values.firstWhere((e) => e.toString() == value);
    } catch (e) {
      return SortOrder.newest; // Default jika terjadi kesalahan
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final repo = NotesRepository();
  List<Note> notes = [];
  Set<String> selected = {};
  bool selectMode = false;
  bool loading = true;
  SortOrder currentSortOrder = SortOrder.newest;

  @override
  void initState() {
    super.initState();
    _loadSortOrderAndNotes();
  }

  Future<void> _loadSortOrderAndNotes() async {
    setState(() => loading = true);
    currentSortOrder = await repo.loadSortOrder();
    await _loadNotes();
  }

  Future<void> _loadNotes() async {
    notes = await repo.loadNotes();
    if (!mounted) return;
    setState(() {
      loading = false;
      selectMode = selected.isNotEmpty;
    });
  }

  void toggleSelect(String id, [bool? val]) {
    setState(() {
      if (val == true) {
        selected.add(id);
      } else if (val == false) {
        selected.remove(id);
      } else if (selected.contains(id)) {
        selected.remove(id);
      } else {
        selected.add(id);
      }
      selectMode = selected.isNotEmpty;
    });
  }

  void exitSelectMode() {
    setState(() {
      selectMode = false;
      selected.clear();
    });
  }

  Future<void> deleteSelected() async {
    if (selected.isEmpty) return;
    final cnt = selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hapus $cnt catatan?'),
        content: const Text('Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      for (final id in selected) {
        await repo.deleteById(id);
      }
      Fluttertoast.showToast(msg: '$cnt catatan dihapus', backgroundColor: Colors.grey.shade800, textColor: Colors.white);
      exitSelectMode();
      await _loadNotes();
    }
  }

  Future<void> shareSelected() async {
    if (selected.isEmpty) return;
    final items = notes.where((n) => selected.contains(n.id)).toList();
    if (items.isEmpty) return;

    if (items.length == 1) {
      final n = items.first;
      await SharePlus.instance.share(ShareParams(text: n.content.isEmpty ? '(kosong)' : n.content, subject: n.name));
    } else {
      final text = items.map((n) => '${n.name}\n${n.content}\n\n').join();
      await SharePlus.instance.share(ShareParams(text: text, subject: 'Beberapa catatan'));
    }
  }

  String categoryOf(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    final check = DateTime(dt.year, dt.month, dt.day);
    if (check == today) {
      return 'Baru Saja';
    }
    if (check == yesterday) {
      return 'Kemarin';
    }
    if (check.isAfter(weekAgo)) {
      const days = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
      return 'Hari ${days[dt.weekday % 7]}';
    }
    return 'Lainnya';
  }

  Map<String, List<Note>> grouped() {
    final sortedNotes = List<Note>.from(notes);
    switch (currentSortOrder) {
      case SortOrder.newest:
        sortedNotes.sort((a, b) => b.lastModifiedMillis.compareTo(a.lastModifiedMillis));
        break;
      case SortOrder.oldest:
        sortedNotes.sort((a, b) => a.lastModifiedMillis.compareTo(b.lastModifiedMillis));
        break;
      case SortOrder.nameAZ:
        sortedNotes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortOrder.nameZA:
        sortedNotes.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
    }

    final map = <String, List<Note>>{};
    for (final n in sortedNotes) {
      final cat = categoryOf(n.lastModified);
      map.putIfAbsent(cat, () => []).add(n);
    }
    return map;
  }

  Future<void> _showSortDialog() async {
    final initialOrder = currentSortOrder;
    SortOrder? selectedOrder = initialOrder;

    final result = await showDialog<SortOrder>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Urutkan Berdasarkan'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<SortOrder>(
                title: const Text('Terbaru'),
                value: SortOrder.newest,
                groupValue: selectedOrder,
                onChanged: (value) => setState(() => selectedOrder = value),
              ),
              RadioListTile<SortOrder>(
                title: const Text('Terlama'),
                value: SortOrder.oldest,
                groupValue: selectedOrder,
                onChanged: (value) => setState(() => selectedOrder = value),
              ),
              RadioListTile<SortOrder>(
                title: const Text('Nama A-Z'),
                value: SortOrder.nameAZ,
                groupValue: selectedOrder,
                onChanged: (value) => setState(() => selectedOrder = value),
              ),
              RadioListTile<SortOrder>(
                title: const Text('Nama Z-A'),
                value: SortOrder.nameZA,
                groupValue: selectedOrder,
                onChanged: (value) => setState(() => selectedOrder = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              if (selectedOrder != null) {
                Navigator.pop(context, selectedOrder);
              }
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );

    if (result != null && result != initialOrder) {
      setState(() {
        currentSortOrder = result;
      });
      await repo.saveSortOrder(result);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedNotes = grouped();
    final keys = groupedNotes.keys.toList()
      ..sort((a, b) {
        const ord = [
          'Baru Saja',
          'Kemarin',
          'Hari Minggu',
          'Hari Senin',
          'Hari Selasa',
          'Hari Rabu',
          'Hari Kamis',
          'Hari Jumat',
          'Hari Sabtu',
          'Lainnya'
        ];
        if (currentSortOrder != SortOrder.newest) {
          return 0;
        }
        return ord.indexOf(a).compareTo(ord.indexOf(b));
      });

    return Scaffold(
      appBar: AppBar(
        title: selectMode ? Text('${selected.length} dipilih') : const Text('My Note'),
        leading: selectMode ? IconButton(icon: const Icon(Icons.close), onPressed: exitSelectMode) : null,
        actions: [
          if (!selectMode)
            IconButton(
              onPressed: _showSortDialog,
              icon: const Icon(Icons.sort),
              tooltip: 'Urutkan',
            ),
          if (selectMode)
            IconButton(icon: const Icon(Icons.share), onPressed: shareSelected),
          if (selectMode)
            IconButton(icon: const Icon(Icons.delete), onPressed: deleteSelected),
          if (!selectMode)
            IconButton(
                onPressed: () async {
                  await _loadNotes();
                },
                icon: const Icon(Icons.refresh))
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (!selectMode) ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GestureDetector(
                      onTap: () => openEditor(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFF6A5AE0), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.note_add, color: Colors.white, size: 32),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Buat Catatan Baru', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Disimpan di browser / lokal', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const Divider(),
                ],
                for (final cat in keys) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(cat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  ...groupedNotes[cat]!.map((n) {
                    final mod = n.lastModified.toString().split('.')[0];
                    return ListTile(
                      leading: selectMode
                          ? Checkbox(value: selected.contains(n.id), onChanged: (v) => toggleSelect(n.id, v))
                          : const Icon(Icons.description, color: Colors.deepPurple),
                      title: Text(n.name),
                      subtitle: Text(mod),
                      trailing: selectMode
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'delete') {
                                  await repo.deleteById(n.id);
                                  Fluttertoast.showToast(msg: 'Catatan dihapus', backgroundColor: Colors.grey.shade800, textColor: Colors.white);
                                  if (!mounted) return;
                                  await _loadNotes();
                                } else if (v == 'rename') {
                                  await renameNoteDialog(n);
                                } else if (v == 'share') {
                                  if (n.content.isEmpty) {
                                    Fluttertoast.showToast(msg: 'Tidak ada isi untuk dibagikan', backgroundColor: Colors.grey.shade800, textColor: Colors.white);
                                  } else {
                                    await SharePlus.instance.share(ShareParams(text: n.content, subject: n.name));
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.redAccent), SizedBox(width: 8), Text('Hapus')])),
                                const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, color: Colors.orangeAccent), SizedBox(width: 8), Text('Ganti Nama')])),
                                const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, color: Colors.blueAccent), SizedBox(width: 8), Text('Bagikan')])),
                              ],
                            ),
                      onTap: () => selectMode ? toggleSelect(n.id) : openEditor(n.id),
                      onLongPress: () => toggleSelect(n.id),
                    );
                  }),
                ],
                if (notes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('Tidak ada catatan')),
                  ),
              ],
            ),
    );
  }

  Future<void> renameNoteDialog(Note n) async {
    final controller = TextEditingController(text: n.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ganti Nama'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Nama baru')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      final newName = controller.text.trim();
      if (newName.isNotEmpty) {
        await repo.rename(n.id, newName);
        Fluttertoast.showToast(msg: 'Nama diubah', backgroundColor: Colors.grey.shade800, textColor: Colors.white);
        await _loadNotes();
      }
    }
  }

  Future<void> openEditor([String? id]) async {
    await navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => NoteEditorScreen(noteId: id),
    ));
    if (!mounted) return;
    await _loadNotes();
  }
}

class NoteEditorScreen extends StatefulWidget {
  final String? noteId;
  const NoteEditorScreen({super.key, this.noteId});

  @override
  State<NoteEditorScreen> createState() => NoteEditorScreenState();
}

class NoteEditorScreenState extends State<NoteEditorScreen> {
  final NotesRepository repo = NotesRepository();
  final TextEditingController ctrl = TextEditingController();
  late Note working;
  bool isNew = true;
  String status = '';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (widget.noteId == null) {
      final name = await repo.nextDefaultName();
      if (!mounted) return;
      working = Note.createNew(name: name);
      isNew = true;
      ctrl.text = '';
      setState(() {});
      return;
    }
    final all = await repo.loadNotes();
    if (!mounted) return;
    final found = all.firstWhere((n) => n.id == widget.noteId, orElse: () => Note.createNew(name: 'mynote'));
    working = Note(
      id: found.id,
      name: found.name,
      content: found.content,
      lastModifiedMillis: found.lastModifiedMillis,
    );
    isNew = found.content.isEmpty && found.lastModifiedMillis == working.lastModifiedMillis && found.name == working.name && widget.noteId == null;
    ctrl.text = working.content;
    setState(() {});
  }

  Future<void> saveAs() async {
    final defaultName = await repo.nextDefaultName();
    final nameCtrl = TextEditingController(text: defaultName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Simpan Dokumen'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'Masukkan nama file')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      final name = nameCtrl.text.trim().isEmpty ? defaultName : nameCtrl.text.trim();
      final now = DateTime.now().millisecondsSinceEpoch;
      final note = Note(id: '$now', name: name, content: ctrl.text, lastModifiedMillis: now);
      await repo.addOrUpdate(note);
      Fluttertoast.showToast(msg: 'Dokumen tersimpan', backgroundColor: Colors.grey.shade800, textColor: Colors.white);
      if (kIsWeb) {
        await downloadFile('$name.txt', note.content, mime: 'text/plain');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: note.id)));
    }
  }

  Future<void> save() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    working.content = ctrl.text;
    working.lastModifiedMillis = now;
    await repo.addOrUpdate(working);
    if (!mounted) return;
    setState(() => status = 'Tersimpan: ${working.name}');
    Fluttertoast.showToast(msg: 'Tersimpan', backgroundColor: Colors.grey.shade800, textColor: Colors.white);
    if (kIsWeb) {
      await downloadFile('${working.name}.txt', working.content, mime: 'text/plain');
    }
  }

  Future<void> share() async {
    if (ctrl.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'Tidak ada catatan', backgroundColor: Colors.grey.shade800, textColor: Colors.white);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: ctrl.text, subject: working.name));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(working.name, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(onPressed: isNew ? null : save, icon: const Icon(Icons.save), tooltip: 'Simpan'),
            IconButton(onPressed: saveAs, icon: const Icon(Icons.save_as), tooltip: 'Simpan Sebagai'),
            IconButton(onPressed: share, icon: const Icon(Icons.share), tooltip: 'Bagikan'),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration.collapsed(hintText: 'Tulis sesuatu...'),
                ),
              ),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(status, style: const TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        ),
      );
}