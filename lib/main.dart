import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(const OasisGridApp());
}

class OasisGridApp extends StatelessWidget {
  const OasisGridApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oasis-Grid Nabeul',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        primarySwatch: Colors.teal,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00B0FF),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  
  // Real-time data stream
  final List<FlSpot> _waterFilteredData = [];
  Timer? _timer;
  double _timeCounter = 0;
  
  // Socket.IO state
  IO.Socket? socket;
  int _activeSinks = 0;
  int _activeShowers = 0;
  List<dynamic> _filters = [];
  Set<int> _notifiedBrokenFilters = {};
  
  // KPIs
  double _totalLitersFiltered = 0.0; 
  final double _tariffPerLiter = 0.0055; 
  final double _efficiencyRating = 96.4;

  // History & Forecast
  String _selectedTimeframe = 'Live';
  final List<FlSpot> _historyData = [];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _initSocket();
    _initializeData();
    _startSimulatedLiveStream();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _totalLitersFiltered = prefs.getDouble('totalLitersFiltered') ?? 0.0;
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('totalLitersFiltered', _totalLitersFiltered);
  }

  Future<void> _resetData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('totalLitersFiltered', 0.0);
    setState(() {
      _totalLitersFiltered = 0.0;
    });
  }

  void _initSocket() {
    socket = IO.io('http://hackathon.bahroun.com', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    
    socket?.onConnect((_) {
      debugPrint('Connected to Oasis-Grid server');
    });

    socket?.on('faucet_state', (data) {
      if (mounted && data != null) {
        setState(() {
          _activeSinks = data['activeSinks'] ?? 0;
          _activeShowers = data['activeShowers'] ?? 0;
          
          if (data['filters'] != null) {
            _filters = data['filters'];
            _checkForBrokenFilters();
          }
        });
      }
    });
  }

  void _checkForBrokenFilters() {
    for (var f in _filters) {
      int id = f['id'];
      String status = f['status'];
      
      if (status == 'NEEDS_SERVICE' && !_notifiedBrokenFilters.contains(id)) {
        _notifiedBrokenFilters.add(id);
        _showNotification("Alert: IoT Controller for Filter $id reports NEEDS SERVICE.");
      } else if (status == 'OK' && _notifiedBrokenFilters.contains(id)) {
        _notifiedBrokenFilters.remove(id);
      }
    }
  }

  void _showNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: const Color(0xFF2C2C2C),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _fixFilter(int id) {
    socket?.emit('fix_filter', {'id': id});
  }

  void _initializeData() {
    for (double i = 0; i <= 60; i += 1.0) {
      _waterFilteredData.add(FlSpot(i, 0.0));
    }
    _timeCounter = 60.0;
  }

  void _generateHistoryData() {
    _historyData.clear();
    double baseDailyVolume = 28000.0; // 28,000 Liters baseline
    final rand = Random();

    if (_selectedTimeframe == 'Day') {
      for (int i = 0; i < 24; i++) {
        double val = 500.0 + 800.0 * sin((i - 6) * pi / 4) + rand.nextDouble() * 200;
        if (val < 200) val = 200 + rand.nextDouble() * 50;
        _historyData.add(FlSpot(i.toDouble(), val));
      }
    } else if (_selectedTimeframe == 'Week') {
      for (int i = 0; i < 7; i++) {
        _historyData.add(FlSpot(i.toDouble(), baseDailyVolume + rand.nextDouble() * 5000));
      }
    } else if (_selectedTimeframe == 'Month') {
      for (int i = 0; i < 30; i++) {
        _historyData.add(FlSpot(i.toDouble(), baseDailyVolume + rand.nextDouble() * 8000));
      }
    } else if (_selectedTimeframe == 'Year') {
      for (int i = 0; i < 12; i++) {
        double monthly = (baseDailyVolume * 30) + (i * 15000) + rand.nextDouble() * 50000;
        _historyData.add(FlSpot(i.toDouble(), monthly));
      }
    } else if (_selectedTimeframe == 'Forecast') {
      for (int i = 0; i < 5; i++) {
        double yearly = (baseDailyVolume * 365) * (1.0 + (i * 0.35)); 
        _historyData.add(FlSpot(i.toDouble(), yearly));
      }
    }
  }

  void _startSimulatedLiveStream() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timeCounter += 1.0; 
        double currentFlowRateLitersPerHour = (_activeSinks * 360.0) + (_activeShowers * 1080.0);
        
        _waterFilteredData.add(FlSpot(_timeCounter, currentFlowRateLitersPerHour));
        
        double litersFilteredInInterval = currentFlowRateLitersPerHour * (1.0 / 3600.0);
        _totalLitersFiltered += litersFilteredInInterval; 
        
        if (litersFilteredInInterval > 0) {
           _saveData(); 
        }
        
        if (_waterFilteredData.length > 60) {
          _waterFilteredData.removeAt(0); 
        }
      });
    });
  }

  @override
  void dispose() {
    socket?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  double get _chartMaxY {
    final data = _selectedTimeframe == 'Live' ? _waterFilteredData : _historyData;
    if (data.isEmpty) return 100;
    
    double maxVal = 0;
    for (var spot in data) {
      if (spot.y > maxVal) maxVal = spot.y;
    }
    if (maxVal == 0) return 100;
    return maxVal * 1.2;
  }

  double get _chartMaxX {
    switch (_selectedTimeframe) {
      case 'Live': return _waterFilteredData.last.x;
      case 'Day': return 23;
      case 'Week': return 6;
      case 'Month': return 29;
      case 'Year': return 11;
      case 'Forecast': return 4;
      default: return 60;
    }
  }

  double get _chartMinX {
    if (_selectedTimeframe == 'Live') {
      return _waterFilteredData.first.x;
    }
    return 0;
  }

  Widget _buildTimeframeSelector() {
    final List<String> options = ['Live', 'Day', 'Week', 'Month', 'Year', 'Forecast'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((String option) {
          final isSelected = _selectedTimeframe == option;
          final isForecast = option == 'Forecast';
          Color activeColor = isForecast ? const Color(0xFF00E676) : const Color(0xFF00B0FF);

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTimeframe = option;
                if (option != 'Live') _generateHistoryData();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? activeColor : Colors.white24,
                ),
              ),
              child: Row(
                children: [
                  if (isForecast && isSelected) ...[
                    const Icon(Icons.auto_graph, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    option,
                    style: TextStyle(
                      color: isSelected ? (isForecast ? Colors.black87 : Colors.white) : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF121212),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.waves, size: 48, color: Color(0xFF00B0FF)),
                SizedBox(height: 12),
                Text('Oasis-Grid Nabeul', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('Control Panel v1.0', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Color(0xFF00B0FF)),
            title: const Text('System Status'),
            selected: _selectedIndex == 0,
            onTap: () {
              setState(() => _selectedIndex = 0);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_money, color: Color(0xFFFFD54F)),
            title: const Text('Financial Reports'),
            selected: _selectedIndex == 1,
            onTap: () {
              setState(() => _selectedIndex = 1);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.eco, color: Color(0xFF00E676)),
            title: const Text('Eco Impact'),
            selected: _selectedIndex == 2,
            onTap: () {
              setState(() => _selectedIndex = 2);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterGrid() {
    if (_filters.isEmpty) return const Center(child: CircularProgressIndicator());
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: _filters.length,
      itemBuilder: (context, index) {
        final filter = _filters[index];
        final isOk = filter['status'] == 'OK';
        
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOk ? Colors.white10 : Colors.redAccent.withOpacity(0.5),
              width: isOk ? 1 : 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.memory,
                color: isOk ? const Color(0xFF00E676) : Colors.redAccent,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text('Filter ${filter['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (!isOk)
                ElevatedButton(
                  onPressed: () => _fixFilter(filter['id']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(60, 24),
                  ),
                  child: const Text('REPAIR', style: TextStyle(fontSize: 10, color: Colors.white)),
                )
              else
                Text(filter['status'], style: TextStyle(color: isOk ? Colors.white54 : Colors.redAccent, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSystemStatusTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusBadge(),
          const SizedBox(height: 32),
          const Text('Data Analytics', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildTimeframeSelector(),
          const SizedBox(height: 24),
          _buildChart(),
          const SizedBox(height: 32),
          const Text('IoT Microcontroller Fleet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const Text('Live ESP32 telemetry from localized bio-filters.', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          _buildFilterGrid(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFinancialReportsTab(double savedTND) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Financial ROI Dashboard', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Real-time utility savings generated by decentralized greywater treatment.', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 32),
          _buildKPICard(
            title: 'Current Utility Savings',
            subtitle: 'Cumulative TND diverted from municipal billing',
            value: '${savedTND.toStringAsFixed(3)} TND',
            icon: Icons.account_balance_wallet,
            color: const Color(0xFFFFD54F),
          ),
          const SizedBox(height: 16),
          _buildKPICard(
            title: 'Annual Projected Savings',
            subtitle: 'Based on current flow-rate trajectory',
            value: '${(savedTND * 365).toStringAsFixed(0)} TND / year',
            icon: Icons.trending_up,
            color: const Color(0xFF00B0FF),
          ),
          const SizedBox(height: 16),
          _buildKPICard(
            title: 'ROI Timeframe',
            subtitle: 'Estimated time to break even on hardware costs',
            value: '4.2 Months',
            icon: Icons.access_time,
            color: Colors.purpleAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildEcoImpactTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ecological Impact', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Tracking progress towards UN Sustainable Development Goals.', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 32),
          _buildKPICard(
            title: 'Total Water Recycled',
            subtitle: 'SDG 11: Sustainable Cities & Communities',
            value: '${_totalLitersFiltered.toStringAsFixed(1)} L',
            icon: Icons.water_drop,
            color: const Color(0xFF00B0FF),
          ),
          const SizedBox(height: 16),
          _buildKPICard(
            title: 'Infrastructure Efficiency',
            subtitle: 'SDG 9: Industry, Innovation & Infrastructure',
            value: '$_efficiencyRating%',
            icon: Icons.precision_manufacturing,
            color: const Color(0xFF00E676),
          ),
          const SizedBox(height: 16),
          _buildKPICard(
            title: 'Carbon Offset Equivalent',
            subtitle: 'Reduced pumping & processing energy',
            value: '${(_totalLitersFiltered * 0.002).toStringAsFixed(2)} kg CO₂',
            icon: Icons.co2,
            color: Colors.tealAccent,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double savedTND = _totalLitersFiltered * _tariffPerLiter;

    Widget body;
    if (_selectedIndex == 0) body = _buildSystemStatusTab();
    else if (_selectedIndex == 1) body = _buildFinancialReportsTab(savedTND);
    else body = _buildEcoImpactTab();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Oasis-Grid Hub', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            tooltip: 'Reset Data',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset Analytics?'),
                  content: const Text('This will permanently delete your tracked total filtered Liters and TND savings.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                    TextButton(
                      onPressed: () {
                        _resetData();
                        Navigator.pop(context);
                      },
                      child: const Text('RESET', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text('Live', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
      drawer: _buildDrawer(),
      body: body,
    );
  }

  Widget _buildStatusBadge() {
    final bool isAnyFaucetOn = _activeSinks > 0 || _activeShowers > 0;
    final statusColor = isAnyFaucetOn ? const Color(0xFF00B0FF) : const Color(0xFF00E676);
    final statusText = isAnyFaucetOn 
      ? 'Bio-filter active: Processing $_activeSinks sink(s) and $_activeShowers shower(s)' 
      : 'Bio-filter Active: Standing By';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(isAnyFaucetOn ? Icons.water_drop : Icons.autorenew, color: statusColor, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Circular Economy Status', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(statusText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: statusColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final data = _selectedTimeframe == 'Live' ? _waterFilteredData : _historyData;
    final isForecast = _selectedTimeframe == 'Forecast';
    final chartColor = isForecast ? const Color(0xFF00E676) : const Color(0xFF00B0FF);

    return Container(
      height: 320,
      padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => const FlLine(color: Colors.white10, strokeWidth: 1)),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 55,
                getTitlesWidget: (value, meta) {
                  String text;
                  if (value >= 1000000) text = '${(value / 1000000).toStringAsFixed(1)}M';
                  else if (value >= 1000) text = '${(value / 1000).toStringAsFixed(0)}k';
                  else text = value.toInt().toString();
                  return Padding(padding: const EdgeInsets.only(right: 8.0), child: Text(text, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 11)));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: _chartMinX, maxX: _chartMaxX, minY: 0, maxY: _chartMaxY,
          lineBarsData: [
            LineChartBarData(
              spots: data.isEmpty ? [const FlSpot(0,0)] : data,
              isCurved: true, color: chartColor, barWidth: 3, isStrokeCapRound: true, dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: chartColor.withOpacity(0.15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPICard({required String title, required String subtitle, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 32, color: color),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
