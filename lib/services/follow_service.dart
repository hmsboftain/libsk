import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  // Live follow status for the follow button
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
