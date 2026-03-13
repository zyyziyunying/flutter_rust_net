import 'package:flutter/material.dart';

import 'apis/example_app_config.dart';
import 'pages/benchmark_page.dart';
import 'pages/request_lab_page.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  final ExampleAppConfig config;

  const ExampleApp({super.key, this.config = kExampleAppConfig});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_rust_net example',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      ),
      home: ExampleHomePage(config: config),
    );
  }
}

class BenchmarkExampleApp extends ExampleApp {
  const BenchmarkExampleApp({super.key});
}

class ExampleHomePage extends StatelessWidget {
  final ExampleAppConfig config;

  const ExampleHomePage({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_rust_net example'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.api_outlined), text: 'Request Lab'),
              Tab(icon: Icon(Icons.speed_outlined), text: 'Benchmark'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            RequestLabPage(config: config.requestLab),
            BenchmarkPage(config: config.benchmark),
          ],
        ),
      ),
    );
  }
}
