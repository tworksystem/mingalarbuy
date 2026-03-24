class ProductReview {
  final String id;
  final String userId;
  final String productId;
  final String userName;
  final String userEmail;
  final String? userAvatar;
  final int rating;
  final String title;
  final String comment;
  final List<String> images;
  final bool isVerified;
  final bool isHelpful;
  final int helpfulCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;
  final Map<String, dynamic>? metadata;

  ProductReview({
    required this.id,
    required this.userId,
    required this.productId,
    required this.userName,
    required this.userEmail,
    required this.rating,
    required this.title,
    required this.comment,
    this.userAvatar,
    this.images = const [],
    this.isVerified = false,
    this.isHelpful = false,
    this.helpfulCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.notes,
    this.metadata,
  });

  // Get formatted rating
  String get formattedRating => '$rating.0';

  // Get star rating display
  String get starRating => '★' * rating + '☆' * (5 - rating);

  // Get time ago display
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  // Get helpful text
  String get helpfulText {
    if (helpfulCount == 0) return 'No helpful votes';
    if (helpfulCount == 1) return '1 person found this helpful';
    return '$helpfulCount people found this helpful';
  }

  // Validate review
  bool get isValid {
    return rating >= 1 &&
        rating <= 5 &&
        title.isNotEmpty &&
        comment.isNotEmpty &&
        comment.length >= 10;
  }

  // Get validation errors
  List<String> get validationErrors {
    List<String> errors = [];
    if (rating < 1 || rating > 5) {
      errors.add('Rating must be between 1 and 5');
    }
    if (title.isEmpty) {
      errors.add('Title is required');
    }
    if (comment.isEmpty) {
      errors.add('Comment is required');
    } else if (comment.length < 10) {
      errors.add('Comment must be at least 10 characters');
    }
    return errors;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'productId': productId,
      'userName': userName,
      'userEmail': userEmail,
      'userAvatar': userAvatar,
      'rating': rating,
      'title': title,
      'comment': comment,
      'images': images,
      'isVerified': isVerified,
      'isHelpful': isHelpful,
      'helpfulCount': helpfulCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'notes': notes,
      'metadata': metadata,
    };
  }

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    return ProductReview(
      id: json['id'],
      userId: json['userId'],
      productId: json['productId'],
      userName: json['userName'],
      userEmail: json['userEmail'],
      userAvatar: json['userAvatar'],
      rating: json['rating'],
      title: json['title'],
      comment: json['comment'],
      images: List<String>.from(json['images'] ?? []),
      isVerified: json['isVerified'] ?? false,
      isHelpful: json['isHelpful'] ?? false,
      helpfulCount: json['helpfulCount'] ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      notes: json['notes'],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }

  ProductReview copyWith({
    String? id,
    String? userId,
    String? productId,
    String? userName,
    String? userEmail,
    String? userAvatar,
    int? rating,
    String? title,
    String? comment,
    List<String>? images,
    bool? isVerified,
    bool? isHelpful,
    int? helpfulCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    Map<String, dynamic>? metadata,
  }) {
    return ProductReview(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      productId: productId ?? this.productId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      userAvatar: userAvatar ?? this.userAvatar,
      rating: rating ?? this.rating,
      title: title ?? this.title,
      comment: comment ?? this.comment,
      images: images ?? this.images,
      isVerified: isVerified ?? this.isVerified,
      isHelpful: isHelpful ?? this.isHelpful,
      helpfulCount: helpfulCount ?? this.helpfulCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductReview &&
        other.id == id &&
        other.userId == userId &&
        other.productId == productId;
  }

  @override
  int get hashCode => id.hashCode ^ userId.hashCode ^ productId.hashCode;

  @override
  String toString() {
    return 'ProductReview(id: $id, productId: $productId, rating: $rating, title: $title)';
  }
}

class ReviewSummary {
  final String productId;
  final double averageRating;
  final int totalReviews;
  final Map<int, int> ratingDistribution; // rating -> count
  final List<ProductReview> recentReviews;

  ReviewSummary({
    required this.productId,
    required this.averageRating,
    required this.totalReviews,
    required this.ratingDistribution,
    this.recentReviews = const [],
  });

  // Get formatted average rating
  String get formattedAverageRating => averageRating.toStringAsFixed(1);

  // Get percentage for each rating
  double getPercentageForRating(int rating) {
    if (totalReviews == 0) return 0.0;
    final count = ratingDistribution[rating] ?? 0;
    return (count / totalReviews) * 100;
  }

  // Get rating text
  String get ratingText {
    if (totalReviews == 0) return 'No reviews yet';
    if (totalReviews == 1) return '1 review';
    return '$totalReviews reviews';
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'averageRating': averageRating,
      'totalReviews': totalReviews,
      'ratingDistribution': ratingDistribution,
      'recentReviews': recentReviews.map((review) => review.toJson()).toList(),
    };
  }

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    return ReviewSummary(
      productId: json['productId'],
      averageRating: json['averageRating'].toDouble(),
      totalReviews: json['totalReviews'],
      ratingDistribution: Map<int, int>.from(json['ratingDistribution']),
      recentReviews: (json['recentReviews'] as List)
          .map((review) =>
              ProductReview.fromJson(review as Map<String, dynamic>))
          .toList(),
    );
  }
}
