import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonMap = Map<String, dynamic>;

void main() => runApp(HabitTrackerApp());

class HabitTrackerApp extends StatefulWidget {
  @override
  _HabitTrackerAppState createState() => _HabitTrackerAppState();
}

class _HabitTrackerAppState extends State<HabitTrackerApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('darkMode') ?? false;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _updateTheme(bool isDark) async {
    setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Tracker',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.grey[900],
        primaryColor: Colors.grey[800],
        cardColor: Colors.grey[800],
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white),
        ),
      ),
      themeMode: _themeMode,
      home: HomePage(),
      routes: {
        '/settings': (_) => SettingsPage(onThemeChanged: _updateTheme),
        '/overview': (_) => OverviewPage(),
      },
    );
  }
}

// === CONFIG ===
class AppConfig {
  TimeOfDay newDayTime;
  double startPosMultiplier,
      stepUp,
      lengthPosStreak,
      maxPosMultiplier;
  double startNegMultiplier,
      stepDown,
      lengthNegStreak,
      maxNegMultiplier;

  AppConfig({
    required this.newDayTime,
    required this.startPosMultiplier,
    required this.stepUp,
    required this.lengthPosStreak,
    required this.maxPosMultiplier,
    required this.startNegMultiplier,
    required this.stepDown,
    required this.lengthNegStreak,
    required this.maxNegMultiplier,
  });

  factory AppConfig.defaultConfig() => AppConfig(
        newDayTime: TimeOfDay(hour: 0, minute: 0),
        startPosMultiplier: 1.0,
        stepUp: 1.0,
        lengthPosStreak: 7.0,
        maxPosMultiplier: 5.0,
        startNegMultiplier: 1.0,
        stepDown: 1.0,
        lengthNegStreak: 1.0,
        maxNegMultiplier: 5.0,
      );

  factory AppConfig.fromJson(JsonMap j) => AppConfig(
        newDayTime:
            TimeOfDay(hour: j['newDayHour'], minute: j['newDayMinute']),
        startPosMultiplier: (j['startPosMultiplier'] as num).toDouble(),
        stepUp: (j['stepUp'] as num).toDouble(),
        lengthPosStreak: (j['lengthPosStreak'] as num).toDouble(),
        maxPosMultiplier: (j['maxPosMultiplier'] as num).toDouble(),
        startNegMultiplier: (j['startNegMultiplier'] as num).toDouble(),
        stepDown: (j['stepDown'] as num).toDouble(),
        lengthNegStreak: (j['lengthNegStreak'] as num).toDouble(),
        maxNegMultiplier: (j['maxNegMultiplier'] as num).toDouble(),
      );

  JsonMap toJson() => {
        'newDayHour': newDayTime.hour,
        'newDayMinute': newDayTime.minute,
        'startPosMultiplier': startPosMultiplier,
        'stepUp': stepUp,
        'lengthPosStreak': lengthPosStreak,
        'maxPosMultiplier': maxPosMultiplier,
        'startNegMultiplier': startNegMultiplier,
        'stepDown': stepDown,
        'lengthNegStreak': lengthNegStreak,
        'maxNegMultiplier': maxNegMultiplier,
      };
}

// === HABIT MODEL ===
class Habit {
  String title;
  int daysPosStreak = 0;
  int daysNegStreak = 0;
  double points = 0;
  bool answeredToday = false;
  bool wasPositive = false;
  double lastDelta = 0;

  // backups for uncommitted answers
  int _backupPosStreak = 0;
  int _backupNegStreak = 0;
  double _backupPoints = 0;

  Habit({required this.title});

  factory Habit.fromJson(JsonMap j) {
    final h = Habit(title: j['title']);
    h.daysPosStreak = j['daysPosStreak'];
    h.daysNegStreak = j['daysNegStreak'];
    h.points = (j['points'] as num).toDouble();
    h.answeredToday = j['answeredToday'] as bool? ?? false;
    h.wasPositive = j['wasPositive'] as bool? ?? false;
    h.lastDelta = (j['lastDelta'] as num?)?.toDouble() ?? 0.0;
    if (h.answeredToday) {
      h._backupPosStreak = h.daysPosStreak - (h.wasPositive ? 1 : 0);
      h._backupNegStreak = h.daysNegStreak - (h.wasPositive ? 0 : 1);
      h._backupPoints = h.points - h.lastDelta;
    }
    return h;
  }

  JsonMap toJson() => {
        'title': title,
        'daysPosStreak': daysPosStreak,
        'daysNegStreak': daysNegStreak,
        'points': points,
        'answeredToday': answeredToday,
        'wasPositive': wasPositive,
        'lastDelta': lastDelta,
      };

