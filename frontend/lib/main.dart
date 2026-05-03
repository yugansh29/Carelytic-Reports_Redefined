import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'api.dart';
import 'package:printing/printing.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static late SharedPreferences prefs;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
  }

  static String get doctorName => prefs.getString('doctor_name') ?? 'Dr. Ravi Sharma';
  static Future<void> setDoctorName(String value) => prefs.setString('doctor_name', value);

  static String get specialty => prefs.getString('specialty') ?? 'Cardiology';
  static Future<void> setSpecialty(String value) => prefs.setString('specialty', value);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.init();
  runApp(const ClinicNoteApp());
}

class ClinicNoteApp extends StatelessWidget {
  const ClinicNoteApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carelytic Reports',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D7E6A),
          primary: const Color(0xFF0D7E6A),
          secondary: const Color(0xFF104A6B),
        ),
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(Theme.of(context).textTheme).copyWith(
          titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E)),
          bodyMedium: GoogleFonts.inter(color: const Color(0xFF4B5563)),
        ),
      ),
      home: const HomeLayout(),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// HOME LAYOUT
// ──────────────────────────────────────────────────────────────────
class HomeLayout extends StatefulWidget {
  const HomeLayout({super.key});
  @override
  State<HomeLayout> createState() => _HomeLayoutState();
}

class _HomeLayoutState extends State<HomeLayout> {
  int _currentIndex = 0;
  bool _privacyMode = false;

  final List<Map<String, dynamic>> _patients = [
    {
      'name': 'Raj Sharma', 'age': '42', 'sex': 'M', 'visit_type': 'Follow-up', 'specialty': 'Cardiology',
      'chief_complaint': 'Mild chest palpitation', 'status': 'Recent',
      // Matches backend DUMMY_EHR key so demo EHR loads without extra config.
      'patient_id': 'p123',
    },
    {
      'name': 'Jane Doe', 'age': '45', 'sex': 'F', 'visit_type': 'Initial Visit', 'specialty': 'Neurology',
      'chief_complaint': 'Recurrent migraines', 'status': 'Scheduled', 'patient_id': 'P-8832',
    },
    {
      'name': 'Michael Chen', 'age': '58', 'sex': 'M', 'visit_type': 'Consultation', 'specialty': 'Gastroenterology',
      'chief_complaint': 'Chronic acid reflux', 'status': 'Follow-up', 'patient_id': 'P-7741',
    },
    {
      'name': 'Elena Rossi', 'age': '34', 'sex': 'F', 'visit_type': 'Post-Op', 'specialty': 'Orthopedics',
      'chief_complaint': 'Left knee ACL recovery check', 'status': 'In review', 'patient_id': 'P-6610',
    },
    {
      'name': 'Sofia Martinez', 'age': '29', 'sex': 'F', 'visit_type': 'Routine', 'specialty': 'Primary Care',
      'chief_complaint': 'Annual physical exam', 'status': 'Completed', 'patient_id': 'P-5529',
    },
  ];

  Map<String, dynamic>? _activePatient;

