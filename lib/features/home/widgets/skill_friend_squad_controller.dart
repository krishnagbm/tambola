import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents one of the up to 5 players (You + max 4 friends) in a Hostless Skill Friend Squad.
class SkillSquadMember {
  final String playerId;
  final String name;
  final String avatar;
  final bool isCreator;
  final int score;
  final int progress;
  final int target;
  final int wrongCount;
  final int reactionMs;
  final bool completed;
  final String? lastEvent;
  final int updatedAtMs;

  const SkillSquadMember({
    required this.playerId,
    required this.name,
    required this.avatar,
    this.isCreator = false,
    this.score = 0,
    this.progress = 0,
    this.target = 5,
    this.wrongCount = 0,
    this.reactionMs = 0,
    this.completed = false,
    this.lastEvent,
    required this.updatedAtMs,
  });

  SkillSquadMember copyWith({
    String? name,
    String? avatar,
    bool? isCreator,
    int? score,
    int? progress,
    int? target,
    int? wrongCount,
    int? reactionMs,
    bool? completed,
    String? lastEvent,
    int? updatedAtMs,
  }) {
    return SkillSquadMember(
      playerId: playerId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      isCreator: isCreator ?? this.isCreator,
      score: score ?? this.score,
      progress: progress ?? this.progress,
      target: target ?? this.target,
      wrongCount: wrongCount ?? this.wrongCount,
      reactionMs: reactionMs ?? this.reactionMs,
      completed: completed ?? this.completed,
      lastEvent: lastEvent ?? this.lastEvent,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'player_id': playerId,
    'name': name,
    'avatar': avatar,
    'is_creator': isCreator,
    'score': score,
    'progress': progress,
    'target': target,
    'wrong_count': wrongCount,
    'reaction_ms': reactionMs,
    'completed': completed,
    'last_event': lastEvent,
    'updated_at_ms': updatedAtMs,
  };

  factory SkillSquadMember.fromJson(Map<String, dynamic> json) {
    return SkillSquadMember(
      playerId: json['player_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Friend',
      avatar: json['avatar']?.toString() ?? '🎲',
      isCreator: json['is_creator'] == true,
      score: (json['score'] as num?)?.toInt() ?? 0,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      target: (json['target'] as num?)?.toInt() ?? 5,
      wrongCount: (json['wrong_count'] as num?)?.toInt() ?? 0,
      reactionMs: (json['reaction_ms'] as num?)?.toInt() ?? 0,
      completed: json['completed'] == true,
      lastEvent: json['last_event']?.toString(),
      updatedAtMs:
          (json['updated_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Tracks a ball that a squad mate has claimed/placed on the 3×9 grid.
class RemotePlacement {
  final int row;
  final int col;
  final String playerName;
  final String playerAvatar;

  const RemotePlacement({
    required this.row,
    required this.col,
    required this.playerName,
    required this.playerAvatar,
  });
}

/// Manages a Hostless 5-Player Friend Squad (Creator + max 4 Friends = 5 Players Free Plan)
/// using Supabase Realtime Broadcast channels so friends can join by code while you play.
class SkillFriendSquadController extends ChangeNotifier {
  static const int maxPlayers = 5; // You + max 4 friends (Free tier cap)

  static const List<String> _avatars = [
    '🦁',
    '🐯',
    '🦊',
    '🐼',
    '🦅',
    '🦄',
    '🐬',
    '🦉',
  ];

  late String _localPlayerId;
  String _localName = 'Player';
  String _localAvatar = '🦁';

  String? _squadCode;
  bool _isCreator = false;
  bool _isConnecting = false;
  String? _errorMessage;
  String? _liveFeedMessage;

  String _syncedGameId = 'level_0a_make';
  String _syncedSubMode = 'make_5_quad';
  int _syncedRoundSeed = 1001;
  int? _syncedStartedAtMs;

  final Map<String, SkillSquadMember> _members = {};
  RealtimeChannel? _channel;

  /// Remote ball placements from squad mates: ball → {row, col, playerName, avatar}.
  /// Used to show "claimed" badges on the deal pool and block re-picking.
  final Map<int, RemotePlacement> remotePlacements = {};

  /// Callback triggered when the squad switches game, subMode, seed, or starts a round.
  void Function(
    String gameId,
    String subMode,
    int roundSeed,
    bool autoStart,
  )?
  onRemoteRoundSync;

  /// Callback triggered when a squad mate drops a ball onto a cell.
  /// [ball] is the ball number, [row]/[col] are 0-based grid indices,
  /// [playerName] and [playerAvatar] are the claimer's display info.
  void Function(int ball, int row, int col, String playerName, String playerAvatar)?
  onRemoteBallPlaced;

  /// Callback triggered when a squad mate lifts a ball they previously placed
  /// (moved it off a cell). [ball] is the ball number freed.
  void Function(int ball)? onRemoteBallLifted;

  String get localPlayerId => _localPlayerId;
  String get localName => _localName;
  String get localAvatar => _localAvatar;
  String? get squadCode => _squadCode;
  bool get isInSquad => _squadCode != null;
  bool get isCreator => _isCreator;
  bool get isConnecting => _isConnecting;
  String? get errorMessage => _errorMessage;
  String? get liveFeedMessage => _liveFeedMessage;
  int get syncedRoundSeed => _syncedRoundSeed;
  String get syncedGameId => _syncedGameId;
  String get syncedSubMode => _syncedSubMode;

  /// Sorted list of up to 5 squad members (ranked by completed/score/reaction time).
  List<SkillSquadMember> get sortedMembers {
    final list = _members.values.toList();
    list.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      if (a.progress != b.progress) return b.progress.compareTo(a.progress);
      if (a.wrongCount != b.wrongCount) {
        return a.wrongCount.compareTo(b.wrongCount);
      }
      return a.reactionMs.compareTo(b.reactionMs);
    });
    return list;
  }

  Future<void> initIdentity() async {
    final rng = Random();
    _localPlayerId =
        'p_${DateTime.now().millisecondsSinceEpoch}_${rng.nextInt(9999)}';
    _localAvatar = _avatars[rng.nextInt(_avatars.length)];
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final metaName =
          user?.userMetadata?['display_name']?.toString() ??
          user?.userMetadata?['full_name']?.toString();
      if (metaName != null && metaName.trim().isNotEmpty) {
        _localName = metaName.trim();
      } else {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('dabhousie_squad_nickname');
        if (saved != null && saved.trim().isNotEmpty) {
          _localName = saved.trim();
        } else {
          _localName = 'Player ${100 + rng.nextInt(899)}';
        }
      }
      if (user != null && user.id.isNotEmpty) {
        _localPlayerId = user.id;
      }
    } catch (_) {
      _localName = 'Player ${100 + rng.nextInt(899)}';
    }
    notifyListeners();
  }

  Future<void> updateLocalName(String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return;
    _localName = clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dabhousie_squad_nickname', clean);
    } catch (_) {}
    if (isInSquad && _members.containsKey(_localPlayerId)) {
      _members[_localPlayerId] = _members[_localPlayerId]!.copyWith(
        name: _localName,
      );
      _broadcastMemberUpdate(_members[_localPlayerId]!);
    }
    notifyListeners();
  }

  /// Creates a new 5-Player Friend Squad (You + up to 4 friends) while playing.
  Future<String> createSquad({
    required String gameId,
    required String subMode,
    required int roundSeed,
    String? customNickname,
  }) async {
    if (customNickname != null && customNickname.trim().isNotEmpty) {
      await updateLocalName(customNickname);
    }
    await leaveSquad(silent: true);

    final rng = Random();
    final code = '${1000 + rng.nextInt(9000)}';
    _squadCode = code;
    _isCreator = true;
    _isConnecting = true;
    _errorMessage = null;
    _syncedGameId = gameId;
    _syncedSubMode = subMode;
    _syncedRoundSeed = roundSeed;
    _syncedStartedAtMs = null;

    final me = SkillSquadMember(
      playerId: _localPlayerId,
      name: _localName,
      avatar: _localAvatar,
      isCreator: true,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _members[_localPlayerId] = me;
    _liveFeedMessage =
        '🎉 Squad #$code open! Share code with up to 4 friends (Max 5 players free).';
    notifyListeners();

    await _subscribeToChannel(code);
    _isConnecting = false;
    notifyListeners();
    return code;
  }

  /// Joins an existing Friend Squad by its 4-digit code (enforcing Max 5 Players = Creator + 4 Friends).
  Future<bool> joinSquad({
    required String code,
    String? customNickname,
    required String currentGameId,
    required String currentSubMode,
    required int currentSeed,
  }) async {
    final cleanCode = code
        .trim()
        .toUpperCase()
        .replaceAll('DAB-', '')
        .replaceAll('#', '')
        .trim();
    if (cleanCode.isEmpty) {
      _errorMessage = 'Please enter a valid 4-digit Friend Code.';
      notifyListeners();
      return false;
    }

    if (customNickname != null && customNickname.trim().isNotEmpty) {
      await updateLocalName(customNickname);
    }
    await leaveSquad(silent: true);

    _squadCode = cleanCode;
    _isCreator = false;
    _isConnecting = true;
    _errorMessage = null;
    _syncedGameId = currentGameId;
    _syncedSubMode = currentSubMode;
    _syncedRoundSeed = currentSeed;

    final me = SkillSquadMember(
      playerId: _localPlayerId,
      name: _localName,
      avatar: _localAvatar,
      isCreator: false,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _members[_localPlayerId] = me;
    _liveFeedMessage = '🔗 Joined Friend Squad #$cleanCode! Syncing board...';
    notifyListeners();

    await _subscribeToChannel(cleanCode);

    // Announce join to existing squad members
    await _sendBroadcast('join_request', {
      'member': me.toJson(),
    });

    _isConnecting = false;
    notifyListeners();
    return true;
  }

  Future<void> _subscribeToChannel(String code) async {
    try {
      final client = Supabase.instance.client;
      final channel = client.channel(
        'skill_squad_$code',
        opts: const RealtimeChannelConfig(self: false),
      );

      channel
          .onBroadcast(
            event: 'join_request',
            callback: (payload) {
              _handleJoinRequest(payload);
            },
          )
          .onBroadcast(
            event: 'squad_snapshot',
            callback: (payload) {
              _handleSquadSnapshot(payload);
            },
          )
          .onBroadcast(
            event: 'squad_full',
            callback: (payload) {
              _handleSquadFull(payload);
            },
          )
          .onBroadcast(
            event: 'round_sync',
            callback: (payload) {
              _handleRoundSync(payload);
            },
          )
          .onBroadcast(
            event: 'member_update',
            callback: (payload) {
              _handleMemberUpdate(payload);
            },
          )
          .onBroadcast(
            event: 'member_left',
            callback: (payload) {
              _handleMemberLeft(payload);
            },
          )
          .onBroadcast(
            event: 'ball_placed',
            callback: (payload) {
              _handleRemoteBallPlaced(payload);
            },
          )
          .onBroadcast(
            event: 'ball_lifted',
            callback: (payload) {
              _handleRemoteBallLifted(payload);
            },
          )
          .subscribe();

      _channel = channel;
    } catch (e) {
      _errorMessage = 'Realtime connection note: playing in local code-seed mode.';
    }
  }

  void _handleJoinRequest(Map<String, dynamic> payload) {
    final rawMember = payload['member'];
    if (rawMember is! Map) return;
    final incoming = SkillSquadMember.fromJson(
      Map<String, dynamic>.from(rawMember),
    );
    if (incoming.playerId.isEmpty) return;

    // Enforce Max 5 Players (Creator + max 4 Friends)
    if (!_members.containsKey(incoming.playerId) &&
        _members.length >= maxPlayers) {
      if (_isCreator) {
        _sendBroadcast('squad_full', {
          'rejected_player_id': incoming.playerId,
          'max_players': maxPlayers,
        });
      }
      return;
    }

    _members[incoming.playerId] = incoming;
    _liveFeedMessage =
        '👋 ${incoming.avatar} ${incoming.name} joined the squad! (${_members.length}/$maxPlayers players)';
    notifyListeners();

    // Broadcast current squad state & deterministic round seed so the new friend gets the exact same board!
    _sendBroadcast('squad_snapshot', {
      'game_id': _syncedGameId,
      'sub_mode': _syncedSubMode,
      'round_seed': _syncedRoundSeed,
      'started_at_ms': _syncedStartedAtMs,
      'members': _members.values.map((m) => m.toJson()).toList(),
    });
  }

  void _handleSquadSnapshot(Map<String, dynamic> payload) {
    final rawMembers = payload['members'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is Map) {
          final m = SkillSquadMember.fromJson(Map<String, dynamic>.from(item));
          if (m.playerId.isNotEmpty &&
              (_members.containsKey(m.playerId) ||
                  _members.length < maxPlayers)) {
            // Preserve our own fresher local score if we already exist
            if (m.playerId != _localPlayerId ||
                !_members.containsKey(_localPlayerId)) {
              _members[m.playerId] = m;
            }
          }
        }
      }
    }

    final remoteGameId = payload['game_id']?.toString();
    final remoteSubMode = payload['sub_mode']?.toString();
    final remoteSeed = (payload['round_seed'] as num?)?.toInt();

    if (remoteGameId != null &&
        remoteSubMode != null &&
        remoteSeed != null &&
        (remoteGameId != _syncedGameId ||
            remoteSubMode != _syncedSubMode ||
            remoteSeed != _syncedRoundSeed)) {
      _syncedGameId = remoteGameId;
      _syncedSubMode = remoteSubMode;
      _syncedRoundSeed = remoteSeed;
      onRemoteRoundSync?.call(remoteGameId, remoteSubMode, remoteSeed, false);
    }
    notifyListeners();
  }

  void _handleSquadFull(Map<String, dynamic> payload) {
    final rejectedId = payload['rejected_player_id']?.toString();
    if (rejectedId == _localPlayerId) {
      leaveSquad(silent: true);
      _errorMessage =
          '🔒 That Friend Squad is full (Max 5 players: 1 creator + 4 friends on Free Plan).';
      notifyListeners();
    }
  }

  void _handleRoundSync(Map<String, dynamic> payload) {
    final remoteGameId = payload['game_id']?.toString() ?? _syncedGameId;
    final remoteSubMode = payload['sub_mode']?.toString() ?? _syncedSubMode;
    final remoteSeed =
        (payload['round_seed'] as num?)?.toInt() ?? _syncedRoundSeed;
    final autoStart = payload['auto_start'] == true;
    final senderName = payload['sender_name']?.toString() ?? 'Friend';

    _syncedGameId = remoteGameId;
    _syncedSubMode = remoteSubMode;
    _syncedRoundSeed = remoteSeed;
    remotePlacements.clear(); // new round from squad mate → reset all ball claims

    // Reset all members' round progress for the new card
    for (final key in _members.keys.toList()) {
      final m = _members[key]!;
      _members[key] = m.copyWith(
        score: 0,
        progress: 0,
        wrongCount: 0,
        reactionMs: 0,
        completed: false,
        lastEvent: null,
      );
    }

    _liveFeedMessage = autoStart
        ? '🚀 $senderName started the round! Go!'
        : '🔄 $senderName dealt a new shared card (Seed #$remoteSeed)!';
    onRemoteRoundSync?.call(remoteGameId, remoteSubMode, remoteSeed, autoStart);
    notifyListeners();
  }

  void _handleMemberUpdate(Map<String, dynamic> payload) {
    final rawMember = payload['member'];
    if (rawMember is! Map) return;
    final updated = SkillSquadMember.fromJson(
      Map<String, dynamic>.from(rawMember),
    );
    if (updated.playerId.isEmpty) return;
    if (!_members.containsKey(updated.playerId) &&
        _members.length >= maxPlayers) {
      return;
    }
    _members[updated.playerId] = updated;
    if (updated.lastEvent != null && updated.lastEvent!.isNotEmpty) {
      _liveFeedMessage = '${updated.avatar} ${updated.name}: ${updated.lastEvent}';
    }
    notifyListeners();
  }

  void _handleMemberLeft(Map<String, dynamic> payload) {
    final leftId = payload['player_id']?.toString();
    final leftName = payload['name']?.toString() ?? 'A friend';
    if (leftId != null && _members.remove(leftId) != null) {
      _liveFeedMessage = '👋 $leftName left the squad (${_members.length}/$maxPlayers).';
      notifyListeners();
    }
  }

  void _handleRemoteBallPlaced(Map<String, dynamic> payload) {
    final ball = (payload['ball'] as num?)?.toInt();
    final row = (payload['row'] as num?)?.toInt();
    final col = (payload['col'] as num?)?.toInt();
    final senderId = payload['sender_id']?.toString() ?? '';
    final playerName = payload['player_name']?.toString() ?? 'Friend';
    final playerAvatar = payload['player_avatar']?.toString() ?? '🎲';
    if (ball == null || row == null || col == null) return;
    if (senderId == _localPlayerId) return; // ignore own echoes (shouldn't happen since self:false)

    // If the same ball was placed elsewhere before, free the previous claim
    if (remotePlacements.containsKey(ball)) {
      remotePlacements.remove(ball);
    }
    remotePlacements[ball] = RemotePlacement(
      row: row,
      col: col,
      playerName: playerName,
      playerAvatar: playerAvatar,
    );
    onRemoteBallPlaced?.call(ball, row, col, playerName, playerAvatar);
    notifyListeners();
  }

  void _handleRemoteBallLifted(Map<String, dynamic> payload) {
    final ball = (payload['ball'] as num?)?.toInt();
    final senderId = payload['sender_id']?.toString() ?? '';
    if (ball == null) return;
    if (senderId == _localPlayerId) return;
    remotePlacements.remove(ball);
    onRemoteBallLifted?.call(ball);
    notifyListeners();
  }

  /// Broadcast that we placed [ball] at ([row], [col]) so squad mates can see it's claimed.
  void broadcastBallPlaced({
    required int ball,
    required int row,
    required int col,
  }) {
    if (!isInSquad) return;
    _sendBroadcast('ball_placed', {
      'ball': ball,
      'row': row,
      'col': col,
      'sender_id': _localPlayerId,
      'player_name': _localName,
      'player_avatar': _localAvatar,
    });
  }

  /// Broadcast that we lifted (moved) [ball] off its previous cell so squad mates free the claim.
  void broadcastBallLifted({required int ball}) {
    if (!isInSquad) return;
    _sendBroadcast('ball_lifted', {
      'ball': ball,
      'sender_id': _localPlayerId,
    });
  }

  /// Broadcasts a new round / game / subMode / start event to all friends in the squad.
  void broadcastRoundSync({
    required String gameId,
    required String subMode,
    required int roundSeed,
    bool autoStart = false,
  }) {
    _syncedGameId = gameId;
    _syncedSubMode = subMode;
    _syncedRoundSeed = roundSeed;
    remotePlacements.clear(); // new round → no stale squad claims

    for (final key in _members.keys.toList()) {
      final m = _members[key]!;
      _members[key] = m.copyWith(
        score: 0,
        progress: 0,
        wrongCount: 0,
        reactionMs: 0,
        completed: false,
        lastEvent: null,
      );
    }
    notifyListeners();

    if (!isInSquad) return;
    _sendBroadcast('round_sync', {
      'game_id': gameId,
      'sub_mode': subMode,
      'round_seed': roundSeed,
      'auto_start': autoStart,
      'sender_name': _localName,
    });
  }

  /// Updates our local player's live score/progress/DAB status and broadcasts it to our friends.
  void reportLocalProgress({
    required int score,
    required int progress,
    required int target,
    required int wrongCount,
    required int reactionMs,
    required bool completed,
    String? eventText,
  }) {
    final existing =
        _members[_localPlayerId] ??
        SkillSquadMember(
          playerId: _localPlayerId,
          name: _localName,
          avatar: _localAvatar,
          isCreator: _isCreator,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );

    final updated = existing.copyWith(
      score: score,
      progress: progress,
      target: target,
      wrongCount: wrongCount,
      reactionMs: reactionMs,
      completed: completed,
      lastEvent: eventText,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _members[_localPlayerId] = updated;
    if (eventText != null && eventText.isNotEmpty) {
      _liveFeedMessage = '${updated.avatar} You: $eventText';
    }
    notifyListeners();

    if (isInSquad) {
      _broadcastMemberUpdate(updated);
    }
  }

  void _broadcastMemberUpdate(SkillSquadMember member) {
    _sendBroadcast('member_update', {
      'member': member.toJson(),
    });
  }

  Future<void> _sendBroadcast(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: event, payload: payload);
    } catch (_) {}
  }

  Future<void> leaveSquad({bool silent = false}) async {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.sendBroadcastMessage(
          event: 'member_left',
          payload: {
            'player_id': _localPlayerId,
            'name': _localName,
          },
        );
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
    _squadCode = null;
    _isCreator = false;
    _isConnecting = false;
    _members.clear();
    if (!silent) {
      _liveFeedMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    leaveSquad(silent: true);
    super.dispose();
  }
}
