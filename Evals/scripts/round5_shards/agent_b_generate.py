from __future__ import annotations

import json
from itertools import product
from pathlib import Path


ROOT = Path("/Users/aris/Documents/VoiceProject/Zphyr")
OUT = ROOT / "Evals/datasets/raw/patch/.tmp_round5/agent_b_intentional_repetition_preservation.jsonl"


def cap(text: str) -> str:
    text = " ".join(text.split())
    return text[:1].upper() + text[1:]


def finish(context: str, body: str) -> str:
    return f"{cap(context)}, {body}."


def make_row(idx: int, subcategory: str, raw: str, expected: str, notes: str) -> dict[str, str]:
    return {
        "id": f"zphyr-round5-intentional-repetition-preservation-{idx:04d}",
        "category": "round5_patch",
        "subcategory": subcategory,
        "raw": raw,
        "expected": expected,
        "language": "fr",
        "notes": notes,
    }


CONTEXTS = [
    "pour cette livraison",
    "sur ce ticket",
    "avant la démo de jeudi",
    "dans ce dossier client",
    "pour la version de ce soir",
    "sur la maquette d'accueil",
    "dans le point de demain",
]


INTENTIONAL_BUNDLES = [
    {
        "main": "il faut garder le message simple",
        "resource": "du temps",
        "goal": "finir ça proprement",
        "hold": "on valide rien tout de suite",
        "process": "ça se remet en place",
    },
    {
        "main": "je veux relire chaque détail",
        "resource": "de la marge",
        "goal": "caler la réponse finale",
        "hold": "on envoie rien maintenant",
        "process": "ça revient doucement",
    },
    {
        "main": "on attend le feu vert final",
        "resource": "du calme",
        "goal": "décider sans se presser",
        "hold": "on tranche pas ce matin",
        "process": "ça reprend son rythme",
    },
    {
        "main": "il faut laisser la discussion respirer",
        "resource": "du recul",
        "goal": "voir le problème en entier",
        "hold": "on boucle rien ce soir",
        "process": "ça retombe un peu",
    },
    {
        "main": "je préfère garder cette piste ouverte",
        "resource": "de l'air",
        "goal": "choisir la bonne option",
        "hold": "on ferme rien maintenant",
        "process": "ça revient petit à petit",
    },
]


EMPHASIS_BUNDLES = [
    {
        "very": "important de prévenir le support",
        "too": "long à relire comme ça",
        "well": "clair quand on l'explique",
        "super": "rassurant pour le client",
    },
    {
        "very": "sensible pour la suite",
        "too": "fragile dans ce timing",
        "well": "utile quand on documente",
        "super": "agréable à présenter",
    },
    {
        "very": "tendu côté budget",
        "too": "pénible à corriger à la main",
        "well": "net dans la maquette",
        "super": "propre à l'écran",
    },
    {
        "very": "délicat à expliquer au client",
        "too": "risqué pour la prod",
        "well": "lisible dans le résumé",
        "super": "solide en réunion",
    },
    {
        "very": "chargé pour une seule journée",
        "too": "compliqué à arbitrer maintenant",
        "well": "fluide pendant la démo",
        "super": "apaisant pour tout le monde",
    },
]


SPOKEN_BUNDLES = [
    {
        "yes_clause": "on peut garder ce plan",
        "insist_clause": "c'est bien ce fichier-là qu'il faut relire",
        "urge_clause": "on lance la visio dès que tout le monde arrive",
        "hurry_clause": "tu m'envoies la capture avant le point",
    },
    {
        "yes_clause": "je t'appelle après le point",
        "insist_clause": "c'est cette version qu'on valide",
        "urge_clause": "on bloque le créneau avant midi",
        "hurry_clause": "tu boucles le mail avant la relance",
    },
    {
        "yes_clause": "on déplace la revue à demain",
        "insist_clause": "c'est bien ce paragraphe qui sonne faux",
        "urge_clause": "on prévient le support tout de suite",
        "hurry_clause": "tu relis le bandeau avant publication",
    },
    {
        "yes_clause": "je garde la formulation courte",
        "insist_clause": "c'est bien cette alerte qui a déclenché le reste",
        "urge_clause": "on ferme la salle avant dix-huit heures",
        "hurry_clause": "tu renvoies la facture avant le call",
    },
    {
        "yes_clause": "on part sur la piste la plus simple",
        "insist_clause": "c'est bien cette estimation qui nous bloque",
        "urge_clause": "on rappelle le client avant sa coupure",
        "hurry_clause": "tu reprends la slide de synthèse maintenant",
    },
]