  void _onSaveNote(Map<String, dynamic> note) {
    if (_activePatient != null) {
      setState(() {
        final idx = _patients.indexWhere((p) => p['name'] == _activePatient!['name']);
        if (idx != -1) {
          _patients[idx]['status'] = 'Saved';
          _patients[idx]['last_note'] = note;
        } else {
          // New patient was already added to list in onSubmit
        }
        _currentIndex = 0; // Redirect to Visits
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carelytic Report saved successfully ✓')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    Widget body;
    switch (_currentIndex) {
      case 0:
        body = DashboardScreen(
          patients: _patients,
          privacyMode: _privacyMode,
          onNewNote: () => setState(() => _currentIndex = 4),
          onLoadPatient: (p) => setState(() {
            _activePatient = p;
            _currentIndex = 1;
          }),
        );
        break;
      case 1:
        body = _activePatient == null
            ? const Center(child: Text('Select a patient from Visits to begin transcription'))
            : ComposerScreen(
                key: ValueKey(_activePatient!['name']),
                patient: _activePatient!,
                onSave: _onSaveNote,
              );
        break;
      case 2:
        body = HistoryScreen(patients: _patients);
        break;
      case 3:
        body = SettingsScreen(onSettingsChanged: () => setState(() {}));
        break;
      case 4:
        body = PatientIntakeScreen(
          onSubmit: (newPatient) => setState(() {
            _patients.insert(0, {...newPatient, 'status': 'New', 'patient_id': 'P-${DateTime.now().microsecondsSinceEpoch}'});
            _activePatient = _patients.first;
            _currentIndex = 1;
          }),
          onCancel: () => setState(() => _currentIndex = 0),
        );
        break;
      default:
        body = const Center(child: Text('Coming soon...'));
    }

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Carelytic', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF0D7E6A))),
          actions: const [
            CircleAvatar(radius: 14, backgroundColor: Color(0xFFE6F1FB), child: Text('DR', style: TextStyle(fontSize: 10, color: Color(0xFF185FA5)))),
            SizedBox(width: 16),
          ],
        ),
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex == 4 ? 0 : (_currentIndex > 3 ? 0 : _currentIndex),
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Visits'),
            NavigationDestination(icon: Icon(Icons.mic_none_outlined), selectedIcon: Icon(Icons.mic), label: 'Compose'),
            NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      );
    } else {
      return Scaffold(
        body: Row(
          children: [
            // Sidebar
            Container(
              width: 240,
              color: const Color(0xFF1A1A2E),
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.health_and_safety, color: Color(0xFF0D7E6A), size: 28),
                        const SizedBox(width: 12),
                        Text('Carelytic', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  _SidebarItem(icon: Icons.dashboard_outlined, label: 'Patient Visits', index: 0, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                  _SidebarItem(icon: Icons.mic_none_outlined, label: 'Quick Compose', index: 1, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                  _SidebarItem(icon: Icons.history_outlined, label: 'Report History', index: 2, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                  _SidebarItem(icon: Icons.settings_outlined, label: 'Settings', index: 3, current: _currentIndex, onTap: (i) => setState(() => _currentIndex = i)),
                  const Spacer(),
                  const Divider(color: Colors.white12, indent: 20, endIndent: 20),
                  ListTile(
                    leading: const CircleAvatar(radius: 14, child: Text('DR', style: TextStyle(fontSize: 10))),
                    title: Text(AppSettings.doctorName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    subtitle: Text(AppSettings.specialty, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 64,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.notifications_outlined, color: Colors.grey, size: 20),
                        const SizedBox(width: 20),
                        const Text('Privacy Mode', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Switch.adaptive(value: _privacyMode, onChanged: (v) => setState(() => _privacyMode = v)),
                      ],
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;
  const _SidebarItem({required this.icon, required this.label, required this.index, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = current == index;
    return InkWell(
      onTap: () => onTap(index),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? const Color(0xFF0D7E6A) : Colors.white60, size: 20),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.white60, fontSize: 14, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN
// ──────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  final List<Map<String, dynamic>> patients;
  final bool privacyMode;
  final VoidCallback onNewNote;
  final ValueChanged<Map<String, dynamic>> onLoadPatient;
  const DashboardScreen({
    super.key,
    required this.patients,
    required this.privacyMode,
    required this.onNewNote,
    required this.onLoadPatient,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _searchQuery = '';

  String _maskedName(String name) {
    if (name.isEmpty) return 'Hidden';
    if (name.length == 1) return '*';
    return '${name[0]}${'*' * (name.length - 1)}';
  }

  @override
  Widget build(BuildContext context) {
    final filteredPatients = widget.patients.where((p) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final name = (p['name'] ?? '').toLowerCase();
      final id = (p['patient_id'] ?? '').toLowerCase();
      final specialty = (p['specialty'] ?? '').toLowerCase();
      return name.contains(query) || id.contains(query) || specialty.contains(query);
    }).toList();

    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Patient Visits', style: Theme.of(context).textTheme.titleLarge),
              FilledButton.icon(
                onPressed: widget.onNewNote,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Register New Patient'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_todayDetailed(), style: GoogleFonts.inter(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by name, ID or specialty...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.filter_list),
              style: IconButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )
          ]),
          const SizedBox(height: 24),
          Expanded(
            child: filteredPatients.isEmpty
                ? const Center(child: Text('No active encounters found.'))
                : ListView.separated(
                    itemCount: filteredPatients.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final p = filteredPatients[i];
                      return _PatientCard(
                        id: p['patient_id'] ?? 'P-0000',
                        name: widget.privacyMode ? _maskedName((p['name'] ?? '').toString()) : p['name'],
                        meta: '${p["age"]}${p["sex"]} · ${p["visit_type"]} · ${p["specialty"]}',
                        complaint: p['chief_complaint'],
                        status: p['status'] ?? 'Draft',
                        onTap: () => widget.onLoadPatient(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _todayDetailed() {
    final now = DateTime.now();
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

class _PatientCard extends StatelessWidget {
  final String id, name, meta, complaint, status;
  final VoidCallback onTap;
  const _PatientCard({required this.id, required this.name, required this.meta, required this.complaint, required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    switch (status.toLowerCase()) {
      case 'completed': case 'saved': statusColor = const Color(0xFF10B981); break;
      case 'new': case 'recent': statusColor = const Color(0xFF3B82F6); break;
      case 'in review': statusColor = const Color(0xFFF59E0B); break;
      default: statusColor = Colors.grey;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(name[0], style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0D7E6A)))),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1F2937))),
                    const SizedBox(width: 8),
                    Text(id, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
                  ]),
                  const SizedBox(height: 2),
                  Text(meta, style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.medical_services_outlined, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(child: Text(complaint, style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusChip(label: status, color: statusColor),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Row(children: [
                    Text('Start Visit', style: TextStyle(fontSize: 12, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                    Icon(Icons.chevron_right, size: 16, color: Theme.of(context).primaryColor),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// PATIENT INTAKE FORM
// ──────────────────────────────────────────────────────────────────
class PatientIntakeScreen extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>> onSubmit;
  final VoidCallback onCancel;
  const PatientIntakeScreen({super.key, required this.onSubmit, required this.onCancel});

  @override
  State<PatientIntakeScreen> createState() => _PatientIntakeScreenState();
}

class _PatientIntakeScreenState extends State<PatientIntakeScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _sex = 'M';
  String _visitType = 'Initial Visit';
  final _specialtyCtrl = TextEditingController(text: 'General Medicine');
  final _complaintCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _specialtyCtrl.dispose();
    _complaintCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('New Patient Encounter', style: TextStyle(fontSize: 16)),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Patient Name',
                  hintText: 'e.g. Jane Doe',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
              )),
              const SizedBox(width: 16),
              Expanded(child: DropdownButtonFormField<String>(
                value: _sex,
                decoration: const InputDecoration(labelText: 'Sex', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Male')),
                  DropdownMenuItem(value: 'F', child: Text('Female')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _sex = v!),
              )),
            ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _visitType,
              decoration: const InputDecoration(labelText: 'Visit Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'Initial Visit', child: Text('Initial Visit')),
                DropdownMenuItem(value: 'Follow-up', child: Text('Follow-up')),
                DropdownMenuItem(value: 'Post-Op', child: Text('Post-Op')),
                DropdownMenuItem(value: 'Consultation', child: Text('Consultation')),
              ],
              onChanged: (v) => setState(() => _visitType = v!),
            ),
            const SizedBox(height: 16),
            TextField(controller: _specialtyCtrl, decoration: const InputDecoration(labelText: 'Specialty', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(
              controller: _complaintCtrl,
              maxLines: 4,
              scrollPadding: const EdgeInsets.all(100),
              decoration: const InputDecoration(
                labelText: 'Chief Complaint',
                hintText: 'Reason for visit...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: () {
                if (_nameCtrl.text.isEmpty || _complaintCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name and Chief Complaint are required')),
                  );
                  return;
                }
                widget.onSubmit({
                  'name': _nameCtrl.text,
                  'age': _ageCtrl.text,
                  'sex': _sex,
                  'visit_type': _visitType,
                  'specialty': _specialtyCtrl.text,
                  'chief_complaint': _complaintCtrl.text,
                });
              },
              icon: const Icon(Icons.mic),
              label: const Text('Start Live Dictation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ),
  );
}
}

// ──────────────────────────────────────────────────────────────────
// COMPOSER SCREEN
// ──────────────────────────────────────────────────────────────────
class ComposerScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final ValueChanged<Map<String, dynamic>> onSave;
  const ComposerScreen({super.key, required this.patient, required this.onSave});
  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  // Logical recording state
  bool _isRecording = false;
  int _recSeconds = 0;
  Timer? _recTimer;
  Timer? _nudgeTimer;

  // Transcript buffers
  String _committedTranscript = '';
  String _currentPartial = '';

  // Data state
  bool _isLoadingSoap = false;
  Map<String, dynamic>? _soapNote;
  Map<String, dynamic> _ehrData = {};
  bool _showEHR = false;
  bool _isFallback = false;
  List<String> _nudges = [];

  final _transcriptController = TextEditingController();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _speechRestartPending = false;

  @override
  void initState() {
    super.initState();
    _fetchEHR();
    _initSpeech();
  }

  // ── Infinite STT Watchdog ──────────────────────────────────────
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (err) {
        debugPrint('STT error: $err');
        // Retry only on native platforms, and only once per interruption.
        if (!kIsWeb && err.errorMsg == 'error_busy' && _isRecording) {
          _scheduleReboot(ms: 1000);
        }
      },
      onStatus: (status) {
        debugPrint('STT status: $status');
        // Web speech recognition should not be auto-restarted from status callbacks.
        if (!kIsWeb && (status == 'notListening' || status == 'done') && _isRecording && mounted) {
           _scheduleReboot();
        }
      },
    );
    if (mounted) setState(() {});
  }

  void _scheduleReboot({int ms = 400}) {
    if (_speechRestartPending) return;
    _speechRestartPending = true;
    Future.delayed(Duration(milliseconds: ms), () async {
      _speechRestartPending = false;
      if (_isRecording && mounted && !_speechToText.isListening) {
        try {
          // Explicitly cancel to clear any hardware busy states
          await _speechToText.cancel(); 
          await _speechToText.listen(
            onResult: _onSpeechResult,
            listenOptions: stt.SpeechListenOptions(
              listenMode: stt.ListenMode.dictation,
              partialResults: true,
              cancelOnError: false, // Prevents timeouts from killing logical session
            ),
          );
        } catch (e) {
          debugPrint('STT Reboot failed: $e');
        }
      }
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (mounted) {
      setState(() {
        _currentPartial = result.recognizedWords;
        _transcriptController.text = _committedTranscript + (_committedTranscript.isEmpty ? '' : ' ') + _currentPartial;
      });
      // Periodically commit the partial to the primary buffer
      if (result.finalResult) {
        _committedTranscript += (_committedTranscript.isEmpty ? '' : ' ') + _currentPartial;
        _currentPartial = '';
      }
    }
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _nudgeTimer?.cancel();
    _speechToText.stop();
    _transcriptController.dispose();
    super.dispose();
  }

  // ── EHR ────────────────────────────────────────────────────────
  void _fetchEHR() async {
    try {
      final patientId = widget.patient['patient_id'] as String?;
      if (patientId == null || patientId.isEmpty) {
        if (mounted) setState(() => _ehrData = {});
        return;
      }
      final data = await ApiService.fetchEhr(patientId);
      if (mounted) setState(() => _ehrData = data);
    } catch (e) {
      if (mounted) {
        setState(() => _ehrData = {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('EHR fetch failed: $e')),
        );
      }
    }
  }

  // ── Recording Control ──────────────────────────────────────────
  void _toggleRecord() async {
    if (_isRecording) {
      setState(() => _isRecording = false);
      _recTimer?.cancel();
      _nudgeTimer?.cancel();
      await _speechToText.stop();
      if (_currentPartial.isNotEmpty) {
        _committedTranscript += (_committedTranscript.isEmpty ? '' : ' ') + _currentPartial;
        _currentPartial = '';
      }
      setState(() => _transcriptController.text = _committedTranscript.trim());
      _fetchNudges();
    } else {
      if (!_speechEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied or Speech-to-Text unavailable.')),
          );
        }
        return;
      }
      _committedTranscript = _transcriptController.text.trim();
      _currentPartial = '';

      setState(() {
        _isRecording = true;
        _recSeconds = 0;
        _nudges = [];
      });

      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );

      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSeconds++);
      });
      _nudgeTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchNudges());
    }
  }

  // ── Nudges ─────────────────────────────────────────────────────
  void _fetchNudges() async {
    final text = _transcriptController.text.trim();
    if (text.isEmpty) return;
    final chief = widget.patient['chief_complaint']?.toString() ?? '';
    final qs = await ApiService.suggestQuestions(text, chief);
    if (qs.isNotEmpty && mounted) setState(() => _nudges = qs);
  }

  // ── SOAP Generation ────────────────────────────────────────────
  void _generateSOAP() async {
    final text = _transcriptController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a transcript first.')));
      return;
    }
    setState(() { _isLoadingSoap = true; _isFallback = false; });
    try {
      final result = await ApiService.generateSoap(text, widget.patient);
      if (mounted) {
        setState(() {
          _isLoadingSoap = false;
          _soapNote = result;
          _isFallback = result['is_fallback'] == true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSoap = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SOAP generation failed: $e')),
        );
      }
    }
  }

  // ── Patient Summary → PDF → Share ─────────────────────────────
  void _exportSummary() async {
    if (_soapNote == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generate a SOAP note first.')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.all(16),
          child: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Building Patient Letter PDF…')]),
        ),
      ),
    );

    Map<String, dynamic> sum;
    try {
      sum = await ApiService.getPatientSummary(_soapNote!);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Patient summary failed: $e')),
        );
      }
      return;
    }

    final summaryText = sum['summary'] as String? ?? 'No summary available.';
    final patientName = widget.patient['name'] as String;
    final visitType = widget.patient['visit_type'] as String;
    final chiefComplaint = widget.patient['chief_complaint'] as String;
    final dateStr = _todayFormatted();

    if (!mounted) return;
    Navigator.pop(context);

    // Build the PDF
    final pdf = pw.Document();
    final headerColor = PdfColor.fromHex('#0D7E6A');
    final lightGrey = PdfColor.fromHex('#F4F6F9');
    final darkText = PdfColor.fromHex('#1A1A2E');
    String pdfSafe(String value) => value
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('•', '-')
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'");

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 48),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: headerColor, width: 2))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Carelytic Reports', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: headerColor)),
                  pw.Text('Patient Letter', style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                ],
              ),
              pw.Text(dateStr, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Confidential — for patient use only', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
            ],
          ),
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: lightGrey, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Patient', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(pdfSafe(patientName), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: darkText)),
                ])),
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Visit Type', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(pdfSafe(visitType), style: pw.TextStyle(fontSize: 12, color: darkText)),
                ])),
                pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Chief Complaint', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(pdfSafe(chiefComplaint), style: pw.TextStyle(fontSize: 12, color: darkText)),
                ])),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          ...summaryText.split('\n').map((line) {
            final safeLine = pdfSafe(line);
            final isSectionHeader = safeLine.startsWith('What We Found') || safeLine.startsWith('Your Next Steps');
            if (isSectionHeader) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 14),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: pw.BoxDecoration(color: headerColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                    child: pw.Text(safeLine.replaceAll(':', ''), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  ),
                  pw.SizedBox(height: 6),
                ],
              );
            } else if (safeLine.trim().startsWith('-')) {
              return pw.Padding(padding: const pw.EdgeInsets.only(left: 18, bottom: 4), child: pw.Text(safeLine.trim(), style: pw.TextStyle(fontSize: 11, lineSpacing: 2)));
            } else if (safeLine.trim().isEmpty) {
              return pw.SizedBox(height: 4);
            } else {
              return pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text(safeLine, style: pw.TextStyle(fontSize: 11, lineSpacing: 2)));
            }
          // ignore: unnecessary_to_list_in_spreads
          }).toList(),
          pw.SizedBox(height: 32),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF3E0'), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.Text(
              pdfSafe('This letter was generated with AI assistance and reviewed by your physician. Always follow your doctor\'s specific instructions.'),
              style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('#E65100')),
            ),
          ),
        ],
      ),
    );

    final safeName = patientName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final pdfData = await pdf.save();

    if (kIsWeb) {
      await Printing.sharePdf(bytes: pdfData, filename: 'carelytic_report_$safeName.pdf');
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/carelytic_report_$safeName.pdf');
      await file.writeAsBytes(pdfData);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Carelytic Report - $patientName',
        text: 'Please find your patient report attached, powered by Carelytic-Reports Redefined.',
      );
    }
  }

  String _todayFormatted() {
    final now = DateTime.now();
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Column(children: [
      if (_isFallback)
        MaterialBanner(
          backgroundColor: Colors.orange[50],
          content: const Text(
            '⚠️  AI API unavailable — showing demo data. Results are not real.',
            style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
          ),
          actions: [TextButton(onPressed: () => setState(() => _isFallback = false), child: const Text('Dismiss'))],
        ),
      Expanded(
        child: isMobile
            ? Column(children: [
                _buildPatientPanel(isMobile: true),
                const Divider(height: 1),
                Expanded(child: _buildMainPanel(isMobile: true)),
              ])
            : Row(children: [
                _buildPatientPanel(isMobile: false),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: _buildMainPanel(isMobile: false)),
              ]),
      ),
    ]);
  }

  Widget _buildPatientPanel({required bool isMobile}) {
    return Container(
      width: isMobile ? double.infinity : 260,
      height: isMobile ? 200 : double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.patient['name'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(
          '${widget.patient["age"]}${widget.patient["sex"]} · ${widget.patient["visit_type"]} · ${widget.patient["specialty"]}',
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_showEHR ? 'EHR Records' : 'Active Context',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            Switch.adaptive(value: _showEHR, onChanged: (v) => setState(() => _showEHR = v)),
          ],
        ),
        Expanded(
          child: ListView(
            physics: const ClampingScrollPhysics(),
            children: _showEHR ? _buildEHRRows() : _buildContextRows(),
          ),
        ),
      ]),
    );
  }

  List<Widget> _buildContextRows() => [
    _infoRow('Chief Complaint', widget.patient['chief_complaint'] as String),
    if (_ehrData['active_problems'] != null)
      _infoRow('Active Problems', (_ehrData['active_problems'] as List).join('\n')),
    if (_ehrData['medications'] != null)
      _infoRow('Medications', (_ehrData['medications'] as List).join('\n')),
    if (_ehrData['allergies'] != null)
      _infoRow('Allergies', (_ehrData['allergies'] as List).join(', ')),
  ];

  List<Widget> _buildEHRRows() {
    if (_ehrData['recent_records'] == null) return [const Text('No EHR records loaded.')];
    return (_ehrData['recent_records'] as List).map<Widget>((e) {
      final eMap = e as Map;
      return _infoRow('${eMap["type"]} (${eMap["date"]})', eMap['finding'] as String);
    }).toList();
  }

  Widget _buildMainPanel({required bool isMobile}) {
    return Column(children: [
      if (_nudges.isNotEmpty)
        Container(
          width: double.infinity,
          color: Colors.indigo[50],
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💡 Suggested Follow-ups:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _nudges.map((q) => _NudgeBubble(text: q)).toList(),
            ),
          ]),
        ),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _toggleRecord,
                icon: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded, size: 18),
                label: Text(_isRecording ? 'Stop' : 'Record'),
                style: FilledButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.teal[700],
                ),
              ),
              if (_isRecording)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulsingDot(),
                    const SizedBox(width: 6),
                    Text(
                      '${_recSeconds ~/ 60}:${(_recSeconds % 60).toString().padLeft(2, "0")}',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              FilledButton.tonal(
                onPressed: _isRecording ? null : _generateSOAP,
                child: const Text('Generate SOAP'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _transcriptController,
            maxLines: isMobile ? 4 : 5,
            decoration: InputDecoration(
              hintText: 'Transcript will appear here. You can edit it manually...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.all(10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: Container(
          color: const Color(0xFFF4F6F9),
          padding: const EdgeInsets.all(14),
          child: _isLoadingSoap
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Generating SOAP note…', style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : _soapNote == null
                  ? const Center(
                      child: Text(
                        'Record your consultation, then tap Generate SOAP.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView(children: [
                      _SoapBox(title: 'Subjective', content: _soapNote!['subjective'], flags: _soapNote!['confidence_flags']),
                      _SoapBox(title: 'Objective', content: _soapNote!['objective'], flags: _soapNote!['confidence_flags']),
                      _SoapBox(title: 'Assessment', content: _soapNote!['assessment'], flags: _soapNote!['confidence_flags']),
                      _SoapBox(title: 'Plan', content: _soapNote!['plan'], flags: _soapNote!['confidence_flags']),
                    ]),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: Colors.white,
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: _exportSummary,
            icon: const Icon(Icons.share_outlined, size: 16),
            label: const Text('Patient Letter'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _soapNote == null ? null : () => widget.onSave(_soapNote!),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Sign & Save'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D7E6A)),
          ),
        ]),
      ),
    ]);
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// SOAP BOX WIDGET
// ──────────────────────────────────────────────────────────────────
class _SoapBox extends StatelessWidget {
  final String title;
  final dynamic content;
  final dynamic flags;
  const _SoapBox({required this.title, required this.content, required this.flags});

