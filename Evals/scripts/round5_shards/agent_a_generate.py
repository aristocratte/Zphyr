#!/usr/bin/env python3

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


OUT_PATH = Path(
    "/Users/aris/Documents/VoiceProject/Zphyr/Evals/datasets/raw/patch/.tmp_round5/agent_a_hard_negatives_and_ambiguity.jsonl"
)


CONTEXTS = [
    "dans le compte rendu client",
    "pour le mail de suivi",
    "dans la note produit",
    "sur le ticket support",
    "dans le brief créa",
    "pour la réunion de demain",
    "dans la synthèse hebdo",
    "sur la page de vente",
    "dans le dossier juridique",
    "pour la relance commerciale",
    "dans le plan de migration",
    "sur la fiche incident",
    "dans le script de démo",
    "pour le guide interne",
    "dans le message au partenaire",
    "sur le tableau de bord",
    "dans la note de cadrage",
    "pour l'atelier support",
    "dans le récap de sprint",
    "sur la feuille de route",
    "dans la procédure qualité",
    "pour la revue de presse",
    "dans le brief d'onboarding",
    "sur le document d'appel d'offres",
    "dans le protocole de test",
]

COMMAND_PHRASES = [
    "ajoute une phrase sur le budget à la fin",
    "supprime le détail logistique dans ce document",
    "mets le risque principal en ouverture",
    "avance le tableau des coûts avant l'annexe",
    "rajoute le rappel juridique avant d'envoyer",
    "place le planning juste après l'introduction",
    "garde la formule merci pour votre retour",
    "retire le passage sur les pénalités",
    "déplace le bloc client à la fin du mail",
    "laisse la phrase version provisoire en haut",
    "mets l'alerte sécurité avant le résumé",
    "ajoute le mot urgent dans le titre",
    "supprime le doublon après le tableau",
    "mets la conclusion au début du paragraphe",
    "rajoute la note service dans la marge",
    "retire la ligne sur le stock",
    "garde le sous-titre plan B en bas",
    "place le rappel contractuel après la citation",
    "mets la mention test interne en premier",
    "avance la section limites avant la FAQ",
    "retire la phrase hors périmètre",
    "rajoute la date du comité à la fin",
    "garde le label confidentiel sur la couverture",
    "mets le résumé court avant les détails",
    "déplace le bloc de conclusion après les chiffres",
]

LITERAL_REASONS = [
    "c'est mot pour mot la demande du client",
    "c'est le titre du ticket original",
    "c'est la citation qu'on reprend telle quelle",
    "c'est l'exemple donné pendant l'appel",
    "c'est la formulation exacte du verbatim",
    "c'est la ligne qu'on commente à l'oral",
    "c'est la phrase affichée dans la capture",
    "c'est le texte du post-it pris en photo",
    "c'est le libellé qu'on a reçu",
    "c'est le passage lu pendant la réunion",
]

QUOTE_TARGETS = [
    "la demande du client",
    "le titre du ticket",
    "le texte affiché à l'écran",
    "le verbatim de l'appel",
    "la phrase du document source",
    "la consigne reçue hier",
    "le nom exact de la section",
    "le contenu du mail transféré",
    "le titre vu dans la capture",
    "la ligne du tableau qu'on commente",
]

CONTENT_SURFACES = [
    "dans le verbatim",
    "dans la note source",
    "dans le copier-coller du client",
    "dans la capture jointe",
    "dans le résumé brut",
    "dans le ticket d'origine",
    "dans le texte qu'on cite",
    "dans le paragraphe commenté",
    "dans la pièce jointe",
    "dans le document partagé",
]

SUBJECTS = [
    "le message d'accueil",
    "la page tarifaire",
    "la note de synthèse",
    "le discours d'ouverture",
    "la réponse au client",
    "la fiche produit",
    "le guide d'installation",
    "la page support",
    "le compte rendu",
    "la présentation finale",
    "le mail de relance",
    "la page de paiement",
    "le texte du devis",
    "la trame d'atelier",
    "le parcours invité",
    "la procédure interne",
    "le message de confirmation",
    "la page recrutement",
    "le mémo de crise",
    "le récapitulatif du sprint",
    "la charte de réponse",
    "le brief d'agence",
    "la note de version",
    "le formulaire d'inscription",
    "le document de passation",
]