CONTRASTIVE_BUNDLES = [
    {
        "want_target": "le rouge rouge",
        "want_alt": "le rouge brique",
        "keep_target": "le mode manuel manuel",
        "keep_alt": "le mode semi-auto",
        "speak_target": "du bug login login",
        "speak_alt": "du bug panier",
        "need_target": "de la version simple simple",
        "need_alt": "de la version premium",
    },
    {
        "want_target": "le bleu bleu",
        "want_alt": "le bleu pétrole",
        "keep_target": "le mode texte texte",
        "keep_alt": "le mode riche",
        "speak_target": "du bug checkout checkout",
        "speak_alt": "du bug facture",
        "need_target": "de la version légère légère",
        "need_alt": "de la version complète",
    },
    {
        "want_target": "le vert vert",
        "want_alt": "le vert olive",
        "keep_target": "le mode export export",
        "keep_alt": "le mode aperçu",
        "speak_target": "du bug search search",
        "speak_alt": "du bug filtre",
        "need_target": "de la version directe directe",
        "need_alt": "de la version guidée",
    },
    {
        "want_target": "le noir noir",
        "want_alt": "le noir anthracite",
        "keep_target": "le mode local local",
        "keep_alt": "le mode distant",
        "speak_target": "du bug upload upload",
        "speak_alt": "du bug partage",
        "need_target": "de la version courte courte",
        "need_alt": "de la version détaillée",
    },
    {
        "want_target": "le blanc blanc",
        "want_alt": "le blanc cassé",
        "keep_target": "le mode admin admin",
        "keep_alt": "le mode lecteur",
        "speak_target": "du bug paiement paiement",
        "speak_alt": "du bug profil",
        "need_target": "de la version ouverte ouverte",
        "need_alt": "de la version verrouillée",
    },
]


RHETORICAL_BUNDLES = [
    {
        "first": "on avance on avance",
        "first_tail": "mais le planning ne suit pas",
        "second": "ça monte ça monte",
        "second_tail": "puis ça retombe d'un coup",
        "third": "j'explique j'explique",
        "third_tail": "et la même question revient",
        "fourth": "on promet on promet",
        "fourth_tail": "puis on décale encore",
    },
    {
        "first": "on ajuste on ajuste",
        "first_tail": "et le sujet reste flou",
        "second": "ça chauffe ça chauffe",
        "second_tail": "puis tout se calme",
        "third": "je relance je relance",
        "third_tail": "mais personne ne tranche",
        "fourth": "on prépare on prépare",
        "fourth_tail": "et la salle change encore",
    },
    {
        "first": "on corrige on corrige",
        "first_tail": "mais le bug se déplace",
        "second": "ça clignote ça clignote",
        "second_tail": "puis l'écran se fige",
        "third": "je reformule je reformule",
        "third_tail": "et le doute reste là",
        "fourth": "on rassure on rassure",
        "fourth_tail": "puis la pression remonte",
    },
    {
        "first": "on compare on compare",
        "first_tail": "et les chiffres racontent autre chose",
        "second": "ça repart ça repart",
        "second_tail": "puis ça cale au dernier moment",
        "third": "je détaille je détaille",
        "third_tail": "et pourtant ça coince encore",
        "fourth": "on annonce on annonce",
        "fourth_tail": "puis on nuance tout de suite",
    },
    {
        "first": "on teste on teste",
        "first_tail": "mais la confiance ne revient pas",
        "second": "ça tourne ça tourne",
        "second_tail": "puis le silence tombe",
        "third": "je rappelle je rappelle",
        "third_tail": "et personne ne répond vraiment",
        "fourth": "on signe on signe",
        "fourth_tail": "puis la dernière réserve ressort",
    },
]


INTENTIONAL_NOTES = [
    "La répétition porte l'insistance et doit rester intacte.",
    "La reprise du même groupe nominal est voulue, pas accidentelle.",
    "Le modèle doit ponctuer sans supprimer l'écho expressif.",
    "La frontière ici est conservative : répétition préservée, nettoyage léger seulement.",
]

EMPHASIS_NOTES = [
    "Le double intensif est volontaire et ne doit pas être réduit.",
    "La répétition d'intensité renforce l'appréciation orale.",
    "Ici, la correction se limite à la ponctuation autour d'une insistance voulue.",
    "Le modèle doit garder l'emphase redoublée telle quelle.",
]

SPOKEN_NOTES = [
    "Le marqueur oral répété porte l'insistance et doit survivre.",
    "La reformulation doit rester minimale autour d'une insistance parlée.",
    "La répétition en tête de phrase est volontaire, pas une disfluence à supprimer.",
    "Nettoyer la ponctuation sans effacer le tour oral répété.",
]

