from __future__ import annotations

import json
from pathlib import Path


OUT_PATH = Path(
    "/Users/aris/Documents/VoiceProject/Zphyr/Evals/datasets/raw/patch/.tmp_round5/agent_e_email_prose_punctuation.jsonl"
)


rows: list[dict[str, str]] = []


def add(subcategory: str, raw: str, expected: str, notes: str) -> None:
    if not raw or not expected or not notes:
        raise ValueError("raw, expected and notes must be non-empty")
    if "<think>" in raw or "</think>" in raw or "<think>" in expected or "</think>" in expected:
        raise ValueError("forbidden tag found")
    rows.append(
        {
            "id": "",
            "category": "round5_patch",
            "subcategory": subcategory,
            "raw": raw,
            "expected": expected,
            "language": "fr",
            "notes": notes,
        }
    )


def build_email_body() -> None:
    confirmations = [
        "la réunion de cadrage est déplacée à jeudi matin",
        "le devis corrigé est en pièce jointe",
        "les accès temporaires restent actifs jusqu'à lundi",
        "le compte rendu partira avant dix-huit heures",
        "la version signée du contrat est disponible",
        "le lien de visioconférence a été mis à jour",
        "la facture validée part aujourd'hui",
        "le dossier complet est prêt pour relecture",
        "la proposition commerciale tient compte de vos remarques",
        "le planning révisé inclut la phase de tests",
    ]
    for text in confirmations:
        add(
            "email_body",
            f"bonjour je vous confirme que {text}",
            f"Bonjour, je vous confirme que {text}.",
            "Ajoute la virgule de salutation et la ponctuation d'un message de suivi.",
        )

    attachments = [
        "le devis mis à jour",
        "le bon de commande signé",
        "la synthèse de l'atelier",
        "la feuille de route du trimestre",
        "les accès de test",
        "le lien du dossier partagé",
        "la facture rectifiée",
        "le support de présentation",
        "le compte rendu validé",
        "la version commentée du contrat",
    ]
    for text in attachments:
        add(
            "email_body",
            f"comme convenu je vous envoie {text}",
            f"Comme convenu, je vous envoie {text}.",
            "Ajoute la virgule après l'amorce et clôt la phrase sans réécrire le contenu.",
        )

    receipts = [
        "votre bon pour accord",
        "les pièces demandées",
        "votre retour sur le planning",
        "la confirmation de présence",
        "les éléments techniques",
        "la version finale du devis",
        "les accès administrateur",
        "le bordereau signé",
        "la demande de modification",
        "votre message de relance",
    ]
    for text in receipts:
        add(
            "email_body",
            f"merci pour votre message nous avons bien reçu {text}",
            f"Merci pour votre message. Nous avons bien reçu {text}.",
            "Scinde naturellement le message en deux phrases courtes.",
        )

    enclosed = [
        "les documents demandés pour le dossier",
        "la convention signée",
        "la dernière version du cahier des charges",
        "le procès-verbal de recette",
        "les justificatifs de paiement",
        "la proposition consolidée",
        "le tableau récapitulatif",
        "les annexes mentionnées lors de l'appel",
        "la note de cadrage",
        "le formulaire complété",
    ]
    for text in enclosed:
        add(
            "email_body",
            f"veuillez trouver ci-joint {text}",
            f"Veuillez trouver ci-joint {text}.",
            "Ajoute la ponctuation finale d'une formule d'envoi standard.",
        )

    followups = [
        "le calendrier actualisé",
        "la liste des points ouverts",
        "le lien vers la démonstration",
        "le récapitulatif des décisions",
        "la version prête à valider",
        "le document de passation",
        "la trame de l'atelier",
        "le tableau de suivi",
        "la proposition corrigée",
        "le support revu ce matin",
    ]
    for text in followups:
        add(
            "email_body",
            f"à la suite de notre appel je vous partage {text}",
            f"À la suite de notre appel, je vous partage {text}.",
            "Met en forme une ouverture d'email usuelle avec la virgule attendue.",
        )

    caveats = [
        "le paiement devrait apparaître demain",
        "le bon de livraison est complet",
        "le créneau de mardi reste disponible",
        "le lot trois peut partir aujourd'hui",
        "la version transmise hier est la bonne",
        "le lien partagé ce matin reste valide",
        "le document signé couvre bien l'ensemble du périmètre",
        "le devis rectifié inclut la remise",
        "la formation peut être maintenue vendredi",
        "la pièce jointe contient bien les deux annexes",
    ]
    for text in caveats:
        add(
            "email_body",
            f"sauf erreur de ma part {text}",
            f"Sauf erreur de ma part, {text}.",
            "Ajoute la virgule après une réserve introductive sans alourdir la phrase.",
        )

    callbacks = [
        "j'ai l'accord définitif du service juridique",
        "nous recevons la confirmation du client",
        "le transporteur nous transmet l'horaire exact",
        "la direction valide la dernière estimation",
        "j'obtiens la version signée",
        "nous clôturons les derniers ajustements",
        "l'équipe support nous renvoie le ticket consolidé",
        "le fournisseur confirme la disponibilité",
        "nous avons le retour du partenaire",
        "la pièce jointe est accessible de votre côté",
    ]
    for text in callbacks:
        add(
            "email_body",
            f"je reviens vers vous dès que {text}",
            f"Je reviens vers vous dès que {text}.",
            "Conserve la formulation telle quelle et applique seulement la ponctuation attendue.",
        )


