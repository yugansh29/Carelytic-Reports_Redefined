import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'api.dart';

void main() {
  runApp(const ClinicNoteApp());
}

class ClinicNoteApp extends StatelessWidget {
  const ClinicNoteApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clinic Note Generator',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      ),
      home: const HomeLayout(),
    );
  }
}

class HomeLayout extends StatefulWidget {
  const HomeLayout({Key? key}) : super(key: key);
  @override
  State<HomeLayout> createState() => _HomeLayoutState();
}

class _HomeLayoutState extends State<HomeLayout> {
  int _currentIndex = 0;
  final List<String> _tabs = ["Visits", "Compose", "History", "Settings"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("NoteAI", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          Row(
            children: _tabs.asMap().entries.map((e) {
              int idx = e.key;
              bool isActive = _currentIndex == idx;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TextButton(
                  onPressed: () => setState(() => _currentIndex = idx),
                  style: TextButton.styleFrom(
                    backgroundColor: isActive ? Colors.grey[200] : Colors.transparent,
                    foregroundColor: isActive ? Colors.black : Colors.grey[600]
                  ),
                  child: Text(e.value),
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 20),
          const CircleAvatar(radius: 14, backgroundColor: Color(0xFFE6F1FB), child: Text("DR", style: TextStyle(fontSize: 10, color: Color(0xFF185FA5)))),
          const SizedBox(width: 8),
          const Text("Dr. Ravi", style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(width: 16),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0: return DashboardScreen(onNavigateCompose: () => setState(() => _currentIndex = 1));
      case 1: return const ComposerScreen();
      default: return const Center(child: Text("Under construction for MVP"));
    }
  }
}

class DashboardScreen extends StatelessWidget {
  final VoidCallback onNavigateCompose;
  const DashboardScreen({Key? key, required this.onNavigateCompose}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: TextField(decoration: InputDecoration(hintText: "Search patients...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12)),)),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: onNavigateCompose,
                icon: const Icon(Icons.add, size: 16),
                label: const Text("New Note"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE1F5EE), foregroundColor: const Color(0xFF085041), elevation: 0)
              )
            ],
          ),
          const SizedBox(height: 16),
          const Text("Today — Apr 16", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          _buildCard("Raj Sharma", "42M · Follow-up · Lower back pain", "In review", Colors.purple[100]!, Colors.purple[900]!),
        ],
      ),
    );
  }

  Widget _buildCard(String name, String meta, String status, Color tagBg, Color tagFg) {
    return InkWell(
      onTap: onNavigateCompose,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            CircleAvatar(radius: 18, backgroundColor: Colors.blue[50], child: Text(name[0], style: const TextStyle(color: Colors.blue))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(meta, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(12)), child: Text(status, style: TextStyle(color: tagFg, fontSize: 11)))
          ],
        ),
      ),
    );
  }
}

class ComposerScreen extends StatefulWidget {
  const ComposerScreen({Key? key}) : super(key: key);
  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  // State
  bool isRecording = false;
  int recSeconds = 0;
  Timer? timer;
  String transcript = "";
  bool isLoadingSoap = false;
  Map<String, dynamic>? soapNote;
  Map<String, dynamic> ehrData = {};
  bool showEHR = false;
  bool isFallback = false;
  List<String> nudges = [];
  Timer? nudgeTimer;

  final AudioRecorder _audioRecorder = AudioRecorder();

  // Mock patient context
  final Map<String, dynamic> patientContext = {
    "name": "Raj Sharma",
    "age": 42,
    "sex": "M",
    "visit_type": "Follow-up",
    "specialty": "General medicine",
    "chief_complaint": "Lower back pain"
  };

  @override
  void initState() {
    super.initState();
    _fetchEHR();
  }

