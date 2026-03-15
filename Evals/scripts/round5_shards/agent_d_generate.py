#!/usr/bin/env python3

import json
from pathlib import Path


OUT_PATH = Path(
    "/Users/aris/Documents/VoiceProject/Zphyr/Evals/datasets/raw/patch/.tmp_round5/agent_d_spoken_lists_and_structuring.jsonl"
)


OBJECT_GROUPS = [
    ("la navigation mobile", "le message de confirmation", "la FAQ de support"),
    ("le brief créa", "la maquette tablette", "la bibliothèque d'icônes"),
    ("le script d'import", "la base prospects", "le connecteur CRM"),
    ("la page tarifs", "la grille tarifaire", "le modèle de devis"),
    ("la procédure d'astreinte", "les alertes de production", "la configuration du monitoring"),
    ("le guide d'onboarding", "le support de formation", "le wiki interne"),
    ("le tunnel d'achat", "la page de paiement", "le flux de remboursement"),
    ("le planning éditorial", "la campagne newsletter", "la séquence de bienvenue"),
    ("le comparatif fournisseurs", "le dossier de sponsoring", "le kit de vente"),
    ("la section mentions légales", "la politique d'accès", "le rapport d'audit"),
    ("le reporting hebdomadaire", "le tableau des priorités", "la note de synthèse"),
    ("le parcours invité", "le module de recherche", "la page partenaires"),
    ("le backlog incident", "les tickets urgents", "le tableau des anomalies"),
    ("la feuille de route Q2", "la note de cadrage", "le backlog design"),
    ("la boîte mail support", "le centre d'aide", "le formulaire SAV"),
    ("le fichier d'inventaire", "les exports comptables", "le dashboard logistique"),
    ("le compte rendu client", "le suivi des abonnements", "la campagne de relance"),
    ("la page recrutement", "la trame d'entretien", "le calendrier social"),
    ("le script de migration", "la recette de déploiement", "le plan de reprise"),
    ("la check-list QA", "la structure des dossiers", "le script de sauvegarde"),
    ("la feuille de style", "le wording de la landing page", "la page événements"),
    ("la matrice des risques", "le mode opératoire", "le rapport d'audit"),
    ("la documentation API", "la liste des dépendances", "la console d'administration"),
    ("la base documentaire", "la charte de réponse", "les formulaires internes"),
    ("les étiquettes colis", "le dashboard logistique", "le suivi des retours"),
]


CONTEXTS = [
    "pour la revue de ce matin",
    "avant le point client de quinze heures",
    "pour le sprint de lundi",
    "avant la démo de demain",
    "pour la reprise de mercredi",
    "avant l'atelier support",
    "pour la mise en ligne de ce soir",
    "avant la réunion produit",
    "pour le bilan du trimestre",
    "avant l'envoi au juridique",
    "pour le suivi de mardi",
    "avant la séance de test",
    "pour le comité design",
    "avant la présentation au board",
    "pour la tournée support",
    "avant la clôture mensuelle",
    "pour le point abonnements",
    "avant les entretiens de jeudi",
    "pour la bascule de minuit",
    "avant la passe QA finale",
    "pour la validation de la campagne",
    "avant le point risques",
    "pour la revue technique",
    "avant la diffusion interne",
    "pour la préparation logistique",
]


VERB_SETS = [
    ("vérifier", "corriger", "mettre à jour"),
    ("revoir", "clarifier", "documenter"),
    ("tester", "simplifier", "finaliser"),
]


BULLET_HEADERS = [
    "point",
    "liste",
    "puce",
]


INLINE_CUES = [
    "les trois priorités c'est",
    "les trois sujets du moment c'est",
    "on doit couvrir trois points",
]


NO_LIST_TEMPLATES = [
    "{context} on doit {a} et {b} avant de {c}",
    "{context} il faut {a} puis {b} pour pouvoir {c}",
    "{context} on va {a} et {b} sans oublier de {c}",
]


DISAMBIGUATION_TEMPLATES = [
    "{context} premièrement je veux surtout {a} avant tout le reste",
    "{context} deuxièmement si on doit {b} on prendra un peu plus de temps",
    "{context} troisièmement je préfère {c} demain matin plutôt que ce soir",
    "{context} quand je dis {a} puis {b} je résume juste la discussion",
    "{context} si on parle de {a} de {b} et de {c} on garde une seule phrase",
]


NOTES = {
    "bulleted_spoken": "Les marqueurs parlés de puces justifient une vraie liste à puces.",
    "numbered_spoken": "Les ordinaux explicites doivent devenir une liste numérotée.",
    "inline_enumeration": "Le signal d'énumération reste en ligne et ne doit pas devenir une liste verticale.",
    "no_list_control": "Coordination simple : garder une phrase et ne pas forcer une liste.",
    "task_sequence": "La séquence d'actions est nette ; le passage en étapes numérotées est justifié.",
    "list_vs_sentence_disambiguation": "Le mot déclencheur reste discursif ici ; il faut garder une phrase ordinaire.",
}


def cap(text: str) -> str:
    return text[0].upper() + text[1:]


def sentence(text: str) -> str:
    text = text.strip()
    if not text.endswith("."):
        text += "."
    return cap(text)


def intro_sentence(context: str, tail: str) -> str:
    return sentence(f"{context}, {tail}")


