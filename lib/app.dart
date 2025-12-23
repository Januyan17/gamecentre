import 'package:flutter/material.dart';
import 'package:rowzow/core/screens/dashboard_page.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gaming Center Staff',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const DashboardPage(),
    );
  }
}
