import 'package:cloud_firestore/cloud_firestore.dart';

typedef FirestoreMap = Map<String, dynamic>;

DateTime _readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

String _string(FirestoreMap map, String key, {String fallback = ''}) {
  final value = map[key];
  return value is String ? value : fallback;
}

int _int(FirestoreMap map, String key) {
  final value = map[key];
  return value is num ? value.toInt() : 0;
}

bool _bool(FirestoreMap map, String key, {bool fallback = false}) {
  final value = map[key];
  return value is bool ? value : fallback;
}

List<String> _strings(FirestoreMap map, String key) {
  final value = map[key];
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList();
}

void _require(List<String> errors, String label, String value) {
  if (value.trim().isEmpty) errors.add('$label obligatoire');
}

void _throwIfInvalid(List<String> errors) {
  if (errors.isNotEmpty) throw ArgumentError(errors.join(', '));
}

class UtilisateurOccasion {
  const UtilisateurOccasion({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.email,
    required this.photo,
    required this.ville,
    required this.pays,
    required this.dateCreation,
    required this.typeCompte,
    required this.estVerifie,
    required this.derniereConnexion,
  });

  final String id;
  final String nom;
  final String prenom;
  final String telephone;
  final String email;
  final String photo;
  final String ville;
  final String pays;
  final DateTime dateCreation;
  final String typeCompte;
  final bool estVerifie;
  final DateTime derniereConnexion;

  factory UtilisateurOccasion.fromSnapshot(
    DocumentSnapshot<FirestoreMap> snapshot,
  ) {
    return UtilisateurOccasion.fromMap(snapshot.data() ?? {}, id: snapshot.id);
  }

  factory UtilisateurOccasion.fromMap(FirestoreMap map, {String? id}) {
    return UtilisateurOccasion(
      id: id ?? _string(map, 'id'),
      nom: _string(map, 'nom'),
      prenom: _string(map, 'prenom'),
      telephone: _string(map, 'telephone'),
      email: _string(map, 'email'),
      photo: _string(map, 'photo'),
      ville: _string(map, 'ville'),
      pays: _string(map, 'pays'),
      dateCreation: _readDate(map['dateCreation']),
      typeCompte: _string(map, 'typeCompte', fallback: 'acheteur'),
      estVerifie: _bool(map, 'estVerifie'),
      derniereConnexion: _readDate(map['derniereConnexion']),
    );
  }

  FirestoreMap toFirestore({bool serverTimestamps = false}) => {
    'id': id,
    'nom': nom.trim(),
    'prenom': prenom.trim(),
    'telephone': telephone.trim(),
    'email': email.trim(),
    'photo': photo.trim(),
    'ville': ville.trim(),
    'pays': pays.trim(),
    'dateCreation': serverTimestamps
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(dateCreation),
    'typeCompte': typeCompte.trim(),
    'estVerifie': estVerifie,
    'derniereConnexion': serverTimestamps
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(derniereConnexion),
  };

  void validate() {
    final errors = <String>[];
    _require(errors, 'nom', nom);
    _require(errors, 'telephone', telephone);
    _require(errors, 'typeCompte', typeCompte);
    if (email.isNotEmpty && !email.contains('@')) errors.add('email invalide');
    _throwIfInvalid(errors);
  }
}

class MessageOccasion {
  const MessageOccasion({
    required this.id,
    required this.conversationId,
    required this.expediteurId,
    required this.destinataireId,
    required this.contenu,
    required this.lu,
    required this.dateEnvoi,
  });

  final String id;
  final String conversationId;
  final String expediteurId;
  final String destinataireId;
  final String contenu;
  final bool lu;
  final DateTime dateEnvoi;

  factory MessageOccasion.fromSnapshot(
    DocumentSnapshot<FirestoreMap> snapshot,
  ) {
    return MessageOccasion.fromMap(snapshot.data() ?? {}, id: snapshot.id);
  }

  factory MessageOccasion.fromMap(FirestoreMap map, {String? id}) {
    return MessageOccasion(
      id: id ?? _string(map, 'id'),
      conversationId: _string(map, 'conversationId'),
      expediteurId: _string(map, 'expediteurId'),
      destinataireId: _string(map, 'destinataireId'),
      contenu: _string(map, 'contenu'),
      lu: _bool(map, 'lu'),
      dateEnvoi: _readDate(map['dateEnvoi']),
    );
  }

  FirestoreMap toFirestore({bool serverTimestamp = false}) => {
    'id': id,
    'conversationId': conversationId.trim(),
    'expediteurId': expediteurId.trim(),
    'destinataireId': destinataireId.trim(),
    'contenu': contenu.trim(),
    'lu': lu,
    'dateEnvoi': serverTimestamp
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(dateEnvoi),
  };

  void validate() {
    final errors = <String>[];
    _require(errors, 'conversationId', conversationId);
    _require(errors, 'expediteurId', expediteurId);
    _require(errors, 'destinataireId', destinataireId);
    _require(errors, 'contenu', contenu);
    _throwIfInvalid(errors);
  }
}

class ConversationOccasion {
  const ConversationOccasion({
    required this.id,
    required this.participants,
    required this.dernierMessage,
    required this.dateDernierMessage,
  });

