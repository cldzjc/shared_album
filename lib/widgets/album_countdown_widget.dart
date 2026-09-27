import 'dart:async';

import 'package:flutter/material.dart';

class AlbumCountdownWidget extends StatefulWidget {
  final DateTime expiresAt;

  const AlbumCountdownWidget({super.key, required this.expiresAt});

  @override
  State<AlbumCountdownWidget> createState() => _AlbumCountdownWidgetState();
}

class _AlbumCountdownWidgetState extends State<AlbumCountdownWidget> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatRemaining(Duration remaining) {
    if (remaining.inHours > 0) {
      final minutes = remaining.inMinutes
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '${remaining.inHours}h${minutes}m 后自动销毁';
    }

    if (remaining.inMinutes > 0) {
      final seconds = remaining.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '${remaining.inMinutes}m${seconds}s 后自动销毁';
    }

    return '${remaining.inSeconds}s 后自动销毁';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(_now);
    final isExpired = remaining.isNegative;

    return Text(
      isExpired ? '已过期' : '🕒 ${_formatRemaining(remaining)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isExpired ? Theme.of(context).colorScheme.error : null,
        fontSize: 12,
        fontWeight: FontWeight.normal,
      ),
    );
  }
}
