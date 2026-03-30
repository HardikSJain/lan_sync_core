import 'package:flutter/material.dart';
import 'package:lan_sync_core/lan_sync_core.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';

class SyncStatusScreen extends StatefulWidget {
  final SyncEngine<Task> syncEngine;

  const SyncStatusScreen({
    required this.syncEngine,
    super.key,
  });

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  final List<SyncEngineEvent> _events = [];
  final int _maxEvents = 50;

  @override
  void initState() {
    super.initState();
    
    // Listen to sync events
    widget.syncEngine.events.listen((event) {
      if (mounted) {
        setState(() {
          _events.insert(0, event);
          if (_events.length > _maxEvents) {
            _events.removeLast();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final peerIds = widget.syncEngine.getActivePeerIds();
    final metrics = widget.syncEngine.getAllMetrics();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Status'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Peer count
          _buildCard(
            title: 'Connected Peers',
            child: Text(
              '${peerIds.length}',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Peer list
          if (peerIds.isNotEmpty) ...[
            _buildCard(
              title: 'Active Peers',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: peerIds.map((peerId) {
                  final peerMetrics = metrics[peerId];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: peerMetrics?.isCircuitOpen ?? false
                                    ? Colors.red
                                    : Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                peerId.substring(0, 8),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (peerMetrics != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Success: ${(peerMetrics.successRate * 100).toStringAsFixed(0)}% '
                            '(${peerMetrics.totalSuccess}/${peerMetrics.totalAttempts})',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (peerMetrics.consecutiveFailures > 0)
                            Text(
                              'Failures: ${peerMetrics.consecutiveFailures} consecutive',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.red.shade700,
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Metrics summary
          if (metrics.isNotEmpty) ...[
            _buildCard(
              title: 'Sync Metrics',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetricRow(
                    'Total attempts',
                    metrics.values.fold(0, (sum, m) => sum + m.totalAttempts).toString(),
                  ),
                  _buildMetricRow(
                    'Successful syncs',
                    metrics.values.fold(0, (sum, m) => sum + m.totalSuccess).toString(),
                  ),
                  _buildMetricRow(
                    'Active failures',
                    metrics.values.fold(0, (sum, m) => sum + m.consecutiveFailures).toString(),
                  ),
                  _buildMetricRow(
                    'Circuits open',
                    metrics.values.where((m) => m.isCircuitOpen).length.toString(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Event log
          _buildCard(
            title: 'Recent Events',
            child: _events.isEmpty
                ? Text(
                    'No events yet',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _events.map((event) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatTime(event.timestamp),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatEventType(event.type),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: _getEventColor(event.type),
                                    ),
                                  ),
                                  if (event.peerId != null)
                                    Text(
                                      event.peerId!.substring(0, 8),
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  if (event.error != null)
                                    Text(
                                      event.error!,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontSize: 11,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: AppTheme.gray,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _formatEventType(SyncEngineEventType type) {
    return type.name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(0)}',
    ).trim().toUpperCase();
  }

  Color _getEventColor(SyncEngineEventType type) {
    switch (type) {
      case SyncEngineEventType.syncCompleted:
      case SyncEngineEventType.peerDiscovered:
      case SyncEngineEventType.circuitBreakerReset:
        return Colors.green.shade700;
      
      case SyncEngineEventType.syncFailed:
      case SyncEngineEventType.circuitBreakerOpened:
      case SyncEngineEventType.peerLost:
      case SyncEngineEventType.error:
        return Colors.red.shade700;
      
      case SyncEngineEventType.syncSkipped:
        return Colors.orange.shade700;
      
      default:
        return AppTheme.black;
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
