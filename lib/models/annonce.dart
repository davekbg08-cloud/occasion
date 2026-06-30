class Annonce {
  const Annonce({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.currency = 'USD',
    required this.category,
    required this.userId,
    this.imageUrls = const <String>[],
    this.location,
    this.city = '',
    this.district = '',
    this.brand = '',
    this.model = '',
    this.year = 0,
    this.condition = '',
    this.phone = '',
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.views = 0,
    this.favoritesCount = 0,
    this.messagesCount = 0,
  });

  final String id;
  final String title;
  final String description;
  final double price;
  final String currency;
  final String category;
  final String userId;
  final List<String> imageUrls;
  final String? location;
  final String city;
  final String district;
  final String brand;
  final String model;
  final int year;
  final String condition;
  final String phone;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isActive;
  final int views;
  final int favoritesCount;
  final int messagesCount;

  factory Annonce.fromJson(Map<String, dynamic> json) {
    final status =
        json['statut'] as String? ??
        json['status'] as String? ??
        ((json['isActive'] as bool? ?? true) ? 'active' : 'inactive');
    final city = json['ville'] as String? ?? json['city'] as String? ?? '';
    final district =
        json['quartier'] as String? ?? json['district'] as String? ?? '';
    final fallbackLocation = [city, district]
        .where((part) => part.trim().isNotEmpty)
        .join(', ');

    return Annonce(
      id: json['id'] as String? ?? '',
      title: json['titre'] as String? ?? json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: _toDouble(json['prix'] ?? json['price']),
      currency:
          json['devise'] as String? ?? json['currency'] as String? ?? 'USD',
      category:
          json['categorie'] as String? ??
          json['category'] as String? ??
          'Divers',
      userId: json['vendeurId'] as String? ?? json['userId'] as String? ?? '',
      imageUrls:
          (json['images'] as List<dynamic>? ??
                  json['imageUrls'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      location:
          json['localisation'] as String? ??
          json['location'] as String? ??
          (fallbackLocation.isEmpty ? null : fallbackLocation),
      city: city,
      district: district,
      brand: json['marque'] as String? ?? json['brand'] as String? ?? '',
      model: json['modele'] as String? ?? json['model'] as String? ?? '',
      year: _toInt(json['annee'] ?? json['year']),
      condition: json['etat'] as String? ?? json['condition'] as String? ?? '',
      phone: json['telephone'] as String? ?? json['phone'] as String? ?? '',
      status: status,
      createdAt: _toDateTime(json['dateCreation'] ?? json['createdAt']),
      updatedAt: _toDateTime(json['dateModification'] ?? json['updatedAt']),
      isActive: status == 'active' || status == 'actif',
      views: _toInt(json['vues'] ?? json['views']),
      favoritesCount: _toInt(json['favoris'] ?? json['favoritesCount']),
      messagesCount: _toInt(
        json['messagesCount'] ??
            json['nombreMessages'] ??
            json['messages'] ??
            0,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titre': title.trim(),
      'description': description.trim(),
      'prix': price,
      'devise': currency.trim(),
      'categorie': category.trim(),
      'marque': brand.trim(),
      'modele': model.trim(),
      'annee': year,
      'etat': condition.trim(),
      'localisation': location?.trim() ?? '',
      'ville': city.trim(),
      'quartier': district.trim(),
      'vendeurId': userId.trim(),
      'telephone': phone.trim(),
      'images': imageUrls,
      'favoris': favoritesCount,
      'vues': views,
      'messagesCount': messagesCount,
      'statut': status.trim().isEmpty
          ? (isActive ? 'active' : 'inactive')
          : status.trim(),
      'dateCreation': createdAt,
      'dateModification': updatedAt,
    };
  }

  void validate() {
    final errors = <String>[];
    if (title.trim().isEmpty) errors.add('titre obligatoire');
    if (description.trim().isEmpty) errors.add('description obligatoire');
    if (price < 0) errors.add('prix invalide');
    if (currency.trim().isEmpty) errors.add('devise obligatoire');
    if (category.trim().isEmpty) errors.add('categorie obligatoire');
    if (userId.trim().isEmpty) errors.add('vendeurId obligatoire');
    if (views < 0) errors.add('vues invalide');
    if (favoritesCount < 0) errors.add('favoris invalide');
    if (messagesCount < 0) errors.add('messages invalide');
    if (errors.isNotEmpty) {
      throw ArgumentError(errors.join(', '));
    }
  }

  Annonce copyWith({
    String? id,
    String? title,
    String? description,
    double? price,
    String? currency,
    String? category,
    String? userId,
    List<String>? imageUrls,
    String? location,
    String? city,
    String? district,
    String? brand,
    String? model,
    int? year,
    String? condition,
    String? phone,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    int? views,
    int? favoritesCount,
    int? messagesCount,
  }) {
    return Annonce(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      userId: userId ?? this.userId,
      imageUrls: imageUrls ?? this.imageUrls,
      location: location ?? this.location,
      city: city ?? this.city,
      district: district ?? this.district,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      condition: condition ?? this.condition,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      views: views ?? this.views,
      favoritesCount: favoritesCount ?? this.favoritesCount,
      messagesCount: messagesCount ?? this.messagesCount,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    try {
      return value.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
