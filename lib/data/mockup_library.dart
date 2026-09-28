import '../models/food_item.dart';

/// A single 3D packaging mockup shipped with the app.
class PackagingMockup {
  /// Stable identifier used to keep the selection across rebuilds.
  final String id;

  /// Human readable name shown on the mockup picker.
  final String label;

  /// Bundled `.glb` asset path.
  final String assetPath;

  /// Product family this shape belongs to ('chips', 'milk', ...).
  final String family;

  const PackagingMockup({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.family,
  });
}

/// The mockups that ship with the app, grouped by the product family they
/// represent. The customizer only ever offers the group that matches the
/// product being engineered — a potato chip product never sees milk cartons.
class MockupLibrary {
  MockupLibrary._();

  static const List<PackagingMockup> chips = [
    PackagingMockup(
      id: 'chips_packet',
      label: 'Chips Packet',
      assetPath: 'assets/mockups/chips/chips_packet.glb',
      family: 'chips',
    ),
    PackagingMockup(
      id: 'sealed_food_pouch',
      label: 'Sealed Food Pouch',
      assetPath: 'assets/mockups/chips/sealed_food_pouch.glb',
      family: 'chips',
    ),
    PackagingMockup(
      id: 'small_snack_pack',
      label: 'Small Snack Pack',
      assetPath: 'assets/mockups/chips/small_snack_pack.glb',
      family: 'chips',
    ),
  ];

  static const List<PackagingMockup> milk = [
    PackagingMockup(
      id: 'tetra_pack',
      label: 'Tetra Pack',
      assetPath: 'assets/mockups/milk/tetra_pack.glb',
      family: 'milk',
    ),
    PackagingMockup(
      id: 'drinking_yogurt_bottle',
      label: 'Drinking Yogurt Bottle',
      assetPath: 'assets/mockups/milk/drinking_yogurt_bottle.glb',
      family: 'milk',
    ),
  ];

  /// Every mockup in the catalogue. Used as the fallback for categories that do
  /// not have a dedicated shape yet, so the picker is never empty.
  static const List<PackagingMockup> all = [...chips, ...milk];

  /// The mockup family that best represents a food category.
  static List<PackagingMockup> forCategory(FoodCategory category) {
    switch (category) {
      case FoodCategory.snacks:
        return chips;
      case FoodCategory.dairy:
      case FoodCategory.beverages:
        return milk;
      case FoodCategory.fruitsVegetables:
      case FoodCategory.meatSeafood:
      case FoodCategory.bakery:
      case FoodCategory.readyToEat:
      case FoodCategory.grainsPulses:
      case FoodCategory.others:
        return all;
    }
  }

  /// The mockups offered for a specific product. Falls back to the whole
  /// catalogue when no product has been selected yet.
  static List<PackagingMockup> forProduct(FoodProduct? product) {
    if (product == null) return all;
    return forCategory(product.category);
  }
}