QUALITY_A = [
    "simple",
    "rassurante",
    "précise",
    "fluide",
    "claire",
    "utile",
    "sobre",
    "accessible",
    "directe",
    "cohérente",
    "lisible",
    "stable",
    "concrète",
    "calme",
    "nette",
    "brève",
    "engageante",
    "solide",
    "crédible",
    "pratique",
    "complète",
    "cadencée",
    "propre",
    "explicable",
    "souple",
]

QUALITY_B = [
    "crédible",
    "chaleureuse",
    "pédagogique",
    "rapide à lire",
    "facile à transmettre",
    "utile pour le support",
    "sans effet de manche",
    "compréhensible du premier coup",
    "adaptée au contexte",
    "alignée sur le ton attendu",
    "facile à relire",
    "sans surprise pour l'équipe",
    "ancrée dans les faits",
    "sans dramatisation",
    "sans ambiguïté inutile",
    "sans phrase en trop",
    "avec un ton humain",
    "sans détour inutile",
    "sans promesse excessive",
    "simple à appliquer",
    "sans rien oublier d'essentiel",
    "agréable à entendre",
    "sans surcharge visuelle",
    "simple à expliquer",
    "adaptable si besoin",
]

AUDIENCES = [
    "le client final",
    "l'équipe support",
    "la direction",
    "les nouveaux arrivants",
    "un lecteur pressé",
    "les équipes terrain",
    "les utilisateurs non techniques",
    "le service juridique",
    "les managers",
    "les partenaires externes",
    "les relecteurs",
    "les personnes en astreinte",
    "un prospect froid",
    "l'équipe produit",
    "le comité projet",
    "les formateurs",
    "les personnes qui reprennent le dossier",
    "les clients mécontents",
    "les équipes commerciales",
    "les lecteurs mobiles",
    "les auditeurs",
    "les prestataires",
    "les membres du support niveau un",
    "les nouveaux clients",
    "le comité de validation",
]

VERB_A = [
    "raccourcir le texte",
    "clarifier la promesse",
    "accélérer la lecture",
    "rassurer le lecteur",
    "poser le contexte",
    "garder un ton direct",
    "simplifier l'ouverture",
    "réduire le doute",
    "tenir la ligne éditoriale",
    "mettre les faits au premier plan",
    "alléger l'introduction",
    "donner un cap clair",
    "rester concret",
    "éviter l'effet catalogue",
    "faire passer l'idée vite",
    "garder un ton posé",
    "maintenir le fil logique",
    "aider la relecture",
    "préserver l'intention de départ",
    "tenir en une lecture",
    "répondre à la question centrale",
    "montrer le bénéfice sans en rajouter",
    "laisser une impression nette",
    "garder le texte respirable",
    "éviter les détours",
]

VERB_B = [
    "perdre la nuance importante",
    "alourdir la phrase",
    "casser le rythme",
    "gommer la réserve utile",
    "faire disparaître l'exemple",
    "durcir le ton",
    "multiplier les détails",
    "ouvrir une nouvelle ambiguïté",
    "changer la portée de la phrase",
    "faire trop marketing",
    "tordre le message",
    "diluer le point principal",
    "déplacer le problème",
    "surjouer la certitude",
    "transformer la phrase en liste",
    "perdre le naturel",
    "déformer la demande d'origine",
    "ajouter une conclusion non dite",
    "forcer une structure",
    "retirer le contexte utile",
    "réécrire plus que nécessaire",
    "faire sonner le message trop sec",
    "changer le niveau de détail",
    "ajouter une consigne cachée",
    "déborder du sujet",
]

NAV_TOPICS = [
    "la conclusion",
    "le rappel budgetaire",
    "la phrase sur les délais",
    "le point sécurité",
    "la note méthodo",
    "le rappel client",
    "la réserve juridique",
    "la partie chiffres",
    "la citation d'ouverture",
    "le tableau des hypothèses",
    "la synthèse finale",
    "le paragraphe sur le planning",
    "la mention confidentielle",
    "le rappel d'astreinte",
    "la référence du contrat",
    "le détail du devis",
    "la phrase d'excuse",
    "la liste des options",
    "le commentaire sur le timing",
    "la note de prudence",
    "le bloc support",
    "le rappel de validation",
    "la phrase d'appel",
    "la limite du périmètre",
    "le mot de clôture",
]