CONTRASTIVE_NOTES = [
    "La répétition sert à distinguer précisément une variante et doit être conservée.",
    "Le redoublement marque un contraste de référence, pas une erreur d'ASR.",
    "Ici, la répétition est sémantique : elle précise la bonne cible.",
    "Le modèle doit préserver le terme répété qui tranche entre deux options proches.",
]

RHETORICAL_NOTES = [
    "La reprise rythmique fait partie de l'effet rhétorique et doit rester.",
    "Le modèle doit ponctuer la cadence sans la lisser.",
    "La répétition de proposition structure l'oral et ne doit pas disparaître.",
    "Ici, le rythme répété porte le sens du contraste final.",
]


def build_intentional(start_idx: int) -> tuple[list[dict[str, str]], int]:
    rows = []
    idx = start_idx
    combos = list(product(CONTEXTS, INTENTIONAL_BUNDLES))
    for context, bundle in combos:
        variants = [
            (
                "intentional_repetition",
                f"{context} vraiment vraiment {bundle['main']}",
                finish(context, f"vraiment vraiment {bundle['main']}"),
                INTENTIONAL_NOTES[0],
            ),
            (
                "intentional_repetition",
                f"{context} {bundle['resource']} {bundle['resource']} il en faut pour {bundle['goal']}",
                finish(context, f"{bundle['resource']} {bundle['resource']}, il en faut pour {bundle['goal']}"),
                INTENTIONAL_NOTES[1],
            ),
            (
                "intentional_repetition",
                f"{context} pas maintenant pas maintenant {bundle['hold']}",
                finish(context, f"pas maintenant pas maintenant, {bundle['hold']}"),
                INTENTIONAL_NOTES[2],
            ),
            (
                "intentional_repetition",
                f"{context} encore encore {bundle['process']}",
                finish(context, f"encore encore {bundle['process']}"),
                INTENTIONAL_NOTES[3],
            ),
        ]
        for subcategory, raw, expected, notes in variants:
            rows.append(make_row(idx, subcategory, raw, expected, notes))
            idx += 1
    return rows, idx


def build_emphasis(start_idx: int) -> tuple[list[dict[str, str]], int]:
    rows = []
    idx = start_idx
    combos = list(product(CONTEXTS, EMPHASIS_BUNDLES))
    for context, bundle in combos:
        variants = [
            (
                "emphasis_repetition",
                f"{context} c'est très très {bundle['very']}",
                finish(context, f"c'est très très {bundle['very']}"),
                EMPHASIS_NOTES[0],
            ),
            (
                "emphasis_repetition",
                f"{context} c'est trop trop {bundle['too']}",
                finish(context, f"c'est trop trop {bundle['too']}"),
                EMPHASIS_NOTES[1],
            ),
            (
                "emphasis_repetition",
                f"{context} c'est bien bien {bundle['well']}",
                finish(context, f"c'est bien bien {bundle['well']}"),
                EMPHASIS_NOTES[2],
            ),
            (
                "emphasis_repetition",
                f"{context} c'est super super {bundle['super']}",
                finish(context, f"c'est super super {bundle['super']}"),
                EMPHASIS_NOTES[3],
            ),
        ]
        for subcategory, raw, expected, notes in variants:
            rows.append(make_row(idx, subcategory, raw, expected, notes))
            idx += 1
    return rows, idx


def build_spoken(start_idx: int) -> tuple[list[dict[str, str]], int]:
    rows = []
    idx = start_idx
    combos = list(product(CONTEXTS, SPOKEN_BUNDLES))
    for context, bundle in combos:
        variants = [
            (
                "spoken_emphasis",
                f"{context} oui oui {bundle['yes_clause']}",
                finish(context, f"oui oui, {bundle['yes_clause']}"),
                SPOKEN_NOTES[0],
            ),
            (
                "spoken_emphasis",
                f"{context} si si {bundle['insist_clause']}",
                finish(context, f"si si, {bundle['insist_clause']}"),
                SPOKEN_NOTES[1],
            ),
            (
                "spoken_emphasis",
                f"{context} allez allez {bundle['urge_clause']}",
                finish(context, f"allez allez, {bundle['urge_clause']}"),
                SPOKEN_NOTES[2],
            ),
            (
                "spoken_emphasis",
                f"{context} vite vite {bundle['hurry_clause']}",
                finish(context, f"vite vite, {bundle['hurry_clause']}"),
                SPOKEN_NOTES[3],
            ),
        ]
        for subcategory, raw, expected, notes in variants:
            rows.append(make_row(idx, subcategory, raw, expected, notes))
            idx += 1
    return rows, idx


