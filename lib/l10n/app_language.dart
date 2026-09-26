import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Langue de l'interface (refonte : ouverture internationale).
///
/// Le français est la langue source : chaque texte de l'app est passé à
/// [tr], qui renvoie sa traduction anglaise si l'anglais est actif. Un
/// texte sans traduction reste simplement en français (aucun plantage).
class AppLanguage {
  AppLanguage._();

  static const _prefsKey = 'app_language';
  static const supported = ['fr', 'en'];

  /// Langue active, écoutée par la racine de l'app pour tout reconstruire.
  static final ValueNotifier<String> current = ValueNotifier<String>('fr');

  static bool get isEnglish => current.value == 'en';

  /// Choix enregistré, sinon langue du téléphone (anglais si le téléphone
  /// est en anglais, français dans tous les autres cas).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && supported.contains(saved)) {
        current.value = saved;
        return;
      }
    } catch (_) {
      // Préférences illisibles : on se rabat sur la langue du téléphone.
    }
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    current.value = device.languageCode == 'en' ? 'en' : 'fr';
  }

  static Future<void> set(String code) async {
    if (!supported.contains(code)) return;
    current.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
    } catch (_) {
      // Non bloquant : la langue reste active pour cette session.
    }
  }
}

/// Traduit un texte français de l'interface dans la langue active.
String tr(String french) {
  if (!AppLanguage.isEnglish) return french;
  return _english[french] ?? french;
}

@visibleForTesting
Map<String, String> get englishTranslations => _english;