NAV_LOCATIONS = [
    "à la fin du document",
    "avant l'annexe",
    "au début du mail",
    "dans le troisième paragraphe",
    "juste après le titre",
    "dans la dernière section",
    "entre les deux exemples",
    "avant le tableau",
    "dans la première minute de la démo",
    "sur la dernière slide",
    "après la partie contexte",
    "dans le bloc central",
    "sur la couverture",
    "à gauche sur l'écran",
    "dans la marge du PDF",
    "au milieu de la page",
    "au tout début du message",
    "après les objections",
    "dans la phrase d'ouverture",
    "avant la conclusion",
    "en bas de la fiche",
    "dans la note finale",
    "au sommet du document",
    "dans le dernier encadré",
    "après les chiffres clés",
]

NAV_REASONS = [
    "et j'en parle juste comme d'un repère",
    "et ça me va exactement comme ça",
    "et je le mentionne seulement pour situer la lecture",
    "et c'est juste un constat",
    "et pas une demande de déplacement",
    "et c'est le meilleur endroit selon moi",
    "et je l'évoque comme une observation",
    "et ça sert juste à expliquer le cheminement",
    "et je rappelle simplement où il se trouve",
    "et je ne demande aucune modification",
]

SCOPE_REFERENCES = [
    "dans ce document",
    "dans ce paragraphe",
    "sur cette page",
    "avant d'envoyer",
    "dans ce mail",
    "sur cette ligne",
    "dans cette note",
    "avant de publier",
    "dans ce tableau",
    "sur cette slide",
    "dans ce dossier",
    "avant la validation",
    "dans cette partie",
    "sur ce point",
    "dans cette section",
    "avant la réunion",
    "dans cette version",
    "sur cet écran",
    "dans le corps du message",
    "avant la diffusion",
    "sur la page d'accueil",
    "dans le bloc final",
    "avant le partage",
    "dans le texte brut",
    "sur le document source",
]

SCOPE_ITEMS = [
    "le budget déjà validé",
    "la formulation de départ",
    "le risque principal",
    "le point qui bloque",
    "la décision de ce matin",
    "la nuance utile",
    "le ton attendu",
    "la réserve du client",
    "la contrainte de délai",
    "la phrase qui rassure",
    "la preuve évoquée",
    "la promesse minimale",
    "le cadre du projet",
    "le rappel important",
    "la phrase de transition",
    "l'exemple cité",
    "la ligne contestée",
    "la demande reçue",
    "le constat partagé",
    "la limite annoncée",
    "la consigne orale",
    "le point de méthode",
    "la marge de manœuvre",
    "le compromis trouvé",
    "la conclusion retenue",
]

SCOPE_FOLLOWUPS = [
    "pas de changer la structure",
    "pas de lancer une mise en forme spéciale",
    "pas d'ajouter une liste",
    "pas de retoucher tout le texte",
    "pas de faire une commande d'édition",
    "pas de déplacer quoi que ce soit",
    "pas de forcer une nouvelle version",
    "pas de transformer la phrase en action",
    "pas de réécrire au-delà du nécessaire",
    "pas de toucher au reste du passage",
]

RESTART_INSERTS = [
    "enfin",
    "je veux dire",
    "ou plutôt",
    "pardon",
    "non enfin",
    "disons",
]

RESTART_CLAUSES = [
    "qu'on peut garder cette version",
    "que la formulation actuelle suffit",
    "qu'on va envoyer ce message tel quel",
    "que ce passage est déjà assez clair",
    "que le ton reste juste comme ça",
    "qu'on n'a pas besoin d'en faire plus",
    "que la note tient déjà debout",
    "que la phrase marche mieux sobre",
    "qu'on doit rester sur cette piste",
    "que ce rappel suffit pour demain",
    "qu'on peut laisser ce paragraphe tranquille",
    "que le lecteur comprendra sans ajout",
    "qu'on garde ce niveau de détail",
    "qu'on n'a pas besoin d'une autre structure",
    "qu'on reste sur cette formulation-là",
    "que ça dit déjà l'essentiel",
    "qu'il vaut mieux ne pas trop retoucher",
    "qu'on tient une version correcte",
    "qu'on peut garder ce ton simple",
    "que ça reste le meilleur compromis",
    "qu'on garde la phrase comme repère",
    "qu'il ne faut pas surcorriger",
    "qu'on a déjà le bon niveau de précision",
    "qu'on peut s'arrêter là",
    "qu'on évite de réécrire davantage",
]