def build_short_sentence() -> None:
    groups = [
        (
            "c'est noté",
            [
                "",
                " pour demain",
                " pour la réunion",
                " pour le devis",
                " pour la validation",
                " pour la relance",
                " pour le rendez-vous",
                " pour l'envoi",
                " pour la démo",
                " pour la version finale",
            ],
            "Ajoute uniquement la majuscule et le point sur une phrase très courte.",
        ),
        (
            "on avance",
            [
                " demain",
                " comme prévu",
                " sur ce point",
                " sur la version B",
                " avec ce créneau",
                " après validation",
                " sur le même plan",
                " côté support",
                " côté planning",
                " sans changement",
            ],
            "Garde une formulation brève et ajoute seulement la ponctuation finale.",
        ),
        (
            "le lien",
            [
                " fonctionne",
                " est valide",
                " est à jour",
                " est le bon",
                " reste actif",
                " a bien été partagé",
                " est accessible",
                " est toujours disponible",
                " s'ouvre correctement",
                " est dans mon message précédent",
            ],
            "Stabilise une phrase courte sans la reformuler.",
        ),
        (
            "je valide",
            [
                " la version finale",
                " le dernier devis",
                " ce créneau",
                " l'envoi de ce soir",
                " le document signé",
                " la relecture",
                " la réunion de jeudi",
                " la proposition corrigée",
                " la diffusion interne",
                " le plan d'action",
            ],
            "Nettoie seulement la casse initiale et la ponctuation.",
        ),
        (
            "tout est",
            [
                " prêt",
                " bouclé",
                " validé",
                " envoyé",
                " confirmé",
                " en ordre",
                " aligné",
                " planifié",
                " calé",
                " transmis",
            ],
            "Reste sur une correction minimale pour un message très court.",
        ),
    ]

    for base, suffixes, note in groups:
        for suffix in suffixes:
            raw = f"{base}{suffix}".strip()
            expected = raw[0].upper() + raw[1:] + "."
            add("short_sentence", raw, expected, note)


