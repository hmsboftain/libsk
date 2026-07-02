import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/analytics_service.dart';

class FollowService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _followingRef(String uid) {
    return _db.collection('users').doc(uid).collection('following');
  }

  // Follow — only writes to user's following subcollection.
  // The Cloud Function onFollowCreated handles incrementing followerCount.
  Future<void> follow(String boutiqueId) async {
    final uid = _uid;
    if (uid == null) return;
    await _followingRef(
      uid,
    ).doc(boutiqueId).set({'followedAt': FieldValue.serverTimestamp()});
  }

  // Unfollow — only deletes from user's following subcollection.
  // The Cloud Function onFollowDeleted handles decrementing followerCount.
  Future<void> unfollow(String boutiqueId) async {
    final uid = _uid;
    if (uid == null) return;
    await _followingRef(uid).doc(boutiqueId).delete();
  }

  // Live follow status for the follow button. Legacy single-listener mode used
  // by one-off placements (e.g. the storefront header); the feed reads follow
  // state from the shared FollowController instead.
  Stream<bool> isFollowing(String boutiqueId) {
    final uid = _uid;
    if (uid == null) return Stream.value(false);
    return _followingRef(
      uid,
    ).doc(boutiqueId).snapshots().map((doc) => doc.exists);
  }

  // List of boutique IDs the current user follows (used by feed)
  Future<List<String>> getFollowingIds() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _followingRef(uid).get();
    return snap.docs.map((d) => d.id).toList();
  }

  // Live follower count stream for boutique profile page
  Stream<int> followerCount(String boutiqueId) {
    return _db
        .collection('boutiques')
        .doc(boutiqueId)
        .snapshots()
        .map((doc) => (doc.data()?['followerCount'] as num?)?.toInt() ?? 0);
  }
}

/// Shared, feed-level follow state (audit finding 4.1).
///
/// Replaces the per-card `isFollowing()` snapshot listeners: the feed loads the
/// followed-boutique set ONCE via [load], and every [FollowButton] reads/writes
/// through this controller instead of each card opening its own Firestore
/// listener on `users/{uid}/following/*`. follow/unfollow is optimistic — local
/// state flips immediately, the write happens in the background, and a failure
/// rolls the local state back.
class FollowController extends ChangeNotifier {
  FollowController([FollowService? service])
      : _service = service ?? FollowService();

  final FollowService _service;
  final Set<String> _following = {};
  bool _loaded = false;

  bool get loaded => _loaded;
  bool isFollowing(String boutiqueId) => _following.contains(boutiqueId);

  /// One-time load of the user's followed boutique ids (single get, not a
  /// listener). Safe to call again (e.g. pull-to-refresh).
  Future<void> load() async {
    try {
      final ids = await _service.getFollowingIds();
      _following
        ..clear()
        ..addAll(ids);
    } catch (_) {
      // Guests / transient errors → treat as following nobody.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Optimistically toggles follow state for [boutiqueId], writing in the
  /// background and rolling back on failure.
  Future<void> toggle(String boutiqueId, String boutiqueName) async {
    final wasFollowing = _following.contains(boutiqueId);
    if (wasFollowing) {
      _following.remove(boutiqueId);
      AnalyticsService.instance.logBoutiqueUnfollow(boutiqueId);
    } else {
      _following.add(boutiqueId);
      AnalyticsService.instance.logBoutiqueFollow(boutiqueId, boutiqueName);
    }
    notifyListeners();

    try {
      if (wasFollowing) {
        await _service.unfollow(boutiqueId);
      } else {
        await _service.follow(boutiqueId);
      }
    } catch (_) {
      // Roll back the optimistic change on failure.
      if (wasFollowing) {
        _following.add(boutiqueId);
      } else {
        _following.remove(boutiqueId);
      }
      notifyListeners();
    }
  }
}
