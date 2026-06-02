import 'package:cloud_firestore/cloud_firestore.dart';

class EventModel {
  final String id;
  final String title;
  final String description;
  final String location;
  final Timestamp eventDate;
  final Timestamp? endDate;
  final List<String> imageUrls;
  final String organizer;
  final String category;
  final String status; // draft / published / cancelled
  final String createdBy;
  final String createdByName;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  // ── Status constants ──────────────────────────────────────
  static const String statusDraft = 'draft';
  static const String statusPublished = 'published';
  static const String statusCancelled = 'cancelled';

  // ── Category constants ────────────────────────────────────
  static const String categoryGeneral = 'general';
  static const String categoryFundraiser = 'fundraiser';
  static const String categoryMeeting = 'meeting';
  static const String categoryReligious = 'religious';
  static const String categoryCommunity = 'community';
  static const List<String> categories = [
    categoryGeneral,
    categoryFundraiser,
    categoryMeeting,
    categoryReligious,
    categoryCommunity,
  ];

  static const int maxImages = 5;

  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.eventDate,
    this.endDate,
    required this.imageUrls,
    required this.organizer,
    required this.category,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    // Read the image gallery; fall back to the legacy single `imageUrl`.
    final raw = d['imageUrls'];
    List<String> images;
    if (raw is List) {
      images = raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } else if (d['imageUrl'] is String &&
        (d['imageUrl'] as String).isNotEmpty) {
      images = [d['imageUrl'] as String];
    } else {
      images = [];
    }

    return EventModel(
      id: doc.id,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      location: d['location'] as String? ?? '',
      eventDate: d['eventDate'] as Timestamp? ?? Timestamp.now(),
      endDate: d['endDate'] as Timestamp?,
      imageUrls: images,
      organizer: d['organizer'] as String? ?? '',
      category: d['category'] as String? ?? categoryGeneral,
      status: d['status'] as String? ?? statusDraft,
      createdBy: d['createdBy'] as String? ?? '',
      createdByName: d['createdByName'] as String? ?? '',
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: d['updatedAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'eventDate': eventDate,
      if (endDate != null) 'endDate': endDate,
      'imageUrls': imageUrls,
      'organizer': organizer,
      'category': category,
      'status': status,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  EventModel copyWith({
    String? title,
    String? description,
    String? location,
    Timestamp? eventDate,
    Timestamp? endDate,
    List<String>? imageUrls,
    String? organizer,
    String? category,
    String? status,
    Timestamp? updatedAt,
  }) {
    return EventModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      eventDate: eventDate ?? this.eventDate,
      endDate: endDate ?? this.endDate,
      imageUrls: imageUrls ?? this.imageUrls,
      organizer: organizer ?? this.organizer,
      category: category ?? this.category,
      status: status ?? this.status,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Computed ──────────────────────────────────────────────

  bool get isDraft => status == statusDraft;
  bool get isPublished => status == statusPublished;
  bool get isCancelled => status == statusCancelled;
  bool get isPast => eventDate.toDate().isBefore(DateTime.now());
  bool get hasImages => imageUrls.isNotEmpty;
  String? get coverImage => imageUrls.isNotEmpty ? imageUrls.first : null;
}
