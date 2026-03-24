/// Page Content Model
/// Represents dynamic page content fetched from backend
class PageContent {
  final String title;
  final String content; // HTML content
  final String slug;
  final String lastModified;

  const PageContent({
    required this.title,
    required this.content,
    required this.slug,
    required this.lastModified,
  });

  factory PageContent.fromJson(Map<String, dynamic> json) {
    return PageContent(
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      slug: json['slug'] ?? '',
      lastModified: json['last_modified'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'slug': slug,
      'last_modified': lastModified,
    };
  }
}

/// Page List Item Model (for page listing)
class PageListItem {
  final int id;
  final String title;
  final String slug;
  final Map<String, dynamic>? meta;
  final int displayOrder;
  final String lastModified;

  const PageListItem({
    required this.id,
    required this.title,
    required this.slug,
    this.meta,
    required this.displayOrder,
    required this.lastModified,
  });

  factory PageListItem.fromJson(Map<String, dynamic> json) {
    return PageListItem(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      slug: json['slug'] ?? '',
      meta: json['meta'] != null ? Map<String, dynamic>.from(json['meta'] as Map) : null,
      displayOrder: json['display_order'] ?? 0,
      lastModified: json['last_modified'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'slug': slug,
      'meta': meta,
      'display_order': displayOrder,
      'last_modified': lastModified,
    };
  }
}

/// FAQ Item Model
class FaqItem {
  final int id;
  final String question;
  final String answer; // HTML content
  final int order;

  const FaqItem({
    required this.id,
    required this.question,
    required this.answer,
    required this.order,
  });

  factory FaqItem.fromJson(Map<String, dynamic> json) {
    return FaqItem(
      id: json['id'] ?? 0,
      question: json['question'] ?? '',
      answer: json['answer'] ?? '',
      order: json['order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'answer': answer,
      'order': order,
    };
  }
}

/// About Us Content Model
/// Represents structured About Us content fetched from backend
class AboutUsContent {
  final String companyName;
  final String tagline;
  final String subtitle;
  final String logoUrl;
  final String aboutBody1;
  final String aboutBody2;
  final String mission;
  final String vision;
  final String email;
  final String phone;
  final String address;
  final String version;

  const AboutUsContent({
    required this.companyName,
    required this.tagline,
    required this.subtitle,
    required this.logoUrl,
    required this.aboutBody1,
    required this.aboutBody2,
    required this.mission,
    required this.vision,
    required this.email,
    required this.phone,
    required this.address,
    required this.version,
  });

  factory AboutUsContent.fromJson(Map<String, dynamic> json) {
    return AboutUsContent(
      companyName: json['company_name'] ?? 'PLANETmm',
      tagline: json['tagline'] ?? 'Pansy & Lincoln',
      subtitle: json['subtitle'] ?? 'All-in-One Network Myanmar',
      logoUrl: json['logo_url'] ?? '',
      aboutBody1: json['about_body_1'] ?? '',
      aboutBody2: json['about_body_2'] ?? '',
      mission: json['mission'] ?? '',
      vision: json['vision'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? '',
      version: json['version'] ?? '1.0.2',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'company_name': companyName,
      'tagline': tagline,
      'subtitle': subtitle,
      'logo_url': logoUrl,
      'about_body_1': aboutBody1,
      'about_body_2': aboutBody2,
      'mission': mission,
      'vision': vision,
      'email': email,
      'phone': phone,
      'address': address,
      'version': version,
    };
  }
}