def build_filler_removal() -> None:
    send_items = [
        "le devis cet après-midi",
        "la version corrigée avant midi",
        "le lien de réunion dans cinq minutes",
        "le tableau final en fin de journée",
        "la convention signée juste après l'appel",
        "le compte rendu ce soir",
        "les accès temporaires avant quatorze heures",
        "la réponse complète demain matin",
        "la note de cadrage avant validation",
        "la facture rectifiée dans l'heure",
    ]
    for text in send_items:
        add(
            "filler_removal",
            f"euh je vous envoie {text}",
            f"Je vous envoie {text}.",
            "Supprime un filler d'attaque clairement disfluent et garde le reste intact.",
        )

    status_items = [
        "le dossier est complet",
        "la pièce jointe est bien partie",
        "la salle est réservée",
        "le bon de commande est signé",
        "la dernière version est la bonne",
        "le paiement est confirmé",
        "la mise à jour est en cours",
        "le rendez-vous est maintenu",
        "la relance est prête",
        "le support est disponible",
    ]
    for text in status_items:
        add(
            "filler_removal",
            f"alors {text}",
            f"{text[0].upper() + text[1:]}.",
            "Retire un amorçage oral en tête de phrase sans autre réécriture.",
        )

    decisions = [
        "on maintient le créneau de jeudi",
        "on décale la démo à quinze heures",
        "on garde la version courte",
        "on confirme le rendez-vous client",
        "on clôture le sujet ce soir",
        "on envoie le lot demain matin",
        "on valide le visuel final",
        "on garde la même introduction",
        "on repousse la réunion à lundi",
        "on repart sur le planning initial",
    ]
    for text in decisions:
        add(
            "filler_removal",
            f"bon {text}",
            f"{text[0].upper() + text[1:]}.",
            "Supprime un marqueur oral initial et conserve la décision telle quelle.",
        )

    confirmations = [
        "la réservation pour mardi",
        "la livraison de la maquette",
        "l'envoi du contrat",
        "la présence de Julie",
        "la date de soutenance",
        "la diffusion du compte rendu",
        "l'accès au dossier partagé",
        "la mise en production",
        "la clôture du ticket",
        "le point de suivi de demain",
    ]
    for text in confirmations:
        add(
            "filler_removal",
            f"du coup je confirme {text}",
            f"Je confirme {text}.",
            "Retire un connecteur conversationnel en tête et ponctue simplement.",
        )

    returns = [
        "nous avons bien reçu votre accord",
        "nous avons le fichier signé",
        "nous gardons la version envoyée ce matin",
        "nous pouvons avancer sans attente supplémentaire",
        "nous avons tout ce qu'il faut pour finaliser",
        "nous transmettons la synthèse demain",
        "nous reprenons le sujet après déjeuner",
        "nous avons corrigé le point bloquant",
        "nous tenons le délai annoncé",
        "nous passons au lot suivant",
    ]
    for text in returns:
        add(
            "filler_removal",
            f"eh bien {text}",
            f"{text[0].upper() + text[1:]}.",
            "Supprime un filler oral au début sans changer le message professionnel.",
        )

    call_backs = [
        "je reviens vers vous avant midi",
        "je reviens vers vous avec la version relue",
        "je reviens vers vous dès que j'ai le retour",
        "je reviens vers vous après validation interne",
        "je reviens vers vous ce soir avec le détail",
        "je reviens vers vous demain pour confirmer",
        "je reviens vers vous avec le bon lien",
        "je reviens vers vous après le point équipe",
        "je reviens vers vous une fois le devis signé",
        "je reviens vers vous quand tout est prêt",
    ]
    for text in call_backs:
        add(
            "filler_removal",
            f"hum {text}",
            f"{text[0].upper() + text[1:]}.",
            "Nettoie un filler hésitant en tête de phrase et laisse le reste inchangé.",
        )


