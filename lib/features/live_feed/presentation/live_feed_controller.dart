import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/live_feed_repository.dart';
import '../domain/activity_event.dart';

class LiveFeedState {
  final List<ActivityEvent> events;
  final bool isConnected;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastRefreshed;
  final int tick; // Incremented by periodic timer to refresh UI relative times

  const LiveFeedState({
    this.events = const [],
    this.isConnected = false,
    this.isLoading = false,
    this.errorMessage,
    this.lastRefreshed,
    this.tick = 0,
  });

  LiveFeedState copyWith({
    List<ActivityEvent>? events,
    bool? isConnected,
    bool? isLoading,
    String? errorMessage,
    DateTime? lastRefreshed,
    int? tick,
  }) {
    return LiveFeedState(
      events: events ?? this.events,
      isConnected: isConnected ?? this.isConnected,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      lastRefreshed: lastRefreshed ?? this.lastRefreshed,
      tick: tick ?? this.tick,
    );
  }
}

final liveFeedProvider = NotifierProvider<LiveFeedNotifier, LiveFeedState>(() {
  return LiveFeedNotifier();
});

class LiveFeedNotifier extends Notifier<LiveFeedState> {
  LiveFeedRepository get _repo => ref.read(liveFeedRepositoryProvider);
  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _timeAgoTimer;

  @override
  LiveFeedState build() {
    ref.onDispose(() {
      _timeAgoTimer?.cancel();
      _channel?.unsubscribe();
    });

    _init();
    _startTimeAgoTicker();
    return const LiveFeedState(isLoading: true);
  }

  void _startTimeAgoTicker() {
    // Tick every 30 seconds to update relative timeago descriptions
    _timeAgoTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      state = state.copyWith(tick: state.tick + 1);
    });
  }

  Future<void> _init() async {
    await refresh();
    _subscribeRealtime();
  }

  Future<void> refresh() async {
    try {
      state = state.copyWith(isLoading: state.events.isEmpty);
      final list = await _repo.fetchRecentActivities(limit: 25);
      state = state.copyWith(
        events: list,
        isLoading: false,
        lastRefreshed: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void _subscribeRealtime() {
    try {
      _channel = _client.channel('public:live_activities');

      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'payments',
            callback: (payload) {
              final newId = payload.newRecord['id']?.toString();
              if (newId != null) _handleNewPayment(newId);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'attendance',
            callback: (payload) {
              final sId = payload.newRecord['session_id']?.toString();
              final tId = payload.newRecord['trainee_id']?.toString();
              if (sId != null && tId != null) _handleNewAttendance(sId, tId);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'lab_payments',
            callback: (payload) {
              final newId = payload.newRecord['id']?.toString();
              if (newId != null) _handleNewLabPayment(newId);
            },
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              state = state.copyWith(isConnected: true);
              // Gap-recovery: whenever reconnecting, re-fetch to capture any missed events
              refresh();
            } else if (status == RealtimeSubscribeStatus.closed ||
                status == RealtimeSubscribeStatus.timedOut) {
              state = state.copyWith(isConnected: false);
            }
          });
    } catch (_) {
      state = state.copyWith(isConnected: false);
    }
  }

  Future<void> _handleNewPayment(String id) async {
    final event = await _repo.fetchSinglePayment(id);
    if (event != null) _prependEvent(event);
  }

  Future<void> _handleNewAttendance(String sessionId, String traineeId) async {
    final event = await _repo.fetchSingleAttendance(sessionId, traineeId);
    if (event != null) _prependEvent(event);
  }

  Future<void> _handleNewLabPayment(String id) async {
    final event = await _repo.fetchSingleLabPayment(id);
    if (event != null) _prependEvent(event);
  }

  void _prependEvent(ActivityEvent event) {
    final current = List<ActivityEvent>.from(state.events);
    current.removeWhere((e) => e.id == event.id);
    current.insert(0, event);
    if (current.length > 50) current.removeLast();
    state = state.copyWith(events: current);
  }
}