  double getPosMultiplier(AppConfig cfg) {
    if (daysPosStreak <= 0) return cfg.startPosMultiplier;
    final periods = ((daysPosStreak - 1) / cfg.lengthPosStreak).floor();
    return min(cfg.startPosMultiplier + periods * cfg.stepUp,
        cfg.maxPosMultiplier);
  }

  double getNegMultiplier(AppConfig cfg) {
    if (daysNegStreak <= 0) return cfg.startNegMultiplier;
    final periods = ((daysNegStreak - 1) / cfg.lengthNegStreak).floor();
    return min(cfg.startNegMultiplier + periods * cfg.stepDown,
        cfg.maxNegMultiplier);
  }

  void answer(bool positive, AppConfig cfg) {
    if (!answeredToday) {
      _backupPosStreak = daysPosStreak;
      _backupNegStreak = daysNegStreak;
      _backupPoints = points;
    }
    if (answeredToday) clearAnswer();
    if (positive) {
      daysPosStreak++;
      daysNegStreak = 0;
      lastDelta = cfg.stepUp * getPosMultiplier(cfg);
      points += lastDelta;
      wasPositive = true;
    } else {
      daysNegStreak++;
      daysPosStreak = 0;
      lastDelta = -cfg.stepDown * getNegMultiplier(cfg);
      points += lastDelta;
      wasPositive = false;
    }
    answeredToday = true;
  }

  void clearAnswer() {
    if (!answeredToday) return;
    daysPosStreak = _backupPosStreak;
    daysNegStreak = _backupNegStreak;
    points = _backupPoints;
    lastDelta = 0;
    answeredToday = false;
  }

  void resetDaily() {
    answeredToday = false;
    lastDelta = 0;
  }
}

// === DAILY RECORD ===
class DailyRecord {
  final int day;
  final Map<String, double> habitDeltas;
  DailyRecord(this.day, this.habitDeltas);

  factory DailyRecord.fromJson(JsonMap j) => DailyRecord(
        j['day'],
        Map<String, double>.from(j['deltas']),
      );

  JsonMap toJson() => {
        'day': day,
        'deltas': habitDeltas,
      };
}

