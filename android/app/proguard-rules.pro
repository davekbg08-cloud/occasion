# google_mlkit_text_recognition référence les variantes optionnelles du
# reconnaisseur de texte (chinois, devanagari, japonais, coréen) que le
# projet n'inclut pas comme dépendances (seul le latin est utilisé). R8
# échoue sinon en mode release au lieu de simplement les ignorer.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
