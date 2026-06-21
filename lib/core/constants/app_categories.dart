/// Canonical product category list shared by add/edit product pages and any
/// category-based filtering UI. Defined here so the list lives in a single
/// source of truth instead of being duplicated per page.
class AppCategories {
  const AppCategories._();

  static const List<String> all = [
    'Dresses',
    'Tops',
    'Bottoms',
    'Outerwear',
    'Abayas',
    'Modest Wear',
    'Swimwear',
    'Activewear',
    'Loungewear',
    'Accessories',
    'Bags',
    'Shoes',
    'Jewellery',
    'Beauty',
    'Kids',
  ];
}
