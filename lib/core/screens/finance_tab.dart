import 'package:flutter/material.dart';
import 'daily_finance_page.dart';
import 'finance_history_page.dart';

class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key});

  @override
  State<FinanceTab> createState() => FinanceTabState();
}

class FinanceTabState extends State<FinanceTab> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  
  late TabController _tabController;
  final GlobalKey<DailyFinancePageState> _dailyFinanceKey = GlobalKey<DailyFinancePageState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Refresh daily finance page when tab 0 (Daily Finance) is selected
    if (_tabController.index == 0 && _dailyFinanceKey.currentState != null) {
      _dailyFinanceKey.currentState!.refreshData();
    }
  }

  void refreshData() {
    // This will be called when the tab is selected from navigation
    if (_dailyFinanceKey.currentState != null) {
      _dailyFinanceKey.currentState!.refreshData();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Scaffold(
        appBar: AppBar(
          title: const Text('Finance'),
          backgroundColor: Colors.purple.shade700,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(
                icon: Icon(Icons.account_balance_wallet),
                text: 'Daily Finance',
              ),
              Tab(
                icon: Icon(Icons.timeline),
                text: 'History',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            DailyFinancePage(key: _dailyFinanceKey),
            const FinanceHistoryPage(),
          ],
        ),
      );
  }
}