  void _fetchEHR() async {
    final data = await ApiService.fetchEhr("p123");
    if (mounted) {
      setState(() { ehrData = data; });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    nudgeTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void toggleRecord() async {
    if (isRecording) {
      // STOP recording
      setState(() => isRecording = false);
      timer?.cancel();
      nudgeTimer?.cancel();
      final path = await _audioRecorder.stop();
      if (path != null) {
        _processAudio(path);
      }
    } else {
      // START recording
      if (await _audioRecorder.hasPermission()) {
        String path = '';
        if (!kIsWeb) {
          final dir = await getTemporaryDirectory();
          path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';
        }
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: path);
        setState(() => isRecording = true);
        recSeconds = 0;
        timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => recSeconds++));
        nudgeTimer = Timer.periodic(const Duration(seconds: 10), (t) => _fetchNudge());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Microphone permission denied")));
      }
    }
  }

  void _fetchNudge() async {
     if (transcript.isEmpty) return;
     final qs = await ApiService.suggestQuestions(transcript, patientContext["chief_complaint"]);
     if (qs.isNotEmpty && mounted) {
       setState(() { nudges = qs; });
     }
  }

  void _processAudio(String path) async {
    setState(() { transcript = "Processing audio..."; });
    try {
      Uint8List bytes;
      if (kIsWeb) {
        final byteData = await http.get(Uri.parse(path));
        bytes = byteData.bodyBytes;
      } else {
        bytes = await File(path).readAsBytes();
      }
      final res = await ApiService.transcribeAudio(bytes);
      if (mounted) {
        setState(() {
          transcript = res["transcript"] ?? "Failed to parse.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
           transcript = "Patient: My back has been hurting for 3 weeks... (Offline Mock due to error)";
        });
      }
    }
  }

  void _generateSOAP() async {
    if (transcript.isEmpty || transcript == "Processing audio...") return;
    setState(() { isLoadingSoap = true; isFallback = false; });
    final result = await ApiService.generateSoap(transcript, patientContext);
    setState(() {
      isLoadingSoap = false;
      soapNote = result;
      isFallback = result["is_fallback"] == true;
    });
  }

  void _exportSummary() async {
    if (soapNote == null) return;
    showDialog(context: context, builder: (_) => const AlertDialog(content: Text("Generating summary...")));
    final sum = await ApiService.getPatientSummary(soapNote!);
    Navigator.pop(context); 
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Patient Summary", style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(child: Text(sum["summary"] ?? "Error")),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("Close"))]
    ));
  }

  Widget _buildLeftPanelContent() {
    return ListView(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      children: [
        if (!showEHR) ...[
          _infoRow("Chief Complaint", patientContext['chief_complaint']),
          if (ehrData['active_problems'] != null)
            _infoRow("Active Problems", (ehrData['active_problems'] as List).join("\n")),
          if (ehrData['medications'] != null)
             _infoRow("Medications", (ehrData['medications'] as List).join("\n")),
        ] else ...[
          const Text("EHR Data", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (ehrData['recent_records'] != null)
            ...(ehrData['recent_records'] as List).map((e) => _infoRow(e['type'] + " (${e['date']})", e['finding'])).toList()
        ]
      ],
    );
  }

  Widget _buildLeftPanel(bool isMobile) {
    return Container(
      width: isMobile ? double.infinity : 260,
      height: isMobile ? 220 : double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(patientContext['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text("${patientContext['age']}${patientContext['sex']} · ${patientContext['visit_type']} · ${patientContext['specialty']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Context", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              Switch(value: showEHR, onChanged: (v)=>setState(()=>showEHR=v)),
            ],
          ),
          Expanded(child: _buildLeftPanelContent()),
        ],
      ),
    );
  }

  Widget _buildMainPanel(bool isMobile) {
    return Column(
      children: [
        // Transcript & Recording area
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nudges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("AI Suggested Questions:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: nudges.map((n) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.indigo[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.indigo[200]!)
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 14, color: Colors.indigo[400]),
                              const SizedBox(width: 6),
                              Flexible(child: Text(n, style: TextStyle(fontSize: 13, color: Colors.indigo[900]))),
                            ],
                          ),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: toggleRecord,
                    icon: Icon(isRecording ? Icons.stop : Icons.mic, size: 16, color: isRecording ? Colors.red : Colors.black87),
                    label: Text(isRecording ? "Stop" : "Record"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecording ? Colors.red[50] : Colors.grey[200],
                      foregroundColor: isRecording ? Colors.red : Colors.black87,
                      elevation: 0,
                    ),
                  ),
                  if (isRecording) ...[
                    const SizedBox(width: 12),
                    Text("${recSeconds ~/ 60}:${(recSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _generateSOAP, 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[600],
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text("Generate Note")
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
                height: isMobile ? 100 : 120,
                child: SingleChildScrollView(child: Text(transcript.isEmpty ? "No transcript yet..." : transcript, style: const TextStyle(color: Colors.black87))),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // SOAP Area
        Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: isLoadingSoap
                ? const Center(child: CircularProgressIndicator())
                : soapNote == null
                    ? const Center(child: Text("Generate to see SOAP note"))
                    : ListView(
                        children: [
                          _soapBox("Subjective", soapNote!["subjective"], soapNote!["confidence_flags"]),
                          _soapBox("Objective", soapNote!["objective"], soapNote!["confidence_flags"]),
                          _soapBox("Assessment", soapNote!["assessment"], soapNote!["confidence_flags"]),
                          _soapBox("Plan", soapNote!["plan"], soapNote!["confidence_flags"]),
                        ],
                      ),
          ),
        ),
        // Footer
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _exportSummary, 
                icon: const Icon(Icons.share, size: 16),
                label: Text(isMobile ? "Export" : "Patient Summary")
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE1F5EE), foregroundColor: const Color(0xFF085041), elevation: 0),
                child: const Text("Sign Note"),
              )
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 700;

    return Column(
      children: [
        if (isFallback)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.orange[100],
            child: const Text("API Error: Displaying Offline Dummy Note.", textAlign: TextAlign.center, style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        Expanded(
          child: isMobile 
            ? Column(
                children: [
                  _buildLeftPanel(true),
                  const Divider(height: 1),
                  Expanded(child: _buildMainPanel(true)),
                ],
              )
            : Row(
                children: [
                  _buildLeftPanel(false),
                  const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE5E7EB)),
                  Expanded(child: _buildMainPanel(false)),
                ],
              ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _soapBox(String title, String? content, dynamic flags) {
    bool isFlagged = flags != null && (flags as List).contains(title.toLowerCase());
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isFlagged ? Colors.orange : Colors.grey[300]!, width: isFlagged ? 2 : 1)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: isFlagged ? Colors.orange[50] : Colors.grey[100], borderRadius: const BorderRadius.vertical(top: Radius.circular(7))),
            child: Row(
              children: [
                Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const Spacer(),
                if (isFlagged) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange[200], borderRadius: BorderRadius.circular(12)), child: const Text("Review", style: TextStyle(fontSize: 10, color: Colors.deepOrange))),
                const SizedBox(width: 4),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(12)), child: const Text("AI", style: TextStyle(fontSize: 10, color: Colors.blue))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(content ?? "Not documented."),
          )
        ],
      ),
    );
  }
}