def build_contrastive(start_idx: int) -> tuple[list[dict[str, str]], int]:
    rows = []
    idx = start_idx
    combos = list(product(CONTEXTS, CONTRASTIVE_BUNDLES))
    for context, bundle in combos:
        variants = [
            (
                "contrastive_repetition",
                f"{context} je veux {bundle['want_target']} pas {bundle['want_alt']}",
                finish(context, f"je veux {bundle['want_target']}, pas {bundle['want_alt']}"),
                CONTRASTIVE_NOTES[0],
            ),
            (
                "contrastive_repetition",
                f"{context} on garde {bundle['keep_target']} pas {bundle['keep_alt']}",
                finish(context, f"on garde {bundle['keep_target']}, pas {bundle['keep_alt']}"),
                CONTRASTIVE_NOTES[1],
            ),
            (
                "contrastive_repetition",
                f"{context} je parle {bundle['speak_target']} pas {bundle['speak_alt']}",
                finish(context, f"je parle {bundle['speak_target']}, pas {bundle['speak_alt']}"),
                CONTRASTIVE_NOTES[2],
            ),
            (
                "contrastive_repetition",
                f"{context} on a besoin {bundle['need_target']} pas {bundle['need_alt']}",
                finish(context, f"on a besoin {bundle['need_target']}, pas {bundle['need_alt']}"),
                CONTRASTIVE_NOTES[3],
            ),
        ]
        for subcategory, raw, expected, notes in variants:
            rows.append(make_row(idx, subcategory, raw, expected, notes))
            idx += 1
    return rows, idx


def build_rhetorical(start_idx: int) -> tuple[list[dict[str, str]], int]:
    rows = []
    idx = start_idx
    combos = list(product(CONTEXTS, RHETORICAL_BUNDLES))
    for context, bundle in combos:
        variants = [
            (
                "rhetorical_repetition",
                f"{context} {bundle['first']} {bundle['first_tail']}",
                finish(context, f"{bundle['first']}, {bundle['first_tail']}"),
                RHETORICAL_NOTES[0],
            ),
            (
                "rhetorical_repetition",
                f"{context} {bundle['second']} {bundle['second_tail']}",
                finish(context, f"{bundle['second']}, {bundle['second_tail']}"),
                RHETORICAL_NOTES[1],
            ),
            (
                "rhetorical_repetition",
                f"{context} {bundle['third']} {bundle['third_tail']}",
                finish(context, f"{bundle['third']}, {bundle['third_tail']}"),
                RHETORICAL_NOTES[2],
            ),
            (
                "rhetorical_repetition",
                f"{context} {bundle['fourth']} {bundle['fourth_tail']}",
                finish(context, f"{bundle['fourth']}, {bundle['fourth_tail']}"),
                RHETORICAL_NOTES[3],
            ),
        ]
        for subcategory, raw, expected, notes in variants:
            rows.append(make_row(idx, subcategory, raw, expected, notes))
            idx += 1
    return rows, idx


def validate(rows: list[dict[str, str]]) -> None:
    expected_counts = {
        "intentional_repetition": 140,
        "emphasis_repetition": 140,
        "spoken_emphasis": 140,
        "contrastive_repetition": 140,
        "rhetorical_repetition": 140,
    }
    counts = {key: 0 for key in expected_counts}
    seen_ids = set()
    seen_pairs = set()
    for row in rows:
        if set(row) != {"id", "category", "subcategory", "raw", "expected", "language", "notes"}:
            raise ValueError(f"invalid keys: {row.keys()}")
        if row["language"] != "fr" or row["category"] != "round5_patch":
            raise ValueError("invalid fixed fields")
        if not row["raw"] or not row["expected"] or not row["notes"]:
            raise ValueError("empty field detected")
        if "<think>" in row["raw"] or "</think>" in row["raw"] or "<think>" in row["expected"] or "</think>" in row["expected"]:
            raise ValueError("forbidden tag detected")
        if row["id"] in seen_ids:
            raise ValueError(f"duplicate id {row['id']}")
        seen_ids.add(row["id"])
        pair = (row["subcategory"], row["raw"], row["expected"])
        if pair in seen_pairs:
            raise ValueError(f"duplicate row {pair}")
        seen_pairs.add(pair)
        counts[row["subcategory"]] += 1
    if len(rows) != 700:
        raise ValueError(f"wrong row count: {len(rows)}")
    if counts != expected_counts:
        raise ValueError(f"wrong distribution: {counts}")


def main() -> None:
    rows = []
    idx = 1
    for builder in (
        build_intentional,
        build_emphasis,
        build_spoken,
        build_contrastive,
        build_rhetorical,
    ):
        built, idx = builder(idx)
        rows.extend(built)
    validate(rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
