import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/review.dart';

class ReviewProvider with ChangeNotifier {
  List<ProductReview> _reviews = [];
  bool _isLoading = false;
  String? _errorMessage;
  static const String _reviewsKey = 'product_reviews';

  // Getters
  List<ProductReview> get reviews => List.unmodifiable(_reviews);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasReviews => _reviews.isNotEmpty;

  // Get reviews by product
  List<ProductReview> getReviewsByProduct(String productId) {
    return _reviews.where((review) => review.productId == productId).toList();
  }

  // Get reviews by user
  List<ProductReview> getReviewsByUser(String userId) {
    return _reviews.where((review) => review.userId == userId).toList();
  }

  // Get reviews by rating
  List<ProductReview> getReviewsByRating(int rating) {
    return _reviews.where((review) => review.rating == rating).toList();
  }

  // Get verified reviews
  List<ProductReview> get verifiedReviews =>
      _reviews.where((review) => review.isVerified).toList();

  // Get helpful reviews
  List<ProductReview> get helpfulReviews =>
      _reviews.where((review) => review.isHelpful).toList();

  ReviewProvider() {
    _loadReviewsFromStorage();
  }

  /// Load reviews from SharedPreferences
  Future<void> _loadReviewsFromStorage() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final reviewsJson = prefs.getString(_reviewsKey);

