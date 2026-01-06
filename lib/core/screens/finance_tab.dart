import 'package:flutter/material.dart';
import 'daily_finance_page.dart';
import 'finance_history_page.dart';

class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key});

  @override
  State<FinanceTab> createState() => FinanceTabState();
}

class FinanceTabState extends State<FinanceTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void refreshData() {
    // This will be called when the tab is selected
    // The DailyFinancePage will refresh in its didChangeDependencies
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finance'),
          backgroundColor: Colors.purple.shade700,
          foregroundColor: Colors.white,
          bottom: TabBar(
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
        body: const TabBarView(
          children: [
            DailyFinancePage(),
            FinanceHistoryPage(),
          ],
        ),
      ),
    );
  }
}

