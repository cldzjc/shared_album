import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlbumExpiryNotifier extends AsyncNotifier<DateTime?> {
  final String albumId;
  Timer? _timer;

  AlbumExpiryNotifier(this.albumId);

  @override
  Future<DateTime?> build() async {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.mounted) {
        refresh();
      }
    });

    ref.onDispose(() => _timer?.cancel());
    return _fetchLatestExpiresAt(albumId);
  }

  Future<DateTime?> _fetchLatestExpiresAt(String id) async {
    final supabase = Supabase.instance.client;
    final response = await supabase
        .from('albums')
        .select('expires_at')
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return DateTime.parse(response['expires_at'] as String);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _fetchLatestExpiresAt(albumId));
  }
}

final albumExpiryProvider = AsyncNotifierProvider.autoDispose
    .family<AlbumExpiryNotifier, DateTime?, String>(
      (albumId) => AlbumExpiryNotifier(albumId),
    );
