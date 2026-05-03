import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
          primary: Color(0xFF00E676), // Vibrant green
          secondary: Color(0xFF00B0FF), // Bright blue
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Real-time data stream
  final List<FlSpot> _waterFilteredData = [];
  Timer? _timer;
  double _timeCounter = 0;
  
  // Socket.IO
  IO.Socket? socket;
  int _activeFaucets = 0;
  
  // KPIs
  double _totalLitersFiltered = 0.0; // Start exactly at 0 for accurate live tracking
  final double _tariffPerLiter = 0.0055; // 5.5 TND per m3 (Combined Water + Sanitation Commercial Tariff)
  final double _efficiencyRating = 96.4;

  @override
  void initState() {
    super.initState();
    _initSocket();
    _initializeData();
    _startSimulatedLiveStream();
  }

  void _initSocket() {
    // Connect to the Oasis-Grid production server
    socket = IO.io('http://hackathon.bahroun.com', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    
    socket?.onConnect((_) {
      debugPrint('Connected to Oasis-Grid server');
    });

    socket?.on('faucet_state', (data) {
      if (mounted && data != null && data['activeCount'] != null) {
        setState(() {
          _activeFaucets = data['activeCount'];
        });
      }
    });

    socket?.onDisconnect((_) => debugPrint('Disconnected from server'));
  }

  void _initializeData() {
    // Fill the chart with a blank 60-second window
    for (double i = 0; i <= 60; i += 1.0) {
      _waterFilteredData.add(FlSpot(i, 0.0));
    }
    _timeCounter = 60.0;
  }

  void _startSimulatedLiveStream() {
    // Poll real-time data every 1 second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timeCounter += 1.0; // 1 second
        
        // Accurate real-time calculation
        // 1 standard faucet = 360 L/hr.
        double currentFlowRateLitersPerHour = _activeFaucets * 360.0;
        
        _waterFilteredData.add(FlSpot(_timeCounter, currentFlowRateLitersPerHour));
        
        // 1 second of real time passed. 1 second = 1/3600 hours.
        double litersFilteredInInterval = currentFlowRateLitersPerHour * (1.0 / 3600.0);
        _totalLitersFiltered += litersFilteredInInterval; 
        
        if (_waterFilteredData.length > 60) {
          _waterFilteredData.removeAt(0); // keep a rolling 60-second window
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

  @override
  Widget build(BuildContext context) {
    double savedTND = _totalLitersFiltered * _tariffPerLiter;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Oasis-Grid: Hotel Dashboard',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E676),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Live',
                  style: TextStyle(
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusBadge(),
              const SizedBox(height: 32),
              const Text(
                'Live Data Stream',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Current Filtration Rate (Liters/Hour)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              _buildChart(),
              const SizedBox(height: 32),
              const Text(
                'Impact & KPI Dashboard',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _buildKPICards(savedTND),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final bool isAnyFaucetOn = _activeFaucets > 0;
    final statusColor = isAnyFaucetOn ? const Color(0xFF00B0FF) : const Color(0xFF00E676);
    final statusText = isAnyFaucetOn 
      ? 'Bio-filter active: Processing $_activeFaucets sink(s)' 
      : 'Bio-filter Active: Standing By';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isAnyFaucetOn ? Icons.water_drop : Icons.autorenew,
            color: statusColor,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Circular Economy Status',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    return Container(
      height: 320,
      padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) {
              return const FlLine(
                color: Colors.white10,
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      value.toInt().toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: _waterFilteredData.isEmpty ? 0 : _waterFilteredData.first.x,
          maxX: _waterFilteredData.isEmpty ? 60 : _waterFilteredData.last.x,
          minY: 0,
          maxY: 4000,
          lineBarsData: [
            LineChartBarData(
              spots: _waterFilteredData,
              isCurved: true,
              color: const Color(0xFF00B0FF),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF00B0FF).withOpacity(0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPICards(double savedTND) {
    return Column(
      children: [
        _buildKPICard(
          title: 'Municipal Drinking Water Saved',
          subtitle: 'SDG 11: Sustainable Cities & Communities',
          value: '${_totalLitersFiltered.toStringAsFixed(1)} L',
          icon: Icons.water_drop,
          color: const Color(0xFF00B0FF), // Blue
        ),
        const SizedBox(height: 16),
        _buildKPICard(
          title: 'Utility Bill Savings',
          subtitle: 'SDG 8: Decent Work & Economic Growth',
          value: '${savedTND.toStringAsFixed(2)} TND',
          icon: Icons.account_balance_wallet,
          color: const Color(0xFFFFD54F), // Amber
        ),
        const SizedBox(height: 16),
        _buildKPICard(
          title: 'Infrastructure Efficiency',
          subtitle: 'SDG 9: Industry, Innovation & Infrastructure',
          value: '$_efficiencyRating%',
          icon: Icons.precision_manufacturing,
          color: const Color(0xFF00E676), // Green
        ),
      ],
    );
  }

  Widget _buildKPICard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 32,
              color: color,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