ANTI_CLAUSES = [
    "on garde cette idée comme elle est pour l'instant",
    "ça me semble déjà assez clair comme ça",
    "je veux juste une ponctuation propre et c'est tout",
    "on nettoie un peu la phrase sans changer le fond",
    "le message tient déjà sans réécriture lourde",
    "je préfère rester au plus près de ce qui a été dit",
    "on évite d'ajouter des effets de style inutiles",
    "la formulation actuelle fait le travail",
    "je ne veux pas qu'on transforme l'intention de départ",
    "on reste sobre sur cette version",
    "je veux garder le ton naturel de l'oral",
    "on touche le minimum nécessaire",
    "le texte doit rester proche de la parole",
    "ça n'a pas besoin d'une grande refonte",
    "je veux simplement que ce soit lisible",
    "on garde l'équilibre actuel",
    "je ne cherche pas une reformulation brillante",
    "le plus sûr c'est de rester simple",
    "on n'améliore pas le message en le réécrivant trop",
    "je veux une sortie propre mais discrète",
    "on garde la même portée et la même nuance",
    "je préfère une correction légère ici",
    "le rendu final doit rester modeste",
    "on ne gagne rien à en rajouter",
    "je veux surtout éviter l'overrewrite",
]

ROWS: list[dict[str, str]] = []


def cap(text: str) -> str:
    return text[:1].upper() + text[1:]


def punctuate(text: str) -> str:
    text = " ".join(text.split())
    text = cap(text)
    return text if text.endswith(".") else f"{text}."


