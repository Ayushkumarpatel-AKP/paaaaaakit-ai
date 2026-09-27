import 'package:flutter/material.dart';

enum FoodCategory {
  snacks('Snacks', Icons.cookie_outlined),
  dairy('Dairy', Icons.water_drop_outlined),
  fruitsVegetables('Fruits & Vegetables', Icons.eco_outlined),
  meatSeafood('Meat & Seafood', Icons.restaurant_outlined),
  bakery('Bakery', Icons.cake_outlined),
  beverages('Beverages', Icons.local_drink_outlined),
  readyToEat('Ready-to-Eat', Icons.lunch_dining_outlined),
  grainsPulses('Grains & Pulses', Icons.grain_outlined),
  others('Others', Icons.category_outlined);

  final String label;
  final IconData icon;
  const FoodCategory(this.label, this.icon);
}

enum StorageType {
  ambient('Ambient (25°C)', Icons.wb_sunny_outlined),
  chilled('Chilled (4°C)', Icons.ac_unit_outlined),
  frozen('Frozen (-18°C)', Icons.severe_cold_outlined);

  final String label;
  final IconData icon;
  const StorageType(this.label, this.icon);
}

enum TransportCondition {
  normal('Normal', Icons.local_shipping_outlined),
  highTemp('High Temp', Icons.thermostat_outlined),
  highHumidity('High Humidity', Icons.water_outlined),
  longDistance('Long Distance', Icons.flight_takeoff_outlined);

  final String label;
  final IconData icon;
  const TransportCondition(this.label, this.icon);
}

class PackagingLayer {
  final String name;
  final int thicknessMicrons;
  final String role;
  final Color layerColor;
  final String materialDescription;

  const PackagingLayer({
    required this.name,
    required this.thicknessMicrons,
    required this.role,
    required this.layerColor,
    required this.materialDescription,
  });
}

class FoodProduct {
  final String id;
  final String name;
  final FoodCategory category;
  final String imageUrl;
  final double moistureContent;
  final double oilFatContent;
  final double phValue;
  final double waterActivity;
  final int defaultShelfLifeMonths;
  final List<PackagingLayer> recommendedLayers;
  final String otr; // Oxygen transmission rate
  final String wvtr; // Water vapor transmission rate
  final String totalThickness;
  final String sealability;
  final String mechanicalStrength;
  final String mapSuitability;
  final double matchScore;

  const FoodProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.moistureContent,
    required this.oilFatContent,
    required this.phValue,
    this.waterActivity = 0.4,
    required this.defaultShelfLifeMonths,
    required this.recommendedLayers,
    required this.otr,
    required this.wvtr,
    required this.totalThickness,
    required this.sealability,
    required this.mechanicalStrength,
    required this.mapSuitability,
    this.matchScore = 95.0,
  });
}

class SupplierItem {
  final String id;
  final String name;
  final String logoUrl;
  final String specialties;
  final String location;
  final String badge;
  final double rating;
  final String minOrder;

  const SupplierItem({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.specialties,
    required this.location,
    required this.badge,
    this.rating = 4.8,
    this.minOrder = '5,000 units',
  });
}

class AuditResult {
  final String id;
  final String title;
  final String imagePath;
  final String detectedMaterial;
  final int materialConfidence;
  final String sealIntegrity;
  final int sealPercentage;
  final String visibleDefects;
  final String leakageRisk;
  final String estimatedShelfLife;
  final String mfgDate;
  final String batchNumber;

  const AuditResult({
    required this.id,
    required this.title,
    required this.imagePath,
    required this.detectedMaterial,
    required this.materialConfidence,
    required this.sealIntegrity,
    required this.sealPercentage,
    required this.visibleDefects,
    required this.leakageRisk,
    required this.estimatedShelfLife,
    required this.mfgDate,
    required this.batchNumber,
  });
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool hasRecommendationCard;
  final String? cardTitle;
  final List<String>? bulletPoints;
  final String? cardImageUrl;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.hasRecommendationCard = false,
    this.cardTitle,
    this.bulletPoints,
    this.cardImageUrl,
  });
}
