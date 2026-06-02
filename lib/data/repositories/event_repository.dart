import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../models/event_model.dart';
import '../../core/constants/app_constants.dart';

class EventRepository {
  final _col =
      FirebaseFirestore.instance.collection(AppConstants.eventsCollection);

  // ── Read ──────────────────────────────────────────────────

  /// Published events, newest event date first. Member-facing.
  Stream<List<EventModel>> streamPublished() {
    return _col
        .where('status', isEqualTo: EventModel.statusPublished)
        .orderBy('eventDate', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());
  }

  /// Every event regardless of status. Admin-facing.
  Stream<List<EventModel>> streamAll() {
    return _col
        .orderBy('eventDate', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map((d) => EventModel.fromFirestore(d)).toList());
  }

  Stream<EventModel?> streamOne(String id) {
    return _col
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? EventModel.fromFirestore(d) : null);
  }

  // ── Write ─────────────────────────────────────────────────

  Future<String> createEvent({
    required String title,
    required String description,
    required String location,
    required DateTime eventDate,
    DateTime? endDate,
    List<String> imageUrls = const [],
    String organizer = '',
    String category = EventModel.categoryGeneral,
    required String status,
    required String createdBy,
    required String createdByName,
  }) async {
    final now = Timestamp.now();
    final data = EventModel(
      id: '',
      title: title,
      description: description,
      location: location,
      eventDate: Timestamp.fromDate(eventDate),
      endDate: endDate != null ? Timestamp.fromDate(endDate) : null,
      imageUrls: imageUrls,
      organizer: organizer,
      category: category,
      status: status,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: now,
      updatedAt: now,
    );
    final doc = await _col.add(data.toFirestore());
    return doc.id;
  }

  Future<void> updateEvent(String id, Map<String, dynamic> fields) async {
    await _col.doc(id).update({
      ...fields,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> deleteEvent(String id) async {
    await _col.doc(id).delete();
  }

  // ── Storage ───────────────────────────────────────────────

  Future<String> uploadImage(XFile file, String uid) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref('events/$uid/$stamp.jpg');
    await ref.putFile(File(file.path));
    return ref.getDownloadURL();
  }

  /// Uploads each file sequentially and returns their download URLs in order.
  Future<List<String>> uploadImages(List<XFile> files, String uid) async {
    final urls = <String>[];
    for (final f in files) {
      urls.add(await uploadImage(f, uid));
    }
    return urls;
  }
}
