import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SimplePlaceholderScreen extends StatelessWidget {
  const SimplePlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.primaryLabel,
    this.primaryRoute,
  });

  final String title;
  final IconData icon;
  final String message;
  final String? primaryLabel;
  final String? primaryRoute;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Colors.blueGrey[200]),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400]),
              ),
              if (primaryLabel != null && primaryRoute != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go(primaryRoute!),
                  child: Text(primaryLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