      if (reviewsJson != null) {
        final List<dynamic> reviewsData = json.decode(reviewsJson);
        _reviews = reviewsData
            .map((review) =>
                ProductReview.fromJson(review as Map<String, dynamic>))
            .toList();
        print(
            'DEBUG: Reviews loaded from storage - ${_reviews.length} reviews');
      }
    } catch (e) {
      print('Error loading reviews from storage: $e');
      _setError('Failed to load reviews');
    } finally {
      _setLoading(false);
    }
  }

  /// Save reviews to SharedPreferences
  Future<void> _saveReviewsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reviewsJson =
          json.encode(_reviews.map((review) => review.toJson()).toList());
      await prefs.setString(_reviewsKey, reviewsJson);
      print('DEBUG: Reviews saved to storage - ${_reviews.length} reviews');
    } catch (e) {
      print('Error saving reviews to storage: $e');
    }
  }

  /// Add new review
  Future<ProductReview?> addReview({
    required String userId,
    required String productId,
    required String userName,
    required String userEmail,
    required int rating,
    required String title,
    required String comment,
    String? userAvatar,
    List<String> images = const [],
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Generate review ID
      final reviewId = 'REV-${DateTime.now().millisecondsSinceEpoch}';

      // Create review
      final review = ProductReview(
        id: reviewId,
        userId: userId,
        productId: productId,
        userName: userName,
        userEmail: userEmail,
        userAvatar: userAvatar,
        rating: rating,
        title: title,
        comment: comment,
        images: images,
        isVerified: false, // Can be set to true by admin
        isHelpful: false,
        helpfulCount: 0,
        createdAt: DateTime.now(),
        notes: notes,
        metadata: metadata,
      );

      // Validate review
      if (!review.isValid) {
        _setError('Invalid review: ${review.validationErrors.join(', ')}');
        return null;
      }

      // Check if user already reviewed this product
      final existingReview = _reviews.firstWhere(
        (r) => r.userId == userId && r.productId == productId,
        orElse: () => ProductReview(
          id: '',
          userId: '',
          productId: '',
          userName: '',
          userEmail: '',
          rating: 0,
          title: '',
          comment: '',
          createdAt: DateTime.now(),
        ),
      );

      if (existingReview.id.isNotEmpty) {
        _setError('You have already reviewed this product');
        return null;
      }

      // Add to reviews list
      _reviews.insert(0, review); // Add to beginning for newest first
      await _saveReviewsToStorage();
      notifyListeners();

      print('DEBUG: Review added - $reviewId');
      return review;
    } catch (e) {
      print('Error adding review: $e');
      _setError('Failed to add review: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Update existing review
  Future<ProductReview?> updateReview({
    required String reviewId,
    int? rating,
    String? title,
    String? comment,
    List<String>? images,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final reviewIndex =
          _reviews.indexWhere((review) => review.id == reviewId);
      if (reviewIndex == -1) {
        _setError('Review not found');
        return null;
      }

      final existingReview = _reviews[reviewIndex];
      final updatedReview = existingReview.copyWith(
        rating: rating ?? existingReview.rating,
        title: title ?? existingReview.title,
        comment: comment ?? existingReview.comment,
        images: images ?? existingReview.images,
        updatedAt: DateTime.now(),
        notes: notes ?? existingReview.notes,
        metadata: metadata ?? existingReview.metadata,
      );

      // Validate updated review
      if (!updatedReview.isValid) {
        _setError(
            'Invalid review: ${updatedReview.validationErrors.join(', ')}');
        return null;
      }

      _reviews[reviewIndex] = updatedReview;
      await _saveReviewsToStorage();
      notifyListeners();

      print('DEBUG: Review updated - $reviewId');
      return updatedReview;
    } catch (e) {
      print('Error updating review: $e');
      _setError('Failed to update review: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Delete review
  Future<bool> deleteReview(String reviewId) async {
    _setLoading(true);
    _clearError();

    try {
      final reviewIndex =
          _reviews.indexWhere((review) => review.id == reviewId);
      if (reviewIndex == -1) {
        _setError('Review not found');
        return false;
      }

      _reviews.removeAt(reviewIndex);
      await _saveReviewsToStorage();
      notifyListeners();

      print('DEBUG: Review deleted - $reviewId');
      return true;
    } catch (e) {
      print('Error deleting review: $e');
      _setError('Failed to delete review');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Mark review as helpful
  Future<bool> markReviewAsHelpful(String reviewId) async {
    _setLoading(true);
    _clearError();

    try {
      final reviewIndex =
          _reviews.indexWhere((review) => review.id == reviewId);
      if (reviewIndex == -1) {
        _setError('Review not found');
        return false;
      }

      final review = _reviews[reviewIndex];
      final updatedReview = review.copyWith(
        isHelpful: !review.isHelpful,
        helpfulCount: review.isHelpful
            ? review.helpfulCount - 1
            : review.helpfulCount + 1,
        updatedAt: DateTime.now(),
      );

      _reviews[reviewIndex] = updatedReview;
      await _saveReviewsToStorage();
      notifyListeners();

      print('DEBUG: Review helpful status updated - $reviewId');
      return true;
    } catch (e) {
      print('Error updating review helpful status: $e');
      _setError('Failed to update review helpful status');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Get review summary for product
  ReviewSummary getReviewSummary(String productId) {
    final productReviews = getReviewsByProduct(productId);

    if (productReviews.isEmpty) {
      return ReviewSummary(
        productId: productId,
        averageRating: 0.0,
        totalReviews: 0,
        ratingDistribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
        recentReviews: [],
      );
    }

    // Calculate average rating
    final totalRating =
        productReviews.fold(0, (sum, review) => sum + review.rating);
    final averageRating = totalRating / productReviews.length;

    // Calculate rating distribution
    final ratingDistribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final review in productReviews) {
      ratingDistribution[review.rating] =
          (ratingDistribution[review.rating] ?? 0) + 1;
    }

    // Get recent reviews (last 5)
    final recentReviews = productReviews.take(5).toList();

    return ReviewSummary(
      productId: productId,
      averageRating: averageRating,
      totalReviews: productReviews.length,
      ratingDistribution: ratingDistribution,
      recentReviews: recentReviews,
    );
  }

  /// Get review by ID
  ProductReview? getReviewById(String reviewId) {
    try {
      return _reviews.firstWhere((review) => review.id == reviewId);
    } catch (e) {
      return null;
    }
  }

  /// Check if user can review product
  bool canUserReviewProduct(String userId, String productId) {
    return !_reviews.any(
        (review) => review.userId == userId && review.productId == productId);
  }

  /// Search reviews
  List<ProductReview> searchReviews(String query) {
    if (query.isEmpty) return _reviews;

    final lowercaseQuery = query.toLowerCase();
    return _reviews.where((review) {
      return review.title.toLowerCase().contains(lowercaseQuery) ||
          review.comment.toLowerCase().contains(lowercaseQuery) ||
          review.userName.toLowerCase().contains(lowercaseQuery) ||
          review.productId.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Clear all reviews (for testing)
  Future<void> clearAllReviews() async {
    _setLoading(true);
    try {
      _reviews.clear();
      await _saveReviewsToStorage();
      notifyListeners();
      print('DEBUG: All reviews cleared');
    } catch (e) {
      print('Error clearing reviews: $e');
      _setError('Failed to clear reviews');
    } finally {
      _setLoading(false);
    }
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error message
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Clear error message
  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Force refresh reviews from storage
  Future<void> refreshReviews() async {
    await _loadReviewsFromStorage();
  }
}
