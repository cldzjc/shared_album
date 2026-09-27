import 'package:flutter/material.dart';

/// iOS 风格轻提示：顶部悬浮胶囊，自动消失。
///
/// 替代 Material SnackBar 的“后端感”绿色/红色大横条：
/// - 成功：白色胶囊 + 深色文字 + 绿色对勾；
/// - 失败：深色胶囊 + 白色文字 + 红色感叹；
/// - 从顶部滑入淡入，2.2 秒后自动滑出。
void showIosToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _IosToastWidget(
      message: message,
      isError: isError,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _IosToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismissed;

  const _IosToastWidget({
    required this.message,
    required this.isError,
    required this.onDismissed,
  });

  @override
  State<_IosToastWidget> createState() => _IosToastWidgetState();
}

class _IosToastWidgetState extends State<_IosToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _controller.forward();

    // 2.2 秒后自动收起并移除
    Future.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;

    return Positioned(
      top: topInset + 10,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, -0.4),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.isError
                      ? const Color(0xE61C1C1E)
                      : const Color(0xF2FFFFFF),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isError
                          ? Icons.cancel_rounded
                          : Icons.check_circle_rounded,
                      size: 18,
                      color: widget.isError
                          ? const Color(0xFFFF453A)
                          : const Color(0xFF34C759),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: widget.isError
                              ? Colors.white
                              : const Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