// === HOME PAGE ===
class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppConfig cfg = AppConfig.defaultConfig();
  List<Habit> habits = [];
  List<DailyRecord> history = [];
  double totalPoints = 0, dailyDelta = 0;
  int currentDay = 1;
  bool dayOver = false, isEditing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(Duration(minutes: 1), (_) => _checkRollover());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _checkRollover() {
    final now = TimeOfDay.fromDateTime(DateTime.now());
    if (!dayOver &&
        now.hour == cfg.newDayTime.hour &&
        now.minute == cfg.newDayTime.minute) {
      setState(() => dayOver = true);
      _saveData();
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      cfg = prefs.getString('config') != null
          ? AppConfig.fromJson(json.decode(prefs.getString('config')!))
          : AppConfig.defaultConfig();
      habits = prefs.getString('habits') != null
          ? (json.decode(prefs.getString('habits')!) as List)
              .map((j) => Habit.fromJson(j))
              .toList()
          : [
              Habit(title: 'Smoking'),
              Habit(title: 'Sugar'),
              Habit(title: 'Social Media')
            ];
      history = prefs.getString('history') != null
          ? (json.decode(prefs.getString('history')!) as List)
              .map((j) => DailyRecord.fromJson(j))
              .toList()
          : [];
      totalPoints = prefs.getDouble('totalPoints') ?? 0;
      currentDay = prefs.getInt('currentDay') ?? 1;
      dayOver = prefs.getBool('dayOver') ?? false;
      dailyDelta = habits.fold(0.0, (sum, h) => sum + h.lastDelta);
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('config', json.encode(cfg.toJson()));
    await prefs.setString(
        'habits', json.encode(habits.map((h) => h.toJson()).toList()));
    await prefs.setString(
        'history', json.encode(history.map((d) => d.toJson()).toList()));
    await prefs.setDouble('totalPoints', totalPoints);
    await prefs.setInt('currentDay', currentDay);
    await prefs.setBool('dayOver', dayOver);
  }

  bool get allAnswered => habits.every((h) => h.answeredToday);

  void _onAnswer(int i, bool pos) {
    if (isEditing) return;
    setState(() {
      final h = habits[i];
      if (h.answeredToday) {
        if (h.wasPositive == pos) {
          // Toggle off the current choice.
          dailyDelta -= h.lastDelta;
          h.clearAnswer();
        } else {
          // Switching answer, subtract previous delta then apply new answer.
          dailyDelta -= h.lastDelta;
          h.answer(pos, cfg);
          dailyDelta += h.lastDelta;
        }
      } else {
        h.answer(pos, cfg);
        dailyDelta += h.lastDelta;
      }
    });
    _saveData();
  }

  void _attemptNextDay() {
    if (!allAnswered) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Incomplete'),
          content: Text('Please answer all habits before continuing.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'))
          ],
        ),
      );
      return;
    }
    setState(() {
      history.add(DailyRecord(currentDay,
          {for (var h in habits) h.title: h.lastDelta}));
      totalPoints = max(0, totalPoints + dailyDelta);
      dailyDelta = 0;
      currentDay++;
      dayOver = false;
      habits.forEach((h) => h.resetDaily());
    });
    _saveData();
  }

  void _toggleEdit() => setState(() => isEditing = !isEditing);

  Future<void> _addHabit() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('New Habit'),
        content: TextField(controller: ctrl, decoration: InputDecoration(hintText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(onPressed: () {
            final name = ctrl.text.trim();
            if (name.isNotEmpty) {
              setState(() => habits.add(Habit(title: name)));
              _saveData();
            }
            Navigator.pop(context);
          }, child: Text('Add')),
        ],
      ),
    );
  }

  Future<void> _renameHabit(int i) async {
    final h = habits[i], ctrl = TextEditingController(text: h.title);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Rename "${h.title}"'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(onPressed: () {
            final newName = ctrl.text.trim();
            if (newName.isNotEmpty) {
              setState(() => h.title = newName);
              _saveData();
            }
            Navigator.pop(context);
          }, child: Text('Save')),
        ],
      ),
    );
  }

  Future<void> _deleteHabit(int i) async {
    final h = habits[i];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${h.title}"?'),
        content: Text('This will remove its history too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        habits.removeAt(i);
        history.forEach((rec) => rec.habitDeltas.remove(h.title));
      });
      _saveData();
    }
  }

  void _reorderHabits(int oldI, int newI) {
    setState(() {
      if (newI > oldI) newI--;
      final item = habits.removeAt(oldI);
      habits.insert(newI, item);
      _saveData();
    });
  }

  void _goToSettings() async {
    await Navigator.pushNamed(context, '/settings');
    _loadData();
  }

  Map<String, double> _streakStats(String title) {
    int longest = 0, curr = 0;
    final runs = <int>[];
    for (var r in history) {
      if ((r.habitDeltas[title] ?? 0) > 0) curr++;
      else {
        if (curr > 0) runs.add(curr);
        longest = max(longest, curr);
        curr = 0;
      }
    }
    if (curr > 0) runs..add(curr)..sort();
    final double avg = runs.isEmpty ? 0.0 : runs.reduce((a, b) => a + b).toDouble() / runs.length;
    return {'longest': longest.toDouble(), 'avg': avg};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Day $currentDay - Habits'),
        actions: [
          IconButton(icon: Icon(isEditing ? Icons.check : Icons.edit), onPressed: _toggleEdit),
          if (!isEditing) IconButton(icon: Icon(Icons.table_chart), onPressed: () => Navigator.pushNamed(context, '/overview')),
          if (!isEditing) IconButton(icon: Icon(Icons.settings), onPressed: _goToSettings),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Total: ${totalPoints.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (dailyDelta != 0) ...[
              SizedBox(width: 8),
              Text(
                (dailyDelta > 0 ? '+' : '-') + '${dailyDelta.abs().toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: dailyDelta > 0 ? Colors.green : Colors.red),
              )
            ]
          ]),
        ),
        Expanded(
          child: isEditing
              ? ReorderableListView(
                  buildDefaultDragHandles: false,
                  onReorder: _reorderHabits,
                  children: [
                    for (int i = 0; i < habits.length; i++)
                      ListTile(
                        key: ValueKey(habits[i]),
                        // <-- custom drag handle on the very left
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                        title: Text(habits[i].title),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit),
                              onPressed: () => _renameHabit(i),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteHabit(i),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              : ListView.builder(
                  itemCount: habits.length,
                  itemBuilder: (ctx, i) {
                    final h = habits[i], s = _streakStats(h.title);
                    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
                    final Color? cardColor = h.answeredToday
                        ? (h.wasPositive
                            ? (isDarkMode ? Colors.green[700] : Colors.green[100])
                            : (isDarkMode ? Colors.red[700] : Colors.red[100]))
                        : null;
                    final Color textColor = isDarkMode ? Colors.white : Colors.black;

                    return Card(
                      color: cardColor,
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: ListTile(
                        textColor: textColor,
                        iconColor: textColor,
                        title: Text(h.title, style: TextStyle(fontSize: 20)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                              'Streak: ' +
                                  (h.daysPosStreak > 0
                                      ? '+${h.daysPosStreak}'
                                      : (h.daysNegStreak > 0 ? '-${h.daysNegStreak}' : '0')) +
                                  ' days'),
                          Text('Longest: ${s['longest']!.toInt()} days'),
                          Text('Avg: ${s['avg']!.toStringAsFixed(2)} days'),
                        ]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: Icon(Icons.check, color: textColor), onPressed: () => _onAnswer(i, true)),
                          IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => _onAnswer(i, false)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: isEditing
          ? FloatingActionButton(onPressed: _addHabit, child: Icon(Icons.add))
          : (dayOver
              ? FloatingActionButton.extended(
                  onPressed: _attemptNextDay,
                  label: Text(allAnswered ? 'Continue' : 'Pending'),
                  icon: Icon(allAnswered ? Icons.arrow_forward : Icons.access_time),
                )
              : null),
    );
  }
}

// === SETTINGS PAGE ===
class SettingsPage extends StatefulWidget {
  final ValueChanged<bool> onThemeChanged;
  SettingsPage({required this.onThemeChanged});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppConfig cfg = AppConfig.defaultConfig();
  bool _isDark = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadDarkMode();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      cfg = prefs.getString('config') != null
          ? AppConfig.fromJson(json.decode(prefs.getString('config')!))
          : AppConfig.defaultConfig();
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('config', json.encode(cfg.toJson()));
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = prefs.getBool('darkMode') ?? false);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: cfg.newDayTime);
    if (t != null) {
      setState(() => cfg.newDayTime = t);
      _saveConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        ListTile(
          title: Text('New Day Time'),
          subtitle: Text(cfg.newDayTime.format(context)),
          trailing: Icon(Icons.access_time),
          onTap: _pickTime,
        ),
        Divider(),
        SwitchListTile(
          title: Text('Dark Mode'),
          value: _isDark,
          onChanged: (v) {
            setState(() => _isDark = v);
            widget.onThemeChanged(v);
          },
        ),
        Divider(),
        Text('Scoring Settings', style: TextStyle(fontSize: 18)),
        _buildField('Start Pos', cfg.startPosMultiplier, (v) => cfg.startPosMultiplier = v),
        _buildField('Step Up', cfg.stepUp, (v) => cfg.stepUp = v),
        _buildField('Length Pos', cfg.lengthPosStreak, (v) => cfg.lengthPosStreak = v),
        _buildField('Max Pos', cfg.maxPosMultiplier, (v) => cfg.maxPosMultiplier = v),
        _buildField('Start Neg', cfg.startNegMultiplier, (v) => cfg.startNegMultiplier = v),
        _buildField('Step Down', cfg.stepDown, (v) => cfg.stepDown = v),
        _buildField('Length Neg', cfg.lengthNegStreak, (v) => cfg.lengthNegStreak = v),
        _buildField('Max Neg', cfg.maxNegMultiplier, (v) => cfg.maxNegMultiplier = v),
        SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('habits');
            await prefs.remove('history');
            await prefs.remove('totalPoints');
            await prefs.remove('currentDay');
            await prefs.remove('dayOver');
            Navigator.popUntil(context, ModalRoute.withName('/'));
          },
          child: Text('Reset All Data'),
        ),
      ]),
    );
  }

  Widget _buildField(String label, double val, Function(double) onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: val.toString(),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            onFieldSubmitted: (s) {
              final v = double.tryParse(s);
              if (v != null) {
                setState(() => onChanged(v));
                _saveConfig();
              }
            },
            decoration: InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ]),
    );
  }
}

