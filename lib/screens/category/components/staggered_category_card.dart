import 'package:ecommerce_int2/models/category.dart' as models;
import 'package:ecommerce_int2/screens/category/category_products_page.dart';
import 'package:flutter/material.dart';

class CategoryCard extends StatelessWidget {
  final Color begin;
  final Color end;
  final String categoryName;
  final String assetPath;
  final VoidCallback? onTap;

  CategoryCard({super.key, 
    required this.controller,
    required this.begin,
    required this.end,
    required this.categoryName,
    required this.assetPath,
    this.onTap,
  })  : height = Tween<double>(begin: 150, end: 250.0).animate(
          CurvedAnimation(
            parent: controller,
            curve: Interval(
              0.0,
              0.300,
              curve: Curves.ease,
            ),
          ),
        ),
        itemHeight = Tween<double>(begin: 0, end: 150.0).animate(
          CurvedAnimation(
            parent: controller,
            curve: Interval(
              0.0,
              0.300,
              curve: Curves.ease,
            ),
          ),
        );

  final Animation<double> controller;
  final Animation<double> height;
  final Animation<double> itemHeight;

  // Helper method to build category image (supports both network URLs and local assets)
  Widget _buildCategoryImage(String imagePath) {
    // Check if imagePath is a URL (starts with http) or a local asset
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      // Load network image
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to default asset if network image fails
          return Image.asset(
            'assets/jeans_5.png',
            fit: BoxFit.contain,
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
      );
    } else {
      // Load local asset
      return Image.asset(
        imagePath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to default asset if specified asset doesn't exist
          return Image.asset(
            'assets/jeans_5.png',
            fit: BoxFit.contain,
          );
        },
      );
    }
  }

  // This function is called each time the controller "ticks" a new frame.
  // When it runs, all of the animation's values will have been
  // updated to reflect the controller's current value.
  Widget _buildAnimation(BuildContext context, Widget? child) {
    return Material(
      color: Colors.transparent,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        onTap: onTap,
        child: Container(
          height: height.value,
          width: MediaQuery.of(context).size.width,
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [begin, end],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: const BorderRadius.all(Radius.circular(10))),
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Align(
                  alignment: const Alignment(-1, 0),
                  child: Text(
                    categoryName,
                    style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  )),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    height: itemHeight.value,
                    child: _buildCategoryImage(assetPath),
                  ),
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(24))),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'View more',
                      style: TextStyle(color: end, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      builder: _buildAnimation,
      animation: controller,
    );
  }
}

class StaggeredCardCard extends StatefulWidget {
  final Color begin;
  final Color end;
  final String categoryName;
  final String assetPath;
  final models.Category? category;

  const StaggeredCardCard({super.key, 
    required this.begin,
    required this.end,
    required this.categoryName,
    required this.assetPath,
    this.category,
  });

  @override
  _StaggeredCardCardState createState() => _StaggeredCardCardState();
}

class _StaggeredCardCardState extends State<StaggeredCardCard>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  bool isActive = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);
  }

  Future<void> _playAnimation() async {
    try {
      await _controller.forward().orCancel;
    } on TickerCanceled {
      // the animation got canceled, probably because we were disposed
    }
  }

  Future<void> _reverseAnimation() async {
    try {
      await _controller.reverse().orCancel;
    } on TickerCanceled {
      // the animation got canceled, probably because we were disposed
    }
  }


  void _handleTap(BuildContext context) {
    if (isActive) {
      isActive = !isActive;
      _reverseAnimation();
    } else {
      isActive = !isActive;
      _playAnimation();
    }

    final targetCategory = widget.category ??
        models.Category(
          widget.begin,
          widget.end,
          widget.categoryName,
          widget.assetPath,
          id: null,
          slug: null,
        );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryProductsPage(category: targetCategory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CategoryCard(
      controller: _controller.view,
      categoryName: widget.categoryName,
      begin: widget.begin,
      end: widget.end,
      assetPath: widget.assetPath,
      onTap: () => _handleTap(context),
    );
  }
}

