class KosModel {
  final int id;
  final Map<String, dynamic> raw;

  KosModel({
    required this.id,
    required this.raw,
  });

  String get name {
    final v = raw['name'] ??
        raw['nama'] ??
        raw['kos_name'] ??
        raw['nama_kos'] ??
        raw['title'];
    return (v ?? 'Kos #$id').toString();
  }

  String get address {
    final v = raw['address'] ??
        raw['alamat'] ??
        raw['location'] ??
        raw['lokasi'] ??
        raw['address_detail'];
    return (v ?? '').toString();
  }

  String get priceText {
    final candidates = <dynamic>[
      raw['price_per_month'],
      raw['pricePerMonth'],
      raw['monthly_price'],
      raw['price'],
      raw['rent_price'],
      raw['harga_per_bulan'],
      raw['harga'],
      raw['biaya'],
    ];

    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }

    return '';
  }

  factory KosModel.fromJson(Map<String, dynamic> json) {
    final dynamic idValue = json['id'] ?? json['kos_id'] ?? json['id_kos'];
    final int id =
        idValue is int ? idValue : int.tryParse(idValue?.toString() ?? '') ?? 0;

    return KosModel(
      id: id,
      raw: json,
    );
  }
}