def bullet_list(context: str, items) -> str:
    body = "\n".join(f"- {cap(item)}." for item in items)
    return f"{cap(context)} :\n{body}"


def numbered_list(context: str, items) -> str:
    body = "\n".join(f"{idx}. {cap(item)}." for idx, item in enumerate(items, start=1))
    return f"{cap(context)} :\n{body}"


def inline_sentence(context: str, items, cue: str) -> str:
    if cue == "on doit couvrir trois points":
        return intro_sentence(context, f"{cue} : {items[0]}, {items[1]} et {items[2]}")
    return intro_sentence(context, f"{cue} {items[0]}, {items[1]} et {items[2]}")


def no_list_sentence(context: str, items, template: str) -> str:
    body = template.format(context="", a=items[0], b=items[1], c=items[2]).strip()
    return intro_sentence(context, body)


def disambiguation_sentence(context: str, items, template: str) -> str:
    body = template.format(context="", a=items[0], b=items[1], c=items[2]).strip()
    body = body.replace("premièrement ", "premièrement, ", 1)
    body = body.replace("deuxièmement ", "deuxièmement, ", 1)
    body = body.replace("troisièmement ", "troisièmement, ", 1)
    if body.startswith("si on parle de "):
        body = f"si on parle de {items[0]}, de {items[1]} et de {items[2]}, on garde une seule phrase"
    return intro_sentence(context, body)


def main() -> None:
    rows = []
    counter = 1
    for group_index, objects in enumerate(OBJECT_GROUPS):
        context = CONTEXTS[group_index]
        for variant_index, verbs in enumerate(VERB_SETS):
            items = [f"{verbs[pos]} {objects[pos]}" for pos in range(3)]

            bullet_marker = BULLET_HEADERS[(group_index + variant_index) % len(BULLET_HEADERS)]
            raw = f"{context} {bullet_marker} {items[0]} {bullet_marker} {items[1]} {bullet_marker} {items[2]}"
            rows.append(
                {
                    "id": f"zphyr-round5-spoken-lists-and-structuring-{counter:04d}",
                    "category": "round5_patch",
                    "subcategory": "bulleted_spoken",
                    "raw": raw,
                    "expected": bullet_list(context, items),
                    "language": "fr",
                    "notes": NOTES["bulleted_spoken"],
                }
            )
            counter += 1

            raw = f"{context} premièrement {items[0]} deuxièmement {items[1]} troisièmement {items[2]}"
            rows.append(
                {
                    "id": f"zphyr-round5-spoken-lists-and-structuring-{counter:04d}",
                    "category": "round5_patch",
                    "subcategory": "numbered_spoken",
                    "raw": raw,
                    "expected": numbered_list(context, items),
                    "language": "fr",
                    "notes": NOTES["numbered_spoken"],
                }
            )
            counter += 1

            cue = INLINE_CUES[(group_index + variant_index) % len(INLINE_CUES)]
            raw = f"{context} {cue} {items[0]} {items[1]} et {items[2]}"
            rows.append(
                {
                    "id": f"zphyr-round5-spoken-lists-and-structuring-{counter:04d}",
                    "category": "round5_patch",
                    "subcategory": "inline_enumeration",
                    "raw": raw,
                    "expected": inline_sentence(context, items, cue),
                    "language": "fr",
                    "notes": NOTES["inline_enumeration"],
                }
            )
            counter += 1

            no_list_template = NO_LIST_TEMPLATES[(group_index + variant_index) % len(NO_LIST_TEMPLATES)]
            raw = no_list_template.format(context=context, a=items[0], b=items[1], c=items[2])
            rows.append(
                {
                    "id": f"zphyr-round5-spoken-lists-and-structuring-{counter:04d}",
                    "category": "round5_patch",
                    "subcategory": "no_list_control",
                    "raw": raw,
                    "expected": no_list_sentence(context, items, no_list_template),
                    "language": "fr",
                    "notes": NOTES["no_list_control"],
                }
            )
            counter += 1

            raw = f"{context} d'abord {items[0]} ensuite {items[1]} enfin {items[2]}"
            rows.append(
                {
                    "id": f"zphyr-round5-spoken-lists-and-structuring-{counter:04d}",
                    "category": "round5_patch",
                    "subcategory": "task_sequence",
                    "raw": raw,
                    "expected": numbered_list(context, items),
                    "language": "fr",
                    "notes": NOTES["task_sequence"],
                }
            )
            counter += 1

            disambiguation_template = DISAMBIGUATION_TEMPLATES[
                (group_index + variant_index) % len(DISAMBIGUATION_TEMPLATES)
            ]
            raw = disambiguation_template.format(context=context, a=items[0], b=items[1], c=items[2])
            rows.append(
                {
                    "id": f"zphyr-round5-spoken-lists-and-structuring-{counter:04d}",
                    "category": "round5_patch",
                    "subcategory": "list_vs_sentence_disambiguation",
                    "raw": raw,
                    "expected": disambiguation_sentence(context, items, disambiguation_template),
                    "language": "fr",
                    "notes": NOTES["list_vs_sentence_disambiguation"],
                }
            )
            counter += 1

    if len(rows) != 450:
        raise SystemExit(f"expected 450 rows, got {len(rows)}")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