def build_spoken_restart() -> None:
    restart_sets = [
        (
            [
                ("je vous envoie demain", "je vous l'envoie ce soir"),
                ("on maintient vendredi", "on maintient jeudi matin"),
                ("je joins le contrat", "je joins la dernière version du contrat"),
                ("la réunion est à seize heures", "la réunion est à quinze heures trente"),
                ("je vous rappelle après déjeuner", "je vous rappelle avant midi"),
                ("on valide la version A", "on valide la version B"),
                ("je transfère le dossier complet", "je transfère seulement le dossier signé"),
                ("on part sur l'option longue", "on part sur l'option courte"),
                ("je vous renvoie le tableau demain", "je vous renvoie le tableau dans l'heure"),
                ("le point support reste lundi", "le point support passe à mardi"),
            ],
            "enfin",
            "spoken_restart",
            "Garde la reprise explicite après « enfin » et supprime la première tentative.",
        ),
        (
            [
                ("je vous envoie le lien public", "je vous envoie le lien privé"),
                ("la facture est partie hier", "la facture part aujourd'hui"),
                ("on clôture le sujet maintenant", "on clôture le sujet après validation"),
                ("je vous appelle cet après-midi", "je vous appelle en fin de matinée"),
                ("la formation commence jeudi", "la formation commence vendredi"),
                ("je laisse Julie en copie", "je laisse Marc en copie"),
                ("on garde la salle du quatrième", "on garde la salle du troisième"),
                ("je vous partage le dossier complet", "je vous partage seulement le dossier final"),
                ("on garde le créneau de dix heures", "on garde le créneau de onze heures"),
                ("je confirme l'adresse précédente", "je confirme la nouvelle adresse"),
            ],
            "pardon",
            "spoken_restart",
            "Nettoie une autocorrection explicite introduite par « pardon ».",
        ),
        (
            [
                ("la démo aura lieu mardi", "la démo aura lieu mercredi"),
                ("je vous transmets la version courte", "je vous transmets la version complète"),
                ("on envoie trois exemplaires", "on envoie deux exemplaires"),
                ("la réunion durera trente minutes", "la réunion durera quarante-cinq minutes"),
                ("je vous rappelle demain", "je vous rappelle lundi"),
                ("on garde le devis de février", "on garde le devis de mars"),
                ("je laisse la section ouverte", "je laisse la section masquée"),
                ("la note part au client", "la note part en interne"),
                ("on valide la date du six", "on valide la date du huit"),
                ("je vous transfère les annexes", "je vous transfère uniquement l'annexe deux"),
            ],
            "je veux dire",
            "spoken_restart",
            "Conserve uniquement la formulation corrigée après la reprise parlée.",
        ),
        (
            [
                ("on se voit à neuf heures", "on se voit à dix heures"),
                ("je vous confirme le lot un", "je vous confirme le lot deux"),
                ("la réunion sera courte", "la réunion sera plus longue que prévu"),
                ("je prends en charge l'introduction", "je prends en charge la conclusion"),
                ("on garde le canal mail", "on garde le canal téléphone"),
                ("je vous envoie le PDF", "je vous envoie le fichier Word"),
                ("la facture porte le mauvais montant", "la facture porte le bon montant"),
                ("on publie ce soir", "on publie demain matin"),
                ("je joins le document source", "je joins seulement l'export final"),
                ("la demande part au support", "la demande part au service achats"),
            ],
            "non",
            "spoken_restart",
            "Traite « non » comme une reprise orale explicite et garde la seconde branche.",
        ),
        (
            [
                ("je vous réponds après validation", "je vous réponds dès ce matin"),
                ("on annule l'atelier", "on décale l'atelier"),
                ("la relance part à quinze heures", "la relance part à seize heures"),
                ("je mets Léa en copie", "je mets Clara en copie"),
                ("on prend la version anglaise", "on prend la version française"),
                ("je réserve mardi", "je réserve mercredi"),
                ("on garde l'intitulé long", "on garde l'intitulé court"),
                ("je vous appelle ce soir", "je vous appelle demain matin"),
                ("la revue commence en salle A", "la revue commence en salle B"),
                ("on clôture le sujet vendredi", "on clôture le sujet lundi"),
            ],
            "ou plutôt",
            "spoken_restart",
            "Retient la correction après « ou plutôt » et élimine l'essai abandonné.",
        ),
        (
            [
                ("je vous envoie le compte rendu brut", "je vous envoie le compte rendu relu"),
                ("la réunion avec le client reste mardi", "la réunion avec le client passe à jeudi"),
                ("je transmets le bon de commande", "je transmets d'abord le devis"),
                ("on valide la maquette claire", "on valide la maquette sombre"),
                ("je vous partage le dossier complet", "je vous partage le dossier compressé"),
                ("la livraison part ce soir", "la livraison part demain matin"),
                ("on garde la première proposition", "on garde la deuxième proposition"),
                ("je confirme la présence de Camille", "je confirme la présence de Nora"),
                ("on réserve trente minutes", "on réserve une heure"),
                ("je renvoie le fichier source", "je renvoie le PDF signé"),
            ],
            "plutôt",
            "spoken_restart",
            "La reprise explicite signale que seule la seconde formulation doit rester.",
        ),
    ]

    for pairs, marker, subcategory, note in restart_sets:
        for first, second in pairs:
            add(subcategory, f"{first} {marker} {second}", f"{second[0].upper() + second[1:]}.", note)


