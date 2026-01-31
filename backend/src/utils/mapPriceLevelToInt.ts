export function mapPriceLevelToInt(priceLevel: string): number | null {
  switch (priceLevel) {
    case 'PRICE_LEVEL_UNSPECIFIED':
      return null;
    case 'PRICE_LEVEL_FREE':
      return 0;
    case 'PRICE_LEVEL_INEXPENSIVE':
      return 1;
    case 'PRICE_LEVEL_MODERATE':
      return 2;
    case 'PRICE_LEVEL_EXPENSIVE':
    case 'PRICE_LEVEL_VERY_EXPENSIVE':
      return 3;
    default:
      return null;
  }
}
