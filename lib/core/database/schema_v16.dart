const schemaV16 = <String>[
  'ALTER TABLE credit_cards ADD COLUMN color_argb INTEGER CHECK(color_argb IS NULL OR (typeof(color_argb)=\'integer\' AND color_argb BETWEEN 4278190080 AND 4294967295))',
];