def build_comma_and_clause_control() -> None:
    opening_sets = [
        (
            "si vous êtes disponible",
            [
                "on peut avancer l'entretien à jeudi",
                "je vous appelle en fin de matinée",
                "nous pouvons clôturer le point aujourd'hui",
                "je vous envoie la version finale avant midi",
                "on maintient le créneau actuel",
                "nous validons le devis dans la foulée",
                "je réserve la salle immédiatement",
                "nous lançons la diffusion demain",
                "je vous partage la synthèse ce soir",
                "on peut regrouper les deux sujets",
                "je garde ce créneau pour vous",
            ],
            "Ajoute la virgule après une proposition conditionnelle placée en tête.",
        ),
        (
            "comme le fichier était trop lourd",
            [
                "je vous envoie un lien séparé",
                "nous avons compressé la pièce jointe",
                "je l'ai découpé en deux envois",
                "je vous le transfère par le dossier partagé",
                "nous avons supprimé les visuels inutiles",
                "je vous renvoie une version allégée",
                "on passe par un espace sécurisé",
                "je vous partage uniquement la partie signée",
                "nous décalons l'envoi complet à ce soir",
                "je vous confirme le dépôt dès qu'il est terminé",
                "on vous transmet le lien dans quelques minutes",
            ],
            "Marque clairement la césure entre la cause initiale et l'action principale.",
        ),
        (
            "après vérification",
            [
                "la dernière pièce jointe est bien la bonne",
                "le montant du devis est correct",
                "le créneau de mardi reste disponible",
                "la liste des participants est à jour",
                "la version transmise hier est complète",
                "le contrat couvre bien les annexes",
                "le dossier partagé fonctionne normalement",
                "la référence indiquée sur la facture est exacte",
                "le planning consolidé est prêt à partir",
                "la salle réservée convient à toute l'équipe",
                "le tableau de suivi est cohérent",
            ],
            "Ajoute la virgule attendue après un segment introductif court.",
        ),
        (
            "pour éviter un doublon",
            [
                "je vous renvoie uniquement la version signée",
                "nous gardons un seul fil de discussion",
                "je retire l'ancienne pièce jointe",
                "on centralise les réponses sur ce message",
                "je supprime la version intermédiaire du dossier",
                "nous gardons le devis rectifié comme référence",
                "je mets à jour le document partagé",
                "on clôture l'ancien ticket aujourd'hui",
                "je fusionne les deux comptes rendus",
                "nous reprenons le tableau unique pour la suite",
                "je transfère seulement le lien final",
            ],
            "Ponctue une proposition de but initiale sans réécrire le fond.",
        ),
        (
            "si cela vous convient",
            [
                "je bloque le créneau avant midi",
                "nous lançons la préparation cet après-midi",
                "je vous confirme la réservation dans l'heure",
                "on garde cette version pour l'envoi client",
                "je transmets l'invitation à toute l'équipe",
                "nous validons la mise à jour ce soir",
                "je finalise le document juste après votre retour",
                "on maintient la démonstration de demain",
                "je vous renvoie le lien unique",
                "nous passons à l'étape suivante",
                "je clôture le point après votre accord",
            ],
            "Clarifie la lecture avec la virgule après une formule d'atténuation.",
        ),
    ]

    for opener, clauses, note in opening_sets:
        for clause in clauses:
            add(
                "comma_and_clause_control",
                f"{opener} {clause}",
                f"{opener.capitalize()}, {clause}.",
                note,
            )


