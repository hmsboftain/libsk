/// Canonical product category list shared by add/edit product pages and any
/// category-based filtering UI. Defined here so the list lives in a single
/// source of truth instead of being duplicated per page.
class AppCategories {
  const AppCategories._();

  static const List<String> all = [
    'Abaya',
    'Blazers',
    'Blouses & Shirts',
    'Casual Wear',
    'Coats',
    'Dresses',
    "Dra'a",
    'Gowns',
    'Jackets',
    'Jumpsuits',
    'Office Attire',
    'Pants',
    'Shoes',
    'Skirts',
    'Tops',
  ];
}
