/// Étiquette d'affichage d'un nom avec un petit numéro de désambiguïsation
/// dérivé de l'id du compte — rien n'empêche deux utilisateurs de choisir
/// le même nom à l'inscription ; ce numéro permet de les distinguer dans
/// le répertoire, la liste de conversations et l'en-tête d'une
/// conversation.
///
/// Dérivé de l'id (déjà garanti unique), jamais stocké séparément : stable
/// pour un même compte, statistiquement distinct d'un autre compte (1
/// chance sur 10 000 qu'un DEUXIÈME compte tombe sur le même numéro —
/// largement suffisant pour désambiguïser visuellement deux homonymes,
/// pas une garantie cryptographique).
///
/// Le hash est fait à la main (jamais `String.hashCode`, dont Dart NE
/// garantit PAS la stabilité entre plateformes/versions du SDK — un même
/// compte afficherait un numéro différent sur le web vs Android, ou après
/// une mise à jour Flutter, ce qui serait très déroutant).
String userTag(String uid) {
  var hash = 5381;
  for (final codeUnit in uid.codeUnits) {
    hash = ((hash * 33) ^ codeUnit) & 0x7fffffff;
  }
  return (hash % 10000).toString().padLeft(4, '0');
}

/// Nom + numéro prêts à afficher, ex. "Jean Kabila #0472". `name` vide ->
/// "Utilisateur #...", jamais une étiquette vide.
String displayNameWithTag(String name, String uid) {
  final trimmed = name.trim();
  final label = trimmed.isEmpty ? 'Utilisateur' : trimmed;
  return '$label #${userTag(uid)}';
}