const _english = <String, String>{
  "Numéro de reversement": "Payout number",
  "Indique le nom du titulaire du compte.": "Enter the account holder's name.",
  "Numéro de reversement enregistré.": "Payout number saved.",
  "L'argent de tes ventes payées par Mobile Money est envoyé sur ce numéro, après confirmation de réception par l'acheteur. Occasion retient une commission de 4 %.": "Money from your sales paid by Mobile Money is sent to this number once the buyer confirms receipt. Occasion keeps a 4% commission.",
  "Nom du titulaire du compte": "Account holder name",
  "Reversement envoyé": "Payout sent",
  "Vendeur payé.": "Seller paid.",
  "Reversement échoué.": "Payout failed.",
  "Reversement échoué": "Payout failed",
  "Reversement pawaPay en cours…": "pawaPay payout in progress…",
  "Reverser via pawaPay": "Pay out via pawaPay",
  "Déjà payé à la main": "Already paid manually",
  "Aucun numéro de reversement enregistré": "No payout number saved",
  "Payée · à livrer": "Paid · to deliver",
  "Livrée · reversement en attente": "Delivered · payout pending",
  "Reversée": "Paid out",
  "Litige": "Dispute",
  "Paiement en vérification": "Payment being verified",
  "En attente de paiement": "Awaiting payment",
  "Paiement échoué": "Payment failed",
  "Annulée": "Cancelled",
  "Remboursée": "Refunded",
  "acheteur": "buyer",
  "Abonnement vendeur": "Seller subscription",
  "Accueil": "Home",
  "Accès refusé ou erreur.": "Access denied or error.",
  "Accès réservé aux administrateurs.": "Administrators only.",
  "Achats": "Purchases",
  "Acheter": "Buy",
  "Acheteur": "Buyer",
  "Actif (visible des acheteurs)": "Active (visible to buyers)",
  "Actions conversation": "Conversation actions",
  "Administration": "Administration",
  "Administration paiements": "Payment administration",
  "Adresses de livraison": "Delivery addresses",
  "Ajouter": "Add",
  "Ajouter une description...": "Add a description...",
  "Ajoutez au moins une photo.": "Add at least one photo.",
  "Ajoutez l'indicatif international, par exemple +243.":
      "Add the international code, for example +243.",
  "Annonce": "Listing",
  "Annonce supprimée.": "Listing deleted.",
  "Annonces": "Listings",
  "Annonces inactives": "Inactive listings",
  "Annuler": "Cancel",
  "Annuler / rembourser": "Cancel / refund",
  "Au panier": "Add to cart",
  "Aucun abonnement pour les acheteurs": "No subscription for buyers",
  "Aucun avis pour le moment.": "No reviews yet.",
  "Aucun contenu pour le moment.": "No content yet.",
  "Aucun litige en cours.": "No open disputes.",
  "Aucun paiement à vérifier.": "No payments to verify.",
  "Aucun reversement en attente.": "No pending payouts.",
  "Aucun signalement ici.": "No reports here.",
  "Aucune annonce": "No listings",
  "Aucune annonce trouvée": "No listings found",
  "Aucune autre conversation.": "No other conversations.",
  "Aucune commande pour le moment.": "No orders yet.",
  "Aucune commande reçue pour le moment.": "No orders received yet.",
  "Aucune demande d'échange pour le moment.": "No exchange requests yet.",
  "Aucune demande.": "No requests.",
  "Aucune notification": "No notifications",
  "Aucune vente réglée pour le moment.": "No settled sales yet.",
  "Avis récents": "Recent reviews",
  "Balayez pour voir les autres photos": "Swipe to see more photos",
  "Bien reçu": "Received",
  "Bienvenue !": "Welcome!",
  "Bloquer": "Block",
  "Boutique": "Shop",
  "CNI, passeport ou carte d'electeur: prenez une photo nette.":
      "ID card, passport or voter card: take a clear photo.",
  "Cadeau envoyé": "Gift sent",
  "Catalogue indisponible.": "Catalog unavailable.",
  "Catégorie": "Category",
  "Ce vendeur n'a pas encore de cadeaux.": "This seller has no gifts yet.",
  "Cette action est irréversible": "This action cannot be undone",
  "Cette action retirera l’annonce de la vente.":
      "This will remove the listing from sale.",
  "Cette annonce est introuvable.": "This listing cannot be found.",
  "Changer image": "Change image",
  "Changer vidéo": "Change video",
  "Chercher": "Search",
  "Choisir depuis la galerie": "Choose from gallery",
  "Choisis ton opérateur Mobile Money.": "Choose your Mobile Money operator.",
  "Choisissez un message pour commencer :": "Pick a message to start:",
  "Choisissez une formule vendeur.": "Choose a seller plan.",
  "Code copié.": "Code copied.",
  "Code de parrainage (optionnel)": "Referral code (optional)",
  "Colle la référence de transaction reçue par SMS Orange Money.":
      "Paste the transaction reference from your Orange Money SMS.",
  "Commandes reçues": "Orders received",
  "Comment payer": "How to pay",
  "Commentaire (optionnel)": "Comment (optional)",
  "Compte": "Account",
  "Compte acheteur": "Buyer account",
  "Confirmer": "Confirm",
  "Confirmer la remise à zéro": "Confirm reset",
  "Connecte-toi avec ton compte vendeur.": "Sign in with your seller account.",
  "Connecte-toi pour enregistrer une recherche.": "Sign in to save a search.",
  "Connecte-toi pour voir tes commandes.": "Sign in to see your orders.",
  "Connectez-vous ou créez un compte pour continuer.":
      "Sign in or create an account to continue.",
  "Connectez-vous pour voir cette liste.": "Sign in to see this list.",
  "Connexion": "Sign in",
  "Contact vendeur": "Contact seller",
  "Contacter": "Contact",
  "Conversation indisponible.": "Conversation unavailable.",
  "Conversation supprimée.": "Conversation deleted.",
  "Conversations": "Conversations",
  "Copier": "Copy",
  "Coût en points": "Cost in points",
  "Créer un compte": "Create an account",
  "Créez votre compte en choisissant votre rôle":
      "Create your account by choosing your role",
  "Demande d'échange envoyée.": "Exchange request sent.",
  "Demandes d'échange": "Exchange requests",
  "Description": "Description",
  "Details supplementaires (facultatif)": "Additional details (optional)",
  "Devise": "Currency",
  "Disponible": "Available",
  "Débloquer": "Unblock",
  "Déconnexion": "Sign out",
  "Découvrir": "Discover",
  "Décris le problème (article non reçu, différent de l'annonce...)":
      "Describe the problem (item not received, different from the listing...)",
  "Déjà un compte ? ": "Already have an account? ",
  "E-mail": "Email",
  "Elle disparaîtra de votre liste de messages.":
      "It will disappear from your messages.",
  "En ligne": "Online",
  "En négociation": "Under negotiation",
  "English": "English",
  "Enregistrer": "Save",
  "Enregistrer cette recherche": "Save this search",
  "Entre un numero de telephone.": "Enter a phone number.",
  "Envoyer": "Send",
  "Envoyer l'avis": "Submit review",
  "Envoyer le signalement": "Send report",
  "Envoyer un selfie": "Send a selfie",
  "Envoyer une photo ou une vidéo": "Send a photo or video",
  "Favoris": "Favorites",
  "Filleuls inscrits": "Referrals signed up",
  "Filtrer par ville/quartier...": "Filter by city/district...",
  "Français": "Français",
  "Historique de vos demandes": "Your request history",
  "Historique des prix": "Price history",
  "ID de l'acheteur": "Buyer ID",
  "ID du vendeur": "Seller ID",
  "ID produit lié (optionnel)": "Linked product ID (optional)",
  "Image": "Image",
  "Impossible d'ouvrir cette conversation pour le moment.":
      "Unable to open this conversation right now.",
  "Impossible d'ouvrir cette conversation.":
      "Unable to open this conversation.",
  "Impossible de charger ce profil pour le moment.":
      "Unable to load this profile right now.",
  "Impossible de charger cette annonce.": "Unable to load this listing.",
  "Impossible de charger l'historique.": "Unable to load history.",
  "Impossible de charger le catalogue.": "Unable to load the catalog.",
  "Impossible de charger le tableau de bord vendeur.":
      "Unable to load the seller dashboard.",
  "Impossible de charger les annonces pour le moment.":
      "Unable to load listings right now.",
  "Impossible de charger les avis pour le moment.":
      "Unable to load reviews right now.",
  "Impossible de charger les commandes pour le moment.":
      "Unable to load orders right now.",
  "Impossible de charger les demandes.": "Unable to load requests.",
  "Impossible de charger les messages. Vérifiez votre connexion ou vos droits d’accès.":
      "Unable to load messages. Check your connection or access rights.",
  "Impossible de charger les notifications.": "Unable to load notifications.",
  "Impossible de charger les produits pour le moment.":
      "Unable to load products right now.",
  "Impossible de charger les statistiques.": "Unable to load statistics.",
  "Impossible de charger vos annonces pour le moment.":
      "Unable to load your listings right now.",
  "Impossible de charger vos points.": "Unable to load your points.",
  "Impossible de charger votre code de parrainage.":
      "Unable to load your referral code.",
  "Impossible de lire cette vidéo.": "Unable to play this video.",
  "Impossible de modifier l'état de la vente.":
      "Unable to change the sale status.",
  "Impossible de modifier le statut de l'annonce.":
      "Unable to change the listing status.",
  "Impossible de supprimer l'annonce.": "Unable to delete the listing.",
  "Indicatif non reconnu. Choisissez votre pays et vérifiez l'indicatif.":
      "Country code not recognized. Choose your country and check the code.",
  "Informations produit": "Product information",
  "Inscription": "Sign up",
  "Invitez vos proches sur Occasion": "Invite your friends to Occasion",
  "J'AI ENVOYÉ L'ARGENT": "I'VE SENT THE MONEY",
  "J'ai envoyé l'argent au vendeur": "I've sent the money to the seller",
  "Laisser un avis": "Leave a review",
  "Langue": "Language",
  "Les vendeurs publieront bientôt leurs articles.":
      "Sellers will post their items soon.",
  "Ma boutique": "My shop",
  "Marqué comme reversé.": "Marked as paid out.",
  "Merci ! Le vendeur va être payé.": "Thank you! The seller will be paid.",
  "Mes achats": "My purchases",
  "Mes alertes de recherche": "My search alerts",
  "Mes annonces": "My listings",
  "Mes commandes": "My orders",
  "Mes points de fidélité": "My loyalty points",
  "Message": "Message",
  "Messages": "Messages",
  "Modifier": "Edit",
  "Modifier la photo": "Change photo",
  "Mon Panier": "My Cart",
  "Mon catalogue de cadeaux": "My gift catalog",
  "Mon compte": "My account",
  "Mon panier": "My cart",
  "Mon statut": "My status",
  "Montant total": "Total amount",
  "Mot de passe": "Password",
  "Motif": "Reason",
  "Moyens de paiement": "Payment methods",
  "Nom": "Name",
  "Notifications": "Notifications",
  "Nouveau statut": "New status",
  "Numero valide.": "Valid number.",
  "Numéro Mobile Money": "Mobile Money number",
  "Numéro de contact": "Contact number",
  "Numéro de téléphone": "Phone number",
  "Orange Money manuel": "Orange Money (manual)",
  "Ouvrir les réglages": "Open settings",
  "Paiement": "Payment",
  "Paiement Mobile Money": "Mobile Money payment",
  "Paiement confirmé.": "Payment confirmed.",
  "Paiement rejeté.": "Payment rejected.",
  "Paiement reçu ! Ta commande est confirmée.":
      "Payment received! Your order is confirmed.",
  "Paiements Orange Money à vérifier": "Orange Money payments to verify",
  "Paramètres": "Settings",
  "Paramètres et confidentialité": "Settings and privacy",
  "Parrainage": "Referrals",
  "Partager": "Share",
  "Partager infos utiles": "Share useful info",
  "Pas encore de conversation": "No conversations yet",
  "Passer à la caisse": "Checkout",
  "Payez après vérification": "Pay after checking",
  "Pays du numéro": "Number's country",
  "Photo de profil mise à jour.": "Profile photo updated.",
  "Photo depuis la galerie": "Photo from gallery",
  "Photos": "Photos",
  "Placez le document ici": "Place the document here",
  "Plus tard": "Later",
  "Points fidélité": "Loyalty points",
  "Points gagnés": "Points earned",
  "Politique de confidentialité": "Privacy policy",
  "Pourquoi signalez-vous ce contenu ?": "Why are you reporting this content?",
  "Prendre une photo": "Take a photo",
  "Prix": "Price",
  "Prix et localisation": "Price and location",
  "Prix invalide.": "Invalid price.",
  "Profil": "Profile",
  "Profil du vendeur": "Seller profile",
  "Publication": "Publishing",
  "Publier": "Publish",
  "Publier le premier article": "Post the first item",
  "Publier un statut": "Post a status",
  "Publier une annonce": "Post a listing",
  "Quartier": "District",
  "Recherche enregistrée. Tu seras notifié des nouvelles annonces correspondantes.":
      "Search saved. You'll be notified of new matching listings.",
  "Rechercher": "Search",
  "Rechercher une annonce...": "Search listings...",
  "Reconnexion nécessaire": "Please sign in again",
  "Refuser": "Decline",
  "Rejeter": "Reject",
  "Relancer la camera": "Restart camera",
  "Remettre à zéro": "Reset",
  "Remise à zéro des points": "Points reset",
  "Remise à zéro des points (exceptionnelle)": "Points reset (exceptional)",
  "Renouvellement vendeur": "Seller renewal",
  "Retirer le filtre ville": "Remove city filter",
  "Retour": "Back",
  "Retour à l'accueil": "Back to home",
  "Revenu": "Income",
  "Revenus": "Income",
  "Reverser au vendeur": "Pay out to seller",
  "Récompenses": "Rewards",
  "Réessayer": "Retry",
  "Référence de transaction (SMS Orange Money)":
      "Transaction reference (Orange Money SMS)",
  "Résoudre": "Resolve",
  "Scanner document": "Scan document",
  "Se connecter": "Sign in",
  "Seuls les vendeurs peuvent publier une annonce.":
      "Only sellers can post listings.",
  "Signalements": "Reports",
  "Signaler ou bloquer": "Report or block",
  "Signaler un problème": "Report a problem",
  "Solde remis à zéro.": "Balance reset.",
  "Statistiques": "Statistics",
  "Statut de publication": "Publishing status",
  "Suppression impossible.": "Unable to delete.",
  "Supprimer": "Delete",
  "Supprimer cette alerte": "Delete this alert",
  "Supprimer cette annonce ?": "Delete this listing?",
  "Supprimer conversation": "Delete conversation",
  "Supprimer définitivement mon compte": "Permanently delete my account",
  "Supprimer la conversation ?": "Delete this conversation?",
  "Supprimer mon compte": "Delete my account",
  "Sélectionnez un média": "Select a media file",
  "Tapez SUPPRIMER pour confirmer :": "Type SUPPRIMER to confirm:",
  "Titre": "Title",
  "Ton abonnement vendeur n'est pas actif. Active-le pour publier.":
      "Your seller subscription isn't active. Activate it to publish.",
  "Ton opérateur": "Your operator",
  "Total :": "Total:",
  "Tout": "All",
  "Tout marquer comme lu": "Mark all as read",
  "Transférer vers...": "Forward to...",
  "Transféré": "Forwarded",
  "Téléphone": "Phone",
  "Téléphone vérifié": "Verified phone",
  "Utilisateur débloqué": "User unblocked",
  "Utilisateurs bloqués": "Blocked users",
  "Vendeur": "Seller",
  "Vendeur introuvable.": "Seller not found.",
  "Vendeur vérifié": "Verified seller",
  "Vendre": "Sell",
  "Vendu": "Sold",
  "Ventes": "Sales",
  "Vidéo": "Video",
  "Vidéo depuis la galerie": "Video from gallery",
  "Ville": "City",
  "Voir ma page vendeur": "View my seller page",
  "Vos adresses de livraison apparaîtront ici.":
      "Your delivery addresses will appear here.",
  "Vos annonces favorites apparaîtront ici.":
      "Your favorite listings will appear here.",
  "Vos annonces publiées apparaîtront ici.":
      "Your published listings will appear here.",
  "Vos revenus vendeur apparaîtront ici.":
      "Your seller income will appear here.",
  "Vos soldes par vendeur": "Your balances by seller",
  "Votre code": "Your code",
  "Votre compte acheteur est gratuit. Vous ne payez pas d'abonnement mensuel.":
      "Your buyer account is free. You don't pay a monthly subscription.",
  "Votre panier est vide": "Your cart is empty",
  "Vous devez être connecté pour envoyer un message.":
      "You must be signed in to send a message.",
  "Vous n'avez bloqué personne pour le moment.":
      "You haven't blocked anyone yet.",
  "Vous pouvez publier quelques annonces selon la configuration gratuite. L'abonnement vendeur servira aux volumes plus élevés et aux options avancées.":
      "You can post a few listings with the free plan. The seller subscription is for higher volumes and advanced options.",
  "Vues": "Views",
  "Vérifier mon abonnement": "Check my subscription",
  "Échanger": "Redeem",
  "Échec de l'enregistrement.": "Saving failed.",
  "Échec de l'enregistrement. Réessaie.": "Saving failed. Try again.",
  "Échec de l'envoi — Réessayer": "Sending failed — Retry",
  "Échec de la confirmation.": "Confirmation failed.",
  "Échec de la confirmation. Réessaie.": "Confirmation failed. Try again.",
  "Échec du rejet.": "Rejection failed.",
  "Échec du signalement. Réessaie.": "Report failed. Try again.",
  "Échec. Réessaie.": "Failed. Try again.",
  "Écrire un message...": "Write a message...",
  "État": "Condition",
  "État de la vente": "Sale status",
};
