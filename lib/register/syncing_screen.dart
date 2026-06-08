import 'package:flutter/material.dart';

enum _TaskStatus { pending, running, done, error }

class SyncTask {
  const SyncTask({required this.label, required this.run});
  final String label;
  final Future<void> Function() run;
}

class SyncingScreen extends StatefulWidget {
  const SyncingScreen({
    super.key,
    required this.tasks,
    required this.onDone,
  });

  final List<SyncTask> tasks;
  final VoidCallback onDone;

  @override
  State<SyncingScreen> createState() => _SyncingScreenState();
}

class _SyncingScreenState extends State<SyncingScreen>
    with SingleTickerProviderStateMixin {
  static const _kPrimary = Color(0xFFE67E22);

  late List<_TaskStatus> _statuses;
  late AnimationController _spinController;

  bool get _allDone =>
      _statuses.every((s) => s == _TaskStatus.done || s == _TaskStatus.error);

  @override
  void initState() {
    super.initState();
    _statuses = List.filled(widget.tasks.length, _TaskStatus.pending);
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _runTasks();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _runTasks() async {
    for (int i = 0; i < widget.tasks.length; i++) {
      if (!mounted) return;
      setState(() => _statuses[i] = _TaskStatus.running);
      try {
        await widget.tasks[i].run();
        if (!mounted) return;
        setState(() => _statuses[i] = _TaskStatus.done);
      } catch (_) {
        if (!mounted) return;
        setState(() => _statuses[i] = _TaskStatus.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDone = _allDone;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  // Animated spinner / done icon
                  Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: isDone ? _buildDoneIcon() : _buildSpinner(),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Title
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      isDone ? 'All set!' : 'Syncing data',
                      key: ValueKey(isDone),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D2D2D),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      isDone
                          ? 'Your register is ready to use'
                          : 'Getting your register ready...',
                      key: ValueKey(isDone),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Task list
                  ...widget.tasks.asMap().entries.map((e) {
                    final i = e.key;
                    final status = _statuses[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          _TaskStatusIcon(status: status),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              e.value.label,
                              style: TextStyle(
                                fontSize: 15,
                                color: status == _TaskStatus.pending
                                    ? const Color(0xFFBDBDBD)
                                    : const Color(0xFF424242),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Spacer(),
                  // Done button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isDone ? widget.onDone : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        disabledBackgroundColor: const Color(0xFFE0E0E0),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFF9E9E9E),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinner() {
    return AnimatedBuilder(
      key: const ValueKey('spinner'),
      animation: _spinController,
      builder: (_, __) {
        return SizedBox(
          width: 72,
          height: 72,
          child: CustomPaint(
            painter: _SpinnerPainter(progress: _spinController.value),
          ),
        );
      },
    );
  }

  Widget _buildDoneIcon() {
    return Container(
      key: const ValueKey('done'),
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _kPrimary,
      ),
      child: const Icon(
        Icons.check_rounded,
        color: Colors.white,
        size: 40,
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.progress});
  final double progress;

  static const _kPrimary = Color(0xFFE67E22);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFF3E0CE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // Arc
    const sweepAngle = 1.4; // radians (~80°)
    final startAngle = progress * 2 * 3.14159 - 1.5708;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = _kPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.progress != progress;
}

class _TaskStatusIcon extends StatelessWidget {
  const _TaskStatusIcon({required this.status});
  final _TaskStatus status;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: SizedBox(
        key: ValueKey(status),
        width: 24,
        height: 24,
        child: switch (status) {
          _TaskStatus.pending => const Icon(
              Icons.radio_button_unchecked,
              size: 22,
              color: Color(0xFFE0E0E0),
            ),
          _TaskStatus.running => const CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFFE67E22),
            ),
          _TaskStatus.done => const Icon(
              Icons.check_circle,
              size: 22,
              color: Color(0xFF4CAF50),
            ),
          _TaskStatus.error => const Icon(
              Icons.error_outline,
              size: 22,
              color: Color(0xFFEF5350),
            ),
        },
      ),
    );
  }
}