def build_polite_formulation() -> None:
    confirm_targets = [
        "si le créneau de jeudi vous convient",
        "si vous avez bien reçu la convention",
        "si la version jointe est la bonne",
        "si nous pouvons maintenir la réunion",
        "si l'adresse indiquée est correcte",
        "si la facture validée peut partir aujourd'hui",
        "si le lien partagé fonctionne de votre côté",
        "si vous souhaitez que je décale le point",
        "si la proposition répond à votre besoin",
        "si vous êtes disponible avant midi",
        "si le document signé peut être diffusé",
    ]
    for target in confirm_targets:
        add(
            "polite_formulation",
            f"pouvez-vous me confirmer {target}",
            f"Pouvez-vous me confirmer {target} ?",
            "Transforme une demande polie parlée en question correctement ponctuée.",
        )

    send_targets = [
        "la version signée dans la matinée",
        "le devis actualisé avant dix-sept heures",
        "le compte rendu relu aujourd'hui",
        "les accès provisoires avant l'appel",
        "le lien de visioconférence corrigé",
        "la facture rectifiée dès que possible",
        "la synthèse de l'atelier ce soir",
        "le dossier complet après validation interne",
        "le bon de commande final",
        "la présentation consolidée demain matin",
        "le tableau de suivi mis à jour",
    ]
    for target in send_targets:
        add(
            "polite_formulation",
            f"pourriez-vous m'envoyer {target}",
            f"Pourriez-vous m'envoyer {target} ?",
            "Ajoute la casse et le point d'interrogation d'une requête polie.",
        )

    tell_targets = [
        "vous avez besoin d'un format différent",
        "le créneau de demain doit être déplacé",
        "la pièce jointe n'est pas lisible",
        "vous préférez un envoi séparé",
        "le document signé peut attendre lundi",
        "la démonstration doit rester en petit comité",
        "vous souhaitez que j'ajoute l'équipe support",
        "la réunion peut durer une heure",
        "vous avez déjà transmis les annexes",
        "un rappel demain matin vous convient",
        "je dois vous renvoyer la version commentée",
    ]
    for target in tell_targets:
        add(
            "polite_formulation",
            f"merci de me dire si {target}",
            f"Merci de me dire si {target}.",
            "Conserve la formule polie et applique seulement la ponctuation adéquate.",
        )

    favor_targets = [
        "me renvoyer la page signée",
        "confirmer le créneau retenu",
        "partager le lien définitif",
        "vérifier la référence du dossier",
        "m'indiquer le bon interlocuteur",
        "transmettre la version finale au service concerné",
        "me prévenir si un décalage est nécessaire",
        "regrouper les pièces dans un seul envoi",
        "me confirmer la disponibilité de la salle",
        "valider le devis avant l'échéance",
        "m'envoyer le bon de commande actualisé",
    ]
    for target in favor_targets:
        add(
            "polite_formulation",
            f"je vous serais reconnaissant de {target}",
            f"Je vous serais reconnaissant de {target}.",
            "Stabilise une formule de politesse sans sur-réécriture.",
        )

    possible_targets = [
        "me confirmer votre présence",
        "transmettre les annexes manquantes",
        "me renvoyer la facture corrigée",
        "déplacer l'entretien à vendredi",
        "valider le document partagé",
        "m'indiquer l'horaire exact d'arrivée",
        "prévenir l'équipe de ce changement",
        "m'envoyer le support avant l'appel",
        "regrouper vos remarques dans un seul message",
        "me dire si ce point est bloquant",
        "partager la dernière version du planning",
    ]
    for target in possible_targets:
        add(
            "polite_formulation",
            f"si possible merci de {target}",
            f"Si possible, merci de {target}.",
            "Ajoute la virgule de cadence attendue dans une demande polie.",
        )


def finalize() -> None:
    if len(rows) != 350:
        raise ValueError(f"expected 350 rows, found {len(rows)}")

    seen_raw_expected: set[tuple[str, str]] = set()
    for idx, row in enumerate(rows, start=1):
        row["id"] = f"zphyr-round5-email-prose-punctuation-{idx:04d}"
        pair = (row["raw"], row["expected"])
        if pair in seen_raw_expected:
            raise ValueError(f"duplicate pair detected: {pair}")
        seen_raw_expected.add(pair)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def main() -> None:
    build_email_body()
    build_short_sentence()
    build_filler_removal()
    build_spoken_restart()
    build_comma_and_clause_control()
    build_polite_formulation()
    finalize()


if __name__ == "__main__":
    main()