  @override
  Widget build(BuildContext context) {
    final flagged = flags != null && (flags as List).contains(title.toLowerCase());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: flagged ? Colors.orange : Colors.grey[300]!, width: flagged ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: flagged ? Colors.orange[50] : Colors.grey[100],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
          ),
          child: Row(children: [
            Text(title.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8)),
            const Spacer(),
            if (flagged) _chip('⚠ Review', Colors.orange[200]!, Colors.deepOrange),
            const SizedBox(width: 4),
            _chip('AI', Colors.blue[100]!, Colors.blue),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            content?.toString().isNotEmpty == true ? content.toString() : 'Not documented.',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// NUDGE BUBBLE WIDGET
// ──────────────────────────────────────────────────────────────────
class _NudgeBubble extends StatelessWidget {
  final String text;
  const _NudgeBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo[200]!),
        boxShadow: [BoxShadow(color: Colors.indigo.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.indigo[400]),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.indigo[900]))),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// PULSING DOT ANIMATION
// ──────────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
    );
  }
}

String _formatClinicalValue(dynamic value) {
  if (value == null) return '';
  if (value is List) return value.map((e) => e.toString()).join(', ');
  return value.toString();
}

// ──────────────────────────────────────────────────────────────────
// HISTORY SCREEN
// ──────────────────────────────────────────────────────────────────
class HistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> patients;
  const HistoryScreen({super.key, required this.patients});

  @override
  Widget build(BuildContext context) {
    final history = patients.where((p) => p['last_note'] != null).toList();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reports History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: history.isEmpty
              ? const Center(child: Text('No saved reports yet.'))
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (ctx, i) {
                    final p = history[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined, color: Color(0xFF0D7E6A)),
                        title: Text(p['name']),
                        subtitle: Text('Saved on ${_todayFormatted()}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Show report summary modal or navigate
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => DraggableScrollableSheet(
                              initialChildSize: 0.9,
                              builder: (_, scroll) => Container(
                                padding: const EdgeInsets.all(20),
                                child: ListView(controller: scroll, children: [
                                  Text('Report for ${p["name"]}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const Divider(),
                                  _buildSection('Subjective', p['last_note']['subjective']),
                                  _buildSection('Objective', p['last_note']['objective']),
                                  _buildSection('Assessment', p['last_note']['assessment']),
                                  _buildSection('Plan', p['last_note']['plan']),
                                  if (p['last_note']['differential_diagnoses'] != null)
                                    _buildSection('Differential Diagnoses', _formatClinicalValue(p['last_note']['differential_diagnoses'])),
                                  if (p['last_note']['risk_assessment'] != null)
                                    _buildSection('Risk Assessment', _formatClinicalValue(p['last_note']['risk_assessment'])),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  String _todayFormatted() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  Widget _buildSection(String title, String? content) {
    if (content == null || content.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(content, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// SETTINGS SCREEN
// ──────────────────────────────────────────────────────────────────
class SettingsScreen extends StatelessWidget {
  final VoidCallback onSettingsChanged;
  const SettingsScreen({super.key, required this.onSettingsChanged});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        _settingTile(context, Icons.api, 'API Configuration', 'Manage OpenAI and Bedrock keys', () {
          _showApiDialog(context);
        }),
        _settingTile(context, Icons.person_outline, 'Doctor Profile', 'Edit personal and practice info', () {
          _showProfileDialog(context);
        }),
        _settingTile(context, Icons.description_outlined, 'Templates', 'Customise SOAP and Letter formats', () {}),
        _settingTile(context, Icons.security, 'Security', 'PIN and biometric lock', () {}),
        const Divider(),
        _settingTile(context, Icons.info_outline, 'About Carelytic', 'Version 1.0.0 — Redefined', () {}),
      ],
    );
  }

  Widget _settingTile(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF0D7E6A)),
      title: Text(title),
      subtitle: Text(sub, style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }

  void _showProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: AppSettings.doctorName);
    final specCtrl = TextEditingController(text: AppSettings.specialty);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Doctor Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: specCtrl, decoration: const InputDecoration(labelText: 'Specialty', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await AppSettings.setDoctorName(nameCtrl.text);
              await AppSettings.setSpecialty(specCtrl.text);
              onSettingsChanged();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showApiDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Backend API URL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text(ApiService.baseUrl, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            const Text('Note: API keys are configured in the backend .env file for security.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