  final String id;
  final List<String> participants;
  final String dernierMessage;
  final DateTime dateDernierMessage;

  factory ConversationOccasion.fromSnapshot(
    DocumentSnapshot<FirestoreMap> snapshot,
  ) {
    return ConversationOccasion.fromMap(snapshot.data() ?? {}, id: snapshot.id);
  }

  factory ConversationOccasion.fromMap(FirestoreMap map, {String? id}) {
    return ConversationOccasion(
      id: id ?? _string(map, 'id'),
      participants: _strings(map, 'participants'),
      dernierMessage: _string(map, 'dernierMessage'),
      dateDernierMessage: _readDate(map['dateDernierMessage']),
    );
  }

  FirestoreMap toFirestore({bool serverTimestamp = false}) => {
    'id': id,
    'participants': participants,
    'dernierMessage': dernierMessage.trim(),
    'dateDernierMessage': serverTimestamp
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(dateDernierMessage),
  };

  void validate() {
    final errors = <String>[];
    if (participants.length < 2) errors.add('participants insuffisants');
    _throwIfInvalid(errors);
  }
}

class SignalementOccasion {
  const SignalementOccasion({
    required this.id,
    required this.annonceId,
    required this.utilisateurId,
    required this.motif,
    required this.description,
    required this.date,
    required this.statut,
  });

  final String id;
  final String annonceId;
  final String utilisateurId;
  final String motif;
  final String description;
  final DateTime date;
  final String statut;

  factory SignalementOccasion.fromSnapshot(
    DocumentSnapshot<FirestoreMap> snapshot,
  ) {
    return SignalementOccasion.fromMap(snapshot.data() ?? {}, id: snapshot.id);
  }

  factory SignalementOccasion.fromMap(FirestoreMap map, {String? id}) {
    return SignalementOccasion(
      id: id ?? _string(map, 'id'),
      annonceId: _string(map, 'annonceId'),
      utilisateurId: _string(map, 'utilisateurId'),
      motif: _string(map, 'motif'),
      description: _string(map, 'description'),
      date: _readDate(map['date']),
      statut: _string(map, 'statut', fallback: 'nouveau'),
    );
  }

  FirestoreMap toFirestore({bool serverTimestamp = false}) => {
    'id': id,
    'annonceId': annonceId.trim(),
    'utilisateurId': utilisateurId.trim(),
    'motif': motif.trim(),
    'description': description.trim(),
    'date': serverTimestamp
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(date),
    'statut': statut.trim(),
  };

  void validate() {
    final errors = <String>[];
    _require(errors, 'annonceId', annonceId);
    _require(errors, 'utilisateurId', utilisateurId);
    _require(errors, 'motif', motif);
    _throwIfInvalid(errors);
  }
}

class CategorieOccasion {
  const CategorieOccasion({
    required this.id,
    required this.nom,
    required this.icone,
    required this.ordre,
  });

  final String id;
  final String nom;
  final String icone;
  final int ordre;

  factory CategorieOccasion.fromSnapshot(
    DocumentSnapshot<FirestoreMap> snapshot,
  ) {
    return CategorieOccasion.fromMap(snapshot.data() ?? {}, id: snapshot.id);
  }

  factory CategorieOccasion.fromMap(FirestoreMap map, {String? id}) {
    return CategorieOccasion(
      id: id ?? _string(map, 'id'),
      nom: _string(map, 'nom'),
      icone: _string(map, 'icone'),
      ordre: _int(map, 'ordre'),
    );
  }

  FirestoreMap toFirestore() => {
    'id': id,
    'nom': nom.trim(),
    'icone': icone.trim(),
    'ordre': ordre,
  };

  void validate() {
    final errors = <String>[];
    _require(errors, 'nom', nom);
    if (ordre < 0) errors.add('ordre invalide');
    _throwIfInvalid(errors);
  }
}

class NotificationOccasion {
  const NotificationOccasion({
    required this.id,
    required this.utilisateurId,
    required this.titre,
    required this.message,
    required this.lu,
    required this.date,
  });

  final String id;
  final String utilisateurId;
  final String titre;
  final String message;
  final bool lu;
  final DateTime date;

  factory NotificationOccasion.fromSnapshot(
    DocumentSnapshot<FirestoreMap> snapshot,
  ) {
    return NotificationOccasion.fromMap(snapshot.data() ?? {}, id: snapshot.id);
  }

  factory NotificationOccasion.fromMap(FirestoreMap map, {String? id}) {
    return NotificationOccasion(
      id: id ?? _string(map, 'id'),
      utilisateurId: _string(map, 'utilisateurId'),
      titre: _string(map, 'titre'),
      message: _string(map, 'message'),
      lu: _bool(map, 'lu'),
      date: _readDate(map['date']),
    );
  }

  FirestoreMap toFirestore({bool serverTimestamp = false}) => {
    'id': id,
    'utilisateurId': utilisateurId.trim(),
    'titre': titre.trim(),
    'message': message.trim(),
    'lu': lu,
    'date': serverTimestamp
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(date),
  };

  void validate() {
    final errors = <String>[];
    _require(errors, 'utilisateurId', utilisateurId);
    _require(errors, 'titre', titre);
    _require(errors, 'message', message);
    _throwIfInvalid(errors);
  }
}
