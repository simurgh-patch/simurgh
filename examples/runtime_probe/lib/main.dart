import 'package:flutter/material.dart';
import 'probe_model.dart';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'simurgh runtime probe',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const ProbeHome(),
  );
}

class ProbeHome extends StatefulWidget {
  const ProbeHome({super.key});
  @override
  State<ProbeHome> createState() => _ProbeHomeState();
}

class _ProbeHomeState extends State<ProbeHome> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('simurgh · baseline')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Official Flutter reference. Custom patch runtime is not installed.',
          ),
        ),
        ListTile(
          title: const Text('Semantic baseline'),
          subtitle: Text(semanticProbe().toString()),
        ),
        for (final name in ['form', 'list', 'navigation', 'animation', 'async'])
          ListTile(
            key: ValueKey(name),
            title: Text(name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ScenarioPage(scenario: name),
              ),
            ),
          ),
      ],
    ),
  );
}

class ScenarioPage extends StatefulWidget {
  const ScenarioPage({required this.scenario, super.key});
  final String scenario;
  @override
  State<ScenarioPage> createState() => _ScenarioPageState();
}

class _ScenarioPageState extends State<ScenarioPage>
    with SingleTickerProviderStateMixin {
  final form = GlobalKey<FormState>();
  final username = TextEditingController();
  late final AnimationController animation;
  String result = '';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    animation.dispose();
    username.dispose();
    super.dispose();
  }

  Future<void> loadItems() async {
    setState(() => loading = true);
    final values = await deterministicItems();
    if (!mounted) return;
    setState(() {
      result = 'Loaded ${values.length} items';
      loading = false;
    });
  }

  Widget content() {
    switch (widget.scenario) {
      case 'form':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: form,
            child: Column(
              children: [
                TextFormField(
                  key: const ValueKey('username'),
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                FilledButton(
                  onPressed: () {
                    if (form.currentState!.validate()) {
                      setState(() => result = 'Hello, ${username.text.trim()}');
                    }
                  },
                  child: const Text('Submit'),
                ),
                Text(result),
              ],
            ),
          ),
        );
      case 'list':
        return ListView.builder(
          key: const ValueKey('long-list'),
          itemCount: 1000,
          itemExtent: 64,
          itemBuilder: (_, index) => ListTile(
            title: Text('Item $index'),
            subtitle: Text('Total: ${calculateTotal(index)}'),
          ),
        );
      case 'navigation':
        return Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Detail')),
                  body: const Center(
                    child: Text('Return to repeat the navigation scenario'),
                  ),
                ),
              ),
            ),
            child: const Text('Open detail'),
          ),
        );
      case 'animation':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotationTransition(
                turns: animation,
                child: const Icon(Icons.refresh, size: 96),
              ),
              FilledButton(
                onPressed: () => animation.forward(from: 0),
                child: const Text('Animate'),
              ),
            ],
          ),
        );
      case 'async':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: loading ? null : loadItems,
                child: const Text('Load'),
              ),
              if (loading) const CircularProgressIndicator(),
              Text(result),
            ],
          ),
        );
      default:
        throw StateError('Unknown scenario');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.scenario)),
    body: content(),
  );
}