// === OVERVIEW PAGE ===
class OverviewPage extends StatefulWidget {
  @override
  _OverviewPageState createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  List<DailyRecord> history = [];
  List<Habit> habits = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      history = prefs.getString('history') != null
          ? (json.decode(prefs.getString('history')!) as List)
              .map((j) => DailyRecord.fromJson(j))
              .toList()
          : [];
      habits = prefs.getString('habits') != null
          ? (json.decode(prefs.getString('habits')!) as List)
              .map((j) => Habit.fromJson(j))
              .toList()
          : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxDay = history.isNotEmpty
        ? history.map((d) => d.day).reduce(max)
        : 0;
    final days = List<int>.generate(maxDay, (i) => i + 1);

    return Scaffold(
      appBar: AppBar(title: Text('Overview')),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text('Habit')),
            ...days.map((d) => DataColumn(label: Text('Day $d'))),
          ],
          rows: habits.map((h) {
            return DataRow(cells: [
              DataCell(Text(h.title)),
              ...days.map((day) {
                final rec = history.firstWhere(
                  (r) => r.day == day,
                  orElse: () => DailyRecord(day, {}),
                );
                final val = rec.habitDeltas[h.title];
                return DataCell(Text(val != null
                    ? val.toStringAsFixed(2)
                    : '-'));
              }).toList(),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