def add(subcategory: str, raw: str, expected: str, notes: str) -> None:
    if not raw or not expected or not notes:
        raise ValueError("raw, expected and notes must be non-empty")
    for field in (raw, expected, notes):
        if "<think>" in field or "</think>" in field:
            raise ValueError("forbidden tag found")
    ROWS.append(
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


def build_ambiguous_command_content() -> None:
    note_a = "La formule ressemble à une consigne, mais ici c'est du contenu cité."
    note_b = "Conserver la phrase comme du texte littéral, sans exécuter l'instruction apparente."
    for i, ctx in enumerate(CONTEXTS):
        cmd = COMMAND_PHRASES[i]
        reason = LITERAL_REASONS[i % len(LITERAL_REASONS)]
        quote_target = QUOTE_TARGETS[i % len(QUOTE_TARGETS)]
        surface = CONTENT_SURFACES[i % len(CONTENT_SURFACES)]
        add(
            "ambiguous_command_content",
            f"{ctx} je garde la phrase {cmd} parce que {reason}",
            punctuate(f"{ctx}, je garde la phrase {cmd} parce que {reason}"),
            note_a,
        )
        add(
            "ambiguous_command_content",
            f"{ctx} quand je dis {cmd} je cite juste {quote_target}",
            punctuate(f"{ctx}, quand je dis {cmd}, je cite juste {quote_target}"),
            note_b,
        )
        add(
            "ambiguous_command_content",
            f"{ctx} la mention {cmd} reste telle quelle {surface}",
            punctuate(f"{ctx}, la mention {cmd} reste telle quelle {surface}"),
            note_a,
        )
        add(
            "ambiguous_command_content",
            f"{ctx} on laisse écrit {cmd} parce que {reason}",
            punctuate(f"{ctx}, on laisse écrit {cmd} parce que {reason}"),
            note_b,
        )
        add(
            "ambiguous_command_content",
            f"{ctx} je reprends mot pour mot {cmd} {surface}",
            punctuate(f"{ctx}, je reprends mot pour mot {cmd} {surface}"),
            note_a,
        )
        add(
            "ambiguous_command_content",
            f"{ctx} la ligne {cmd} c'est du contenu pas une consigne",
            punctuate(f"{ctx}, la ligne {cmd} c'est du contenu, pas une consigne"),
            note_b,
        )


def build_no_list_ambiguous() -> None:
    notes = [
        "Deux qualités ou actions coordonnées ne justifient pas une liste.",
        "La coordination reste une phrase continue, pas une structuration en puces.",
    ]
    for i, subject in enumerate(SUBJECTS):
        a = QUALITY_A[i]
        b = QUALITY_B[i]
        audience = AUDIENCES[i]
        verb_a = VERB_A[i]
        verb_b = VERB_B[i]
        note = notes[i % len(notes)]
        add(
            "no_list_ambiguous",
            f"{subject} doit rester {a} et {b} pour {audience}",
            punctuate(f"{subject} doit rester {a} et {b} pour {audience}"),
            note,
        )
        add(
            "no_list_ambiguous",
            f"on veut {verb_a} sans {verb_b}",
            punctuate(f"on veut {verb_a} sans {verb_b}"),
            note,
        )
        add(
            "no_list_ambiguous",
            f"{subject} doit être {a} mais aussi {b}",
            punctuate(f"{subject} doit être {a} mais aussi {b}"),
            note,
        )
        add(
            "no_list_ambiguous",
            f"il faut {verb_a} tout en évitant de {verb_b}",
            punctuate(f"il faut {verb_a} tout en évitant de {verb_b}"),
            note,
        )
        add(
            "no_list_ambiguous",
            f"{subject} doit aider {audience} et rester {a}",
            punctuate(f"{subject} doit aider {audience} et rester {a}"),
            note,
        )
        add(
            "no_list_ambiguous",
            f"je veux {verb_a} et en même temps ne pas {verb_b}",
            punctuate(f"je veux {verb_a} et en même temps ne pas {verb_b}"),
            note,
        )


def build_navigation_ambiguity() -> None:
    notes = [
        "Les repères de position sont descriptifs ici et ne doivent pas être exécutés.",
        "La mention de placement reste littérale et sert seulement à situer le contenu.",
    ]
    for i, topic in enumerate(NAV_TOPICS):
        location = NAV_LOCATIONS[i]
        reason = NAV_REASONS[i % len(NAV_REASONS)]
        note = notes[i % len(notes)]
        add(
            "navigation_ambiguity",
            f"{topic} est déjà {location} {reason}",
            punctuate(f"{topic} est déjà {location} {reason}"),
            note,
        )
        add(
            "navigation_ambiguity",
            f"je parle du fait que {topic} reste {location} {reason}",
            punctuate(f"je parle du fait que {topic} reste {location} {reason}"),
            note,
        )
        add(
            "navigation_ambiguity",
            f"quand je mentionne {location} pour {topic} je situe juste la lecture",
            punctuate(f"quand je mentionne {location} pour {topic}, je situe juste la lecture"),
            note,
        )
        add(
            "navigation_ambiguity",
            f"{topic} vient {location} et c'est simplement un repère pour moi",
            punctuate(f"{topic} vient {location} et c'est simplement un repère pour moi"),
            note,
        )
        add(
            "navigation_ambiguity",
            f"je rappelle que {topic} se trouve {location} sans demander de bouger quoi que ce soit",
            punctuate(
                f"je rappelle que {topic} se trouve {location} sans demander de bouger quoi que ce soit"
            ),
            note,
        )
        add(
            "navigation_ambiguity",
            f"pour {topic} la mention {location} reste descriptive et pas opérationnelle",
            punctuate(f"pour {topic}, la mention {location} reste descriptive et pas opérationnelle"),
            note,
        )


def build_formatting_scope_ambiguity() -> None:
    notes = [
        "Le mot de portée reste littéral et n'ouvre pas une commande de mise en forme.",
        "Ici le scope est sémantique ; il faut nettoyer légèrement sans transformer la structure.",
    ]
    for i, scope in enumerate(SCOPE_REFERENCES):
        item = SCOPE_ITEMS[i]
        follow = SCOPE_FOLLOWUPS[i % len(SCOPE_FOLLOWUPS)]
        note = notes[i % len(notes)]
        add(
            "formatting_scope_ambiguity",
            f"{scope} je veux surtout rappeler {item}",
            punctuate(f"{scope}, je veux surtout rappeler {item}"),
            note,
        )
        add(
            "formatting_scope_ambiguity",
            f"{scope} je parle simplement de {item} {follow}",
            punctuate(f"{scope}, je parle simplement de {item}, {follow}"),
            note,
        )
        add(
            "formatting_scope_ambiguity",
            f"{scope} mon sujet c'est {item} {follow}",
            punctuate(f"{scope}, mon sujet c'est {item}, {follow}"),
            note,
        )
        add(
            "formatting_scope_ambiguity",
            f"{scope} je garde juste {item} en tête {follow}",
            punctuate(f"{scope}, je garde juste {item} en tête, {follow}"),
            note,
        )
        add(
            "formatting_scope_ambiguity",
            f"{scope} on évoque {item} et pas une action d'édition",
            punctuate(f"{scope}, on évoque {item} et pas une action d'édition"),
            note,
        )
        add(
            "formatting_scope_ambiguity",
            f"{scope} je reste sur {item} {follow}",
            punctuate(f"{scope}, je reste sur {item}, {follow}"),
            note,
        )


def build_spoken_restart_hard_negative() -> None:
    notes = [
        "Le redémarrage oral appelle un nettoyage discret, pas une réécriture agressive.",
        "Présence d'un restart parlé : garder le fond et stabiliser seulement la ponctuation.",
    ]
    openers = [
        "je pense",
        "c'est",
        "on va dire",
        "je dirais",
        "ça reste",
        "on peut dire",
    ]
    for i, clause in enumerate(RESTART_CLAUSES):
        insert = RESTART_INSERTS[i % len(RESTART_INSERTS)]
        opener = openers[i % len(openers)]
        note = notes[i % len(notes)]
        add(
            "spoken_restart_hard_negative",
            f"{opener} {insert} {clause}",
            punctuate(f"{opener}, {insert}, {clause}"),
            note,
        )
        add(
            "spoken_restart_hard_negative",
            f"{opener} {insert} {clause} pour cette version",
            punctuate(f"{opener}, {insert}, {clause} pour cette version"),
            note,
        )
        add(
            "spoken_restart_hard_negative",
            f"{opener} {insert} {clause} aujourd'hui",
            punctuate(f"{opener}, {insert}, {clause} aujourd'hui"),
            note,
        )
        add(
            "spoken_restart_hard_negative",
            f"{opener} {insert} {clause} dans ce contexte",
            punctuate(f"{opener}, {insert}, {clause} dans ce contexte"),
            note,
        )
        add(
            "spoken_restart_hard_negative",
            f"{opener} {insert} {clause} pour le message final",
            punctuate(f"{opener}, {insert}, {clause} pour le message final"),
            note,
        )
        add(
            "spoken_restart_hard_negative",
            f"{opener} {insert} {clause} si on reste sobre",
            punctuate(f"{opener}, {insert}, {clause} si on reste sobre"),
            note,
        )


def build_anti_overrewrite() -> None:
    notes = [
        "Le bon comportement est un polissage minimal, sans reformulation créative.",
        "Cas anti-overrewrite : la sortie doit rester très proche de l'oral d'origine.",
    ]
    tails = [
        "pour cette passe",
        "sur ce message",
        "dans cette note",
        "pour l'envoi de ce soir",
        "à ce stade",
        "sur cette version",
    ]
    for i, clause in enumerate(ANTI_CLAUSES):
        note = notes[i % len(notes)]
        tail = tails[i % len(tails)]
        add(
            "anti_overrewrite",
            clause,
            punctuate(clause),
            note,
        )
        add(
            "anti_overrewrite",
            f"{clause} {tail}",
            punctuate(f"{clause} {tail}"),
            note,
        )
        add(
            "anti_overrewrite",
            f"franchement {clause}",
            punctuate(f"franchement {clause}"),
            note,
        )
        add(
            "anti_overrewrite",
            f"pour moi {clause}",
            punctuate(f"pour moi, {clause}"),
            note,
        )
        add(
            "anti_overrewrite",
            f"oui {clause}",
            punctuate(f"oui, {clause}"),
            note,
        )
        add(
            "anti_overrewrite",
            f"à mon avis {clause}",
            punctuate(f"à mon avis, {clause}"),
            note,
        )


def main() -> None:
    build_ambiguous_command_content()
    build_no_list_ambiguous()
    build_navigation_ambiguity()
    build_formatting_scope_ambiguity()
    build_spoken_restart_hard_negative()
    build_anti_overrewrite()

    expected_counts = {
        "ambiguous_command_content": 150,
        "no_list_ambiguous": 150,
        "navigation_ambiguity": 150,
        "formatting_scope_ambiguity": 150,
        "spoken_restart_hard_negative": 150,
        "anti_overrewrite": 150,
    }

    counts = Counter(row["subcategory"] for row in ROWS)
    if counts != expected_counts:
        raise ValueError(f"unexpected counts: {counts}")

    seen = set()
    for idx, row in enumerate(ROWS, start=1):
        key = (row["subcategory"], row["raw"], row["expected"])
        if key in seen:
            raise ValueError(f"duplicate row detected: {key}")
        seen.add(key)
        row["id"] = f"zphyr-round5-hard-negatives-and-ambiguity-{idx:04d}"

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as handle:
        for row in ROWS:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"wrote {len(ROWS)} rows to {OUT_PATH}")
    for subcategory in sorted(expected_counts):
        print(f"{subcategory}: {counts[subcategory]}")


if __name__ == "__main__":
    main()
