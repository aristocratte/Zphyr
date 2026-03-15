from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


ROOT = Path("/Users/aris/Documents/VoiceProject/Zphyr")
OUT = ROOT / "Evals/datasets/raw/patch/.tmp_round5/agent_c_protected_terms_verbatim.jsonl"


def cap(text: str) -> str:
    text = " ".join(text.split())
    return text[:1].upper() + text[1:]


def punctuate(text: str) -> str:
    text = cap(text)
    return text if text.endswith(".") else f"{text}."


def row(row_id: str, subcategory: str, raw: str, expected: str, notes: str) -> dict[str, str]:
    return {
        "id": row_id,
        "category": "round5_patch",
        "subcategory": subcategory,
        "raw": raw,
        "expected": expected,
        "language": "fr",
        "notes": notes,
    }


def build_triplet(
    token: str,
    subcategory: str,
    opener: str,
    context: str,
    stake: str,
    boundary: str,
    note: str,
) -> list[dict[str, str]]:
    raw1 = f"{opener} on garde {token} tel quel {context}"
    exp1 = punctuate(f"{opener}, on garde {token} tel quel {context}")
    raw2 = f"{opener} je peux reformuler le reste mais {token} doit rester tel quel {stake}"
    exp2 = punctuate(f"{opener}, je peux reformuler le reste, mais {token} doit rester tel quel {stake}")
    raw3 = f"{opener} je veux voir {token} tel quel {boundary}"
    exp3 = punctuate(f"{opener}, je veux voir {token} tel quel {boundary}")
    return [
        row("", subcategory, raw1, exp1, note),
        row("", subcategory, raw2, exp2, note),
        row("", subcategory, raw3, exp3, note),
    ]


def build_config_env_vars() -> list[dict[str, str]]:
    sub = "config_env_vars"
    openers = [
        "dans ce ticket",
        "pour la revue de ce matin",
        "sur la branche de release",
        "dans le message au support",
        "avant la mise en production",
        "dans la check-list de merge",
        "sur la capture d'écran",
        "dans le commentaire du PR",
        "dans la note pour l'équipe infra",
        "dans le script de déploiement",
        "dans l'alerte d'hier soir",
        "dans le récap de sprint",
        "dans la consigne du runbook",
        "dans le tableau d'incident",
        "sur la page de debug",
        "dans le mail au client",
        "dans la procédure d'onboarding",
        "dans le doc d'exploitation",
        "dans la checklist QA",
        "dans le compte rendu",
        "dans la consigne pour l'astreinte",
        "dans la description de la tâche",
        "dans le rappel Slack",
        "dans le bloc de configuration",
        "dans le log de validation",
    ]
    contexts = [
        "dans le fichier d'exemple",
        "dans la phrase du commit",
        "dans le message final",
        "dans le copier-coller du runbook",
        "dans la capture envoyée au support",
        "dans la doc de configuration",
        "dans le résumé de l'incident",
        "dans le rappel de sécurité",
        "dans l'instruction du ticket",
        "dans le tableau de suivi",
        "dans la checklist de mise en ligne",
        "dans la procédure de reprise",
        "dans le commentaire de revue",
        "dans la note de version",
        "dans le point d'équipe",
        "dans la procédure d'accès",
        "dans le message de debug",
        "dans le rapport quotidien",
        "dans le guide de démarrage",
        "dans le patch temporaire",
        "dans le protocole de test",
        "dans le mémo de support",
        "dans l'export de config",
        "dans la consigne partagée",
        "dans la trace jointe",
    ]
    stakes = [
        "quand je reformule la consigne",
        "même si je raccourcis la phrase",
        "quand je nettoie la ponctuation",
        "si je coupe la phrase en deux",
        "quand je retire les hésitations",
        "dans la version envoyée au client",
        "dans le résumé pour l'équipe",
        "quand je réécris le titre",
        "dans le texte qu'on relit",
        "dans la version finale du mail",
        "dans la copie du ticket",
        "quand je simplifie l'explication",
        "dans la note publiée",
        "si je compacte le paragraphe",
        "quand je prépare le handoff",
        "dans la relance du support",
        "quand je nettoie le compte rendu",
        "dans la capture annotée",
        "sur la fiche d'incident",
        "dans la procédure révisée",
        "dans la version lue à voix haute",
        "quand je retire les répétitions",
        "sur le message d'escalade",
        "dans la réponse du soir",
        "dans la consigne finale",
    ]
    boundaries = [
        "et pas la variable d'à côté",
        "sans toucher au reste de la ligne",
        "même si je reformule le commentaire",
        "pas la phrase entière",
        "même dans la version raccourcie",
        "et pas le texte autour",
        "dans l'exemple affiché",
        "sur la capture envoyée",
        "dans la checklist qu'on partage",
        "avant d'envoyer la note",
        "dans la phrase de rappel",
        "sur le panneau d'alerte",
        "dans le patch temporaire",
        "dans le mail d'escalade",
        "sur la page de debug",
        "dans le résumé du bug",
        "dans la procédure qu'on archive",
        "dans le commentaire du diff",
        "dans la doc de crise",
        "même si le reste change",
        "dans le paragraphe d'ouverture",
        "dans la relance du client",
        "sur la fiche de validation",
        "dans la capture du serveur",
        "dans la phrase qu'on cite",
    ]
    tokens = ["JWT_SECRET", "NEXT_PUBLIC_API_URL", "JWT_SECRET", "NEXT_PUBLIC_API_URL", "JWT_SECRET"]
    note_tokens = {
        "JWT_SECRET": "Préserver JWT_SECRET à l'identique malgré un nettoyage léger.",
        "NEXT_PUBLIC_API_URL": "Préserver NEXT_PUBLIC_API_URL à l'identique malgré un nettoyage léger.",
    }
    rows: list[dict[str, str]] = []
    for i in range(25):
        token = tokens[i % len(tokens)]
        rows.extend(
            build_triplet(
                token,
                sub,
                openers[i],
                contexts[i],
                stakes[i],
                boundaries[i],
                note_tokens[token],
            )
        )
    return rows


def build_package_names() -> list[dict[str, str]]:
    sub = "package_names"
    tokens = ["PrismaClient", "React Query", "TanStack Query", "useQuery", "useMutation"]
    openers = [
        "dans ce compte rendu",
        "pour la démo de demain",
        "dans la note de migration",
        "dans le résumé du bug",
        "sur le ticket produit",
        "dans le commentaire de revue",
        "dans la doc d'architecture",
        "pour le message au backend",
        "dans le guide de contribution",
        "sur la tâche du sprint",
        "dans le mail à l'équipe mobile",
        "dans la consigne de pairing",
        "dans la procédure de reprise",
        "pour le support niveau deux",
        "dans le handoff du soir",
        "sur la page interne",
        "dans l'ordre du jour",
        "dans la note de cadrage",
        "dans la consigne envoyée au freelance",
        "dans la relance du client",
        "sur le tableau de dette",
        "dans le ticket d'onboarding",
        "dans le récap de la review",
        "pour le point d'avancement",
        "dans le protocole de test",
    ]
    contexts = [
        "quand on cite la dépendance concernée",
        "dans l'exemple du correctif",
        "dans la phrase qui décrit la stack",
        "dans le passage où on parle du cache",
        "dans la ligne copiée du ticket",
        "dans le commentaire qu'on garde tel quel",
        "dans la version envoyée au support",
        "dans la checklist de merge",
        "dans la note affichée au tableau",
        "dans la consigne de debug",
        "dans le passage relu par l'équipe",
        "dans le message épinglé",
        "dans la note de version",
        "dans l'explication qu'on simplifie",
        "dans le texte repris dans Confluence",
        "dans le résumé fait au client",
        "dans la phrase qu'on raccourcit",
        "dans l'instruction ajoutée au runbook",
        "dans la capture commentée",
        "dans le mémo de release",
        "dans le rappel partagé sur Slack",
        "dans la section de contexte",
        "dans la relance du QA",
        "dans la note jointe au diff",
        "dans l'explication du hotfix",
    ]
    stakes = [
        "même si le reste de la phrase change",
        "quand je coupe une subordonnée",
        "si je retire une hésitation au début",
        "quand je simplifie le message",
        "dans la reformulation finale",
        "si j'ajoute juste une virgule",
        "dans la version concise du ticket",
        "quand je clarifie la consigne",
        "dans la synthèse envoyée au client",
        "si je nettoie la ponctuation",
        "dans la note reprise par le support",
        "quand je compacte le paragraphe",
        "dans la réponse au reviewer",
        "si je raccourcis l'exemple",
        "dans le résumé d'incident",
        "dans le patch qu'on décrit",
        "sur la slide de démo",
        "dans le commentaire publié",
        "si je supprime un mot vide",
        "dans la relance du matin",
        "dans la note d'équipe",
        "quand je retire un doublon oral",
        "dans la version corrigée",
        "dans le compte rendu final",
        "si je réécris l'ouverture",
    ]
    boundaries = [
        "et pas le nom traduit",
        "sans toucher au terme technique",
        "même si la phrase devient plus courte",
        "pas la librairie elle-même",
        "dans le texte qu'on partage",
        "sur la capture annotée",
        "dans le résumé qu'on publie",
        "dans la doc qu'on met à jour",
        "dans le message au support",
        "dans le ticket client",
        "sur la note d'incident",
        "dans la phrase d'ouverture",
        "dans la checklist du sprint",
        "sur la slide finale",
        "dans la procédure de debug",
        "dans le résumé de livraison",
        "dans la consigne pour demain",
        "dans la réponse du reviewer",
        "dans le tableau partagé",
        "sur la page d'escalade",
        "dans le mail interne",
        "dans le texte du changelog",
        "même quand on reformule autour",
        "dans la note du chef de projet",
        "dans l'exemple repris tel quel",
    ]
    notes = {
        "PrismaClient": "Préserver PrismaClient tel quel dans une phrase de stack.",
        "React Query": "Préserver React Query tel quel dans une phrase de stack.",
        "TanStack Query": "Préserver TanStack Query tel quel dans une phrase de stack.",
        "useQuery": "Préserver useQuery tel quel dans une phrase de stack.",
        "useMutation": "Préserver useMutation tel quel dans une phrase de stack.",
    }
    rows: list[dict[str, str]] = []
    for i in range(25):
        token = tokens[i % len(tokens)]
        rows.extend(
            build_triplet(token, sub, openers[i], contexts[i], stakes[i], boundaries[i], notes[token])
        )
    return rows


def build_terminal_commands() -> list[dict[str, str]]:
    sub = "terminal_commands"
    tokens = ["rollback", "deploy", "hotfix", "build", "cache"]
    openers = [
        "sur la procédure d'astreinte",
        "dans le message au release manager",
        "avant la fenêtre de maintenance",
        "dans le ticket d'incident",
        "sur le canal d'urgence",
        "dans la note de déploiement",
        "au moment du handoff",
        "dans le rappel de ce soir",
        "sur la checklist ops",
        "dans le point avec l'infra",
        "dans la réponse au support",
        "dans le brief de mise en ligne",
        "sur la consigne du runbook",
        "dans la note du post-mortem",
        "dans la documentation interne",
        "dans le mail envoyé aux astreintes",
        "sur la fiche de production",
        "dans l'explication du hotfix",
        "dans le suivi du build cassé",
        "dans le message épinglé du projet",
        "dans le rappel du scrum",
        "dans le commentaire du PR d'urgence",
        "sur la fiche de reprise",
        "dans la relance de validation",
        "dans la synthèse technique",
    ]
    contexts = [
        "quand on parle de l'action à lancer",
        "dans la phrase qui décrit l'étape",
        "dans le passage qu'on cite au support",
        "dans le résumé que tout le monde relit",
        "dans la consigne qu'on partage",
        "dans l'exemple du runbook",
        "dans la ligne envoyée au client interne",
        "dans le message d'escalade",
        "dans la note de reprise",
        "dans la check-list d'incident",
        "dans la relance à l'équipe infra",
        "dans le commentaire qu'on garde",
        "dans la procédure d'urgence",
        "dans la fiche lue à voix haute",
        "dans le mail qui résume l'action",
        "dans la consigne publiée",
        "dans la note collée au ticket",
        "dans le rappel du soir",
        "dans le journal d'exploitation",
        "dans le protocole de bascule",
        "dans le paragraphe de conclusion",
        "dans le compte rendu du build",
        "dans le tableau de suivi",
        "dans la procédure courte",
        "dans la note d'après incident",
    ]
    stakes = [
        "même si je reformule l'étape",
        "quand je nettoie la ponctuation",
        "si je retire un mot d'appui",
        "dans la copie du runbook",
        "dans le résumé final",
        "quand je compacte la phrase",
        "si je coupe le message en deux",
        "dans la version lue au téléphone",
        "dans la note envoyée aux ops",
        "si je simplifie le contexte",
        "dans la synthèse du ticket",
        "sur la fiche de crise",
        "dans le commentaire du reviewer",
        "dans la note d'équipe",
        "sur la page d'incident",
        "dans la version courte",
        "quand je retire une hésitation",
        "dans la phrase que je corrige",
        "dans la procédure finale",
        "sur la consigne affichée",
        "dans la relance de nuit",
        "dans le compte rendu client",
        "dans le texte du changelog",
        "quand je réécris l'introduction",
        "sur la note de validation",
    ]
    boundaries = [
        "et pas l'action traduite",
        "sans changer le mot opératoire",
        "même si le reste devient plus fluide",
        "dans le texte partagé avec l'astreinte",
        "sur la capture du ticket",
        "dans la consigne qu'on copie",
        "dans la note envoyée à minuit",
        "sur la fiche d'exploitation",
        "dans le journal interne",
        "dans le résumé du runbook",
        "dans le mémo transmis au support",
        "dans la page de bascule",
        "dans le mail interne",
        "dans la note de crise",
        "sur la slide du point ops",
        "dans la relance matinale",
        "dans le diff commenté",
        "dans la phrase de conclusion",
        "même quand je reformule autour",
        "dans la version publiée",
        "dans la procédure relue",
        "dans le point de production",
        "dans la checklist d'urgence",
        "dans la note jointe",
        "sur le message épinglé",
    ]
    notes = {
        "rollback": "Préserver rollback tel quel dans une consigne terminale.",
        "deploy": "Préserver deploy tel quel dans une consigne terminale.",
        "hotfix": "Préserver hotfix tel quel dans une consigne terminale.",
        "build": "Préserver build tel quel dans une consigne terminale.",
        "cache": "Préserver cache tel quel dans une consigne terminale.",
    }
    rows: list[dict[str, str]] = []
    for i in range(25):
        token = tokens[i % len(tokens)]
        rows.extend(
            build_triplet(token, sub, openers[i], contexts[i], stakes[i], boundaries[i], notes[token])
        )
    return rows


def build_framework_names() -> list[dict[str, str]]:
    sub = "framework_names"
    tokens = ["React Query", "TanStack Query", "useQuery", "useMutation", "PrismaClient"]
    openers = [
        "sur la fiche de migration",
        "dans la note de cadrage",
        "pour le pairing de demain",
        "dans le commentaire du mentor",
        "sur le ticket de perf",
        "dans la synthèse de l'atelier",
        "pour le guide de debug",
        "dans la relance au backend",
        "sur la carte technique",
        "dans le mail de revue",
        "dans la consigne au stagiaire",
        "dans la page de référence",
        "sur la note du sprint",
        "dans la doc de support",
        "pour le brief du matin",
        "sur la capture partagée",
        "dans la note de démo",
        "dans la page d'architecture",
        "sur la tâche de refonte",
        "dans le fil de discussion",
        "pour la séance de QA",
        "dans la note de passation",
        "sur la fiche de correction",
        "dans le rappel du lead",
        "dans le compte rendu du standup",
    ]
    contexts = [
        "quand on cite le framework concerné",
        "dans le passage qui explique la requête",
        "dans la phrase qui décrit le hook",
        "dans la ligne recopiée du bug",
        "dans le résumé qu'on envoie au support",
        "dans la doc qu'on simplifie",
        "dans la consigne de revue",
        "dans la checklist qu'on diffuse",
        "dans la note du ticket",
        "dans la slide de la démo",
        "dans la version envoyée au client interne",
        "dans le mémo d'incident",
        "dans le guide qu'on met à jour",
        "dans le paragraphe d'ouverture",
        "dans la note affichée en réunion",
        "dans la phrase qui reste après coupe",
        "dans la relance de l'après-midi",
        "dans la synthèse de la review",
        "dans le mail que tout le monde relit",
        "dans la consigne de handoff",
        "dans la phrase reprise dans le runbook",
        "dans le mémo partagé",
        "dans l'exemple donné au support",
        "dans la note jointe au ticket",
        "dans l'explication du patch",
    ]
    stakes = [
        "même si je reformule le reste",
        "quand j'ajoute une virgule",
        "si je retire un détour oral",
        "dans la copie finale",
        "quand je coupe une précision",
        "dans la version raccourcie",
        "si je clarifie l'instruction",
        "dans le commentaire final",
        "quand je compacte le paragraphe",
        "sur la slide validée",
        "dans la réponse du reviewer",
        "dans le résumé d'équipe",
        "si je nettoie la ponctuation",
        "dans la note consolidée",
        "dans le ticket prêt à partir",
        "dans la reformulation du support",
        "sur le message épinglé",
        "dans la fiche de validation",
        "dans la phrase relue à voix haute",
        "dans la relance du chef de projet",
        "sur la page publiée",
        "dans le résumé de backlog",
        "dans le texte du changelog",
        "dans le guide partagé",
        "si je supprime un mot vide",
    ]
    boundaries = [
        "et pas la paraphrase autour",
        "sans toucher au nom du framework",
        "même dans la version courte",
        "dans le texte qu'on cite",
        "sur la capture jointe",
        "dans la consigne du pair",
        "dans la note du sprint",
        "sur la fiche de debug",
        "dans le mail interne",
        "dans la réponse au QA",
        "dans le ticket d'architecture",
        "dans la note finale",
        "dans la synthèse partagée",
        "sur le tableau d'incident",
        "dans la slide de demain",
        "dans la doc qu'on archive",
        "dans la check-list du sprint",
        "dans le message de suivi",
        "dans la phrase du patch",
        "même quand je reformule autour",
        "dans la revue qu'on publie",
        "dans la note d'onboarding",
        "dans le support de démo",
        "dans le résumé qu'on envoie",
        "dans l'exemple qu'on lit",
    ]
    notes = {
        "React Query": "Préserver React Query tel quel dans un contexte de framework.",
        "TanStack Query": "Préserver TanStack Query tel quel dans un contexte de framework.",
        "useQuery": "Préserver useQuery tel quel dans un contexte de framework.",
        "useMutation": "Préserver useMutation tel quel dans un contexte de framework.",
        "PrismaClient": "Préserver PrismaClient tel quel dans un contexte de framework.",
    }
    rows: list[dict[str, str]] = []
    for i in range(25):
        token = tokens[i % len(tokens)]
        rows.extend(
            build_triplet(token, sub, openers[i], contexts[i], stakes[i], boundaries[i], notes[token])
        )
    return rows


def build_product_names() -> list[dict[str, str]]:
    sub = "product_names"
    tokens = ["GitHub Actions", "Playwright", "Vitest", "Docker", "Redis"]
    openers = [
        "dans la note d'exploitation",
        "sur le ticket de QA",
        "dans le mail de livraison",
        "pour le point avec le client",
        "dans la relance du support",
        "sur la page de statut",
        "dans le résumé du bug",
        "pour le brief de production",
        "dans la documentation de test",
        "sur la fiche d'incident",
        "dans la consigne du soir",
        "sur la capture partagée",
        "dans la synthèse du sprint",
        "pour la revue d'architecture",
        "dans le tableau de suivi",
        "sur la note de mise en ligne",
        "dans le message au QA",
        "pour le ticket de reprise",
        "sur la checklist produit",
        "dans le compte rendu d'équipe",
        "dans le rappel du lead",
        "pour le standup de demain",
        "sur la page de debug",
        "dans la note du changelog",
        "dans le résumé d'après incident",
    ]
    contexts = [
        "quand on cite l'outil concerné",
        "dans la phrase du rapport",
        "dans la consigne qu'on garde",
        "dans la note qu'on simplifie",
        "dans le message envoyé au support",
        "dans l'exemple qu'on reprend",
        "dans la relance de l'équipe",
        "dans la checklist de validation",
        "dans la procédure qu'on relit",
        "dans la note transmise au client interne",
        "dans le ticket qu'on reformule",
        "dans la phrase de l'incident",
        "dans le résumé affiché en réunion",
        "dans le passage que j'abrège",
        "dans la version finale du mail",
        "dans la doc mise à jour",
        "dans la slide de démo",
        "dans le journal d'exploitation",
        "dans la synthèse du patch",
        "dans le commentaire de revue",
        "dans la fiche de suivi",
        "dans la note qui part en prod",
        "dans la procédure de reprise",
        "dans le tableau du sprint",
        "dans le message du runbook",
    ]
    stakes = [
        "même si je nettoie la phrase",
        "quand j'ajoute juste une virgule",
        "si je retire une hésitation",
        "dans la reformulation finale",
        "si je coupe le paragraphe",
        "dans la copie client",
        "quand je simplifie le contexte",
        "dans le résumé du ticket",
        "sur la note du matin",
        "dans la version lue à voix haute",
        "dans la consigne revue",
        "sur la capture annotée",
        "dans le texte du changelog",
        "dans la slide validée",
        "quand je compacte l'explication",
        "dans la page publiée",
        "dans la relance interne",
        "sur la fiche d'astreinte",
        "dans la note du support",
        "dans la réponse au reviewer",
        "dans le guide d'onboarding",
        "dans le handoff du soir",
        "dans la note d'équipe",
        "quand je retire un mot vide",
        "dans la synthèse finale",
    ]
    boundaries = [
        "et pas la traduction du nom",
        "sans toucher à la casse",
        "même si le reste change",
        "dans le texte qu'on partage",
        "sur la fiche de suivi",
        "dans le compte rendu",
        "dans la doc d'escalade",
        "sur la slide de démo",
        "dans le résumé de crise",
        "dans le mail interne",
        "sur le message épinglé",
        "dans la phrase d'ouverture",
        "dans la procédure publiée",
        "dans la note d'incident",
        "dans le ticket client",
        "dans la réponse au support",
        "dans le guide relu",
        "dans la version courte",
        "dans le tableau de bord",
        "même quand je reformule autour",
        "dans la note de sprint",
        "dans la checklist d'astreinte",
        "dans la synthèse envoyée",
        "sur la page interne",
        "dans le passage qu'on cite",
    ]
    notes = {
        "GitHub Actions": "Préserver GitHub Actions tel quel malgré la ponctuation ajoutée.",
        "Playwright": "Préserver Playwright tel quel malgré la ponctuation ajoutée.",
        "Vitest": "Préserver Vitest tel quel malgré la ponctuation ajoutée.",
        "Docker": "Préserver Docker tel quel malgré la ponctuation ajoutée.",
        "Redis": "Préserver Redis tel quel malgré la ponctuation ajoutée.",
    }
    rows: list[dict[str, str]] = []
    for i in range(25):
        token = tokens[i % len(tokens)]
        rows.extend(
            build_triplet(token, sub, openers[i], contexts[i], stakes[i], boundaries[i], notes[token])
        )
    return rows


def build_version_numbers() -> list[dict[str, str]]:
    sub = "version_numbers"
    tokens = ["OAuth 2.0", "Playwright 1.52.0", "Vitest 2.1.4", "Docker 25.0.3", "Redis 7.2.4"]
    openers = [
        "dans la note de compatibilité",
        "sur la fiche de migration",
        "dans le mail au support",
        "pour le ticket de mise à niveau",
        "dans la checklist de release",
        "sur le tableau d'incident",
        "dans la synthèse du sprint",
        "dans la consigne QA",
        "sur la doc de validation",
        "dans la note de version",
        "sur la page d'architecture",
        "dans le brief du matin",
        "pour le message au client",
        "dans le ticket de sécurité",
        "sur la procédure d'escalade",
        "dans la note du post-mortem",
        "sur la slide de démo",
        "dans la page de debug",
        "sur la fiche d'onboarding",
        "dans la relance de review",
        "pour la note de production",
        "sur la doc d'exploitation",
        "dans le guide de reprise",
        "dans le ticket backlog",
        "dans le résumé de livraison",
    ]
    contexts = [
        "quand on cite la version exacte",
        "dans la phrase qui décrit le prérequis",
        "dans la ligne copiée du ticket",
        "dans la note qu'on partage",
        "dans la procédure qu'on relit",
        "dans le résumé qu'on envoie",
        "dans l'exemple du runbook",
        "dans le rappel au support",
        "dans la checklist technique",
        "dans la note client",
        "dans la synthèse du problème",
        "dans le passage qu'on reformule",
        "dans la relance de validation",
        "dans le mémo publié",
        "dans la fiche d'astreinte",
        "dans la réponse au reviewer",
        "dans le journal d'exploitation",
        "dans la note d'ouverture",
        "dans la page interne",
        "dans la doc consolidée",
        "dans la version courte du mail",
        "dans la phrase qu'on abrège",
        "dans le changelog relu",
        "dans la capture commentée",
        "dans la consigne finale",
    ]
    stakes = [
        "même si je simplifie le reste",
        "quand je retire une hésitation",
        "dans la copie finale",
        "si je nettoie la ponctuation",
        "dans la note envoyée à l'équipe",
        "sur la fiche de suivi",
        "dans le paragraphe de conclusion",
        "quand je coupe une précision",
        "dans la relance du soir",
        "si je compacte le message",
        "dans la version lue à voix haute",
        "dans la note publiée",
        "sur la checklist d'incident",
        "dans le guide partagé",
        "quand je clarifie l'explication",
        "dans la réponse au client interne",
        "dans le résumé du ticket",
        "sur la page de statut",
        "dans la note du support",
        "dans la synthèse d'équipe",
        "quand je retire un doublon oral",
        "dans la doc archivée",
        "sur la slide validée",
        "dans la version corrigée",
        "dans le compte rendu final",
    ]
    boundaries = [
        "et pas une version arrondie",
        "sans toucher aux chiffres",
        "même si la phrase change autour",
        "dans le texte qu'on partage",
        "sur la capture de validation",
        "dans le ticket client",
        "dans le journal d'incident",
        "dans la doc d'escalade",
        "sur la note d'équipe",
        "dans le mail interne",
        "dans la consigne de sécurité",
        "dans le résumé de migration",
        "sur la page de référence",
        "dans le compte rendu",
        "dans la checklist finale",
        "dans le guide d'installation",
        "dans la relance du support",
        "dans l'exemple publié",
        "dans la note d'onboarding",
        "même quand je reformule autour",
        "dans la procédure affichée",
        "dans le changelog du soir",
        "sur la fiche de reprise",
        "dans la version envoyée",
        "dans le patch qu'on décrit",
    ]
    notes = {
        "OAuth 2.0": "Préserver OAuth 2.0 tel quel avec sa numérotation.",
        "Playwright 1.52.0": "Préserver Playwright 1.52.0 tel quel avec sa numérotation.",
        "Vitest 2.1.4": "Préserver Vitest 2.1.4 tel quel avec sa numérotation.",
        "Docker 25.0.3": "Préserver Docker 25.0.3 tel quel avec sa numérotation.",
        "Redis 7.2.4": "Préserver Redis 7.2.4 tel quel avec sa numérotation.",
    }
    rows: list[dict[str, str]] = []
    for i in range(25):
        token = tokens[i % len(tokens)]
        rows.extend(
            build_triplet(token, sub, openers[i], contexts[i], stakes[i], boundaries[i], notes[token])
        )
    return rows


def build_filenames_and_paths() -> list[dict[str, str]]:
    sub = "filenames_and_paths"
    tokens = [
        ("schema.prisma", "/srv/app/backend/prisma/schema.prisma"),
        ("package.json", "/srv/app/frontend/package.json"),
        ("tsconfig.json", "/srv/app/frontend/tsconfig.json"),
        ("vite.config.ts", "/srv/app/frontend/vite.config.ts"),
        ("docker-compose.yml", "/srv/app/infra/docker-compose.yml"),
        ("docker-compose.prod.yml", "/srv/app/infra/docker-compose.prod.yml"),
        ("next.config.js", "/srv/app/frontend/next.config.js"),
    ]
    openers = [
        "dans la note de déploiement",
        "sur le ticket d'infra",
        "dans la procédure de reprise",
        "dans le mail au backend",
        "sur la fiche de debug",
        "dans le changelog",
        "dans le guide d'onboarding",
        "pour la revue de code",
        "dans le post-mortem",
        "sur la doc de build",
        "dans la page de production",
        "dans la relance du support",
        "sur le résumé du sprint",
        "dans la note du QA",
        "dans la checklist ops",
        "dans la page de runbook",
        "sur la fiche de validation",
        "dans la consigne du soir",
        "dans le brief technique",
        "sur le tableau de suivi",
        "dans la note d'incident",
        "sur la checklist produit",
        "dans le ticket backlog",
        "dans le mail de handoff",
        "sur la synthèse de migration",
    ]
    contexts = [
        "quand on cite le chemin exact",
        "dans la ligne que je recopie",
        "dans la phrase qui décrit le fichier",
        "dans le rappel envoyé à l'équipe",
        "dans la note qu'on partage",
        "dans le passage qu'on reformule",
        "dans la checklist de correction",
        "dans le résumé qu'on publie",
        "dans la procédure qu'on relit",
        "dans le commentaire du reviewer",
        "dans la note jointe au ticket",
        "dans la doc qu'on simplifie",
        "dans le support de démo",
        "dans le mémo d'incident",
        "dans le texte repris dans le runbook",
        "dans la version courte du mail",
        "dans la fiche de reprise",
        "dans la page interne",
        "dans la note consolidée",
        "dans la phrase lue à voix haute",
        "dans le résumé du build",
        "dans la capture annotée",
        "dans la réponse au client interne",
        "dans la note de validation",
        "dans la procédure finale",
    ]
    stakes = [
        "même si je nettoie le reste",
        "quand je coupe une précision",
        "dans la copie finale",
        "si je retire une hésitation",
        "sur la fiche de suivi",
        "dans le journal d'exploitation",
        "dans la note publiée",
        "quand je simplifie le contexte",
        "dans la relance du soir",
        "dans la synthèse d'équipe",
        "sur la page d'incident",
        "dans la version envoyée au support",
        "dans le guide partagé",
        "quand j'ajoute juste une virgule",
        "dans le ticket prêt à partir",
        "sur la slide de démo",
        "dans la note de production",
        "dans le commentaire de revue",
        "dans la procédure relue",
        "dans le compte rendu final",
        "quand je retire un mot vide",
        "dans le changelog du soir",
        "sur la note de sprint",
        "dans la réponse du reviewer",
        "dans la relance du QA",
    ]
    boundaries = [
        "et pas une version simplifiée",
        "sans toucher au nom du fichier",
        "même si la phrase change autour",
        "dans le texte qu'on partage",
        "sur la capture qu'on annote",
        "dans la doc d'escalade",
        "dans le résumé de migration",
        "dans le mail interne",
        "sur la checklist de reprise",
        "dans la note du client interne",
        "sur la page d'architecture",
        "dans le compte rendu",
        "dans la procédure qu'on archive",
        "dans la relance du support",
        "dans la phrase de conclusion",
        "sur la fiche d'astreinte",
        "dans le ticket de suivi",
        "dans le guide d'onboarding",
        "dans la synthèse du runbook",
        "même quand je reformule autour",
        "dans le message épinglé",
        "dans la note du sprint",
        "dans le changelog partagé",
        "dans la version courte",
        "dans l'exemple qu'on cite",
    ]
    rows: list[dict[str, str]] = []
    for i in range(25):
        token, path = tokens[i % len(tokens)]
        note = f"Préserver {token} tel quel ainsi que le chemin associé."
        opener = openers[i]
        context = f"{contexts[i]} pour {path}"
        stake = f"{stakes[i]} quand je parle de {token}"
        boundary = f"{boundaries[i]} autour de {path}"
        rows.extend(build_triplet(token, sub, opener, context, stake, boundary, note))
    return rows


def build_mixed_fr_en_terms() -> list[dict[str, str]]:
    sub = "mixed_fr_en_terms"
    token_pairs = [
        ("backend", "frontend"),
        ("endpoint", "production"),
        ("prompt", "dataset"),
        ("feature flag", "validation"),
        ("deploy", "hotfix"),
        ("build", "cache"),
        ("backend", "endpoint"),
        ("frontend", "feature flag"),
        ("prompt", "production"),
        ("dataset", "validation"),
        ("deploy", "production"),
        ("hotfix", "backend"),
        ("cache", "frontend"),
        ("feature flag", "endpoint"),
        ("prompt", "build"),
        ("dataset", "cache"),
        ("validation", "production"),
        ("deploy", "dataset"),
        ("hotfix", "frontend"),
        ("backend", "production"),
        ("frontend", "validation"),
        ("endpoint", "cache"),
        ("prompt", "feature flag"),
        ("build", "production"),
        ("dataset", "backend"),
    ]
    openers = [
        "dans la note de cadrage",
        "sur le ticket produit",
        "dans le mail d'équipe",
        "pour la revue de demain",
        "dans la synthèse du sprint",
        "sur la page de debug",
        "dans le brief du matin",
        "sur la slide de démo",
        "dans le ticket d'onboarding",
        "dans la doc de reprise",
        "sur le fil de discussion",
        "dans la note de production",
        "pour le point avec le client",
        "dans le rappel Slack",
        "sur la fiche QA",
        "dans le compte rendu",
        "pour la procédure d'incident",
        "dans la note d'architecture",
        "sur le tableau de backlog",
        "dans le brief de livraison",
        "dans la relance du support",
        "sur la checklist ops",
        "dans la doc de validation",
        "sur la fiche d'astreinte",
        "dans la synthèse finale",
    ]
    contexts = [
        "quand on garde les deux termes en anglais",
        "dans la phrase qui résume le sujet",
        "dans le passage qu'on simplifie",
        "dans la consigne qu'on reformule",
        "dans le rappel envoyé à l'équipe",
        "dans la note qu'on relit",
        "dans le résumé publié",
        "dans la relance du ticket",
        "dans la checklist qu'on partage",
        "dans la procédure qu'on abrège",
        "dans la note jointe au diff",
        "dans le message de suivi",
        "dans la slide lue à voix haute",
        "dans la page interne",
        "dans la synthèse client",
        "dans la note d'équipe",
        "dans la relance du soir",
        "dans la doc d'escalade",
        "dans la phrase du runbook",
        "dans la note du changelog",
        "dans la checklist finale",
        "dans le support de démo",
        "dans le mail au backend",
        "dans la fiche de reprise",
        "dans la procédure publiée",
    ]
    stakes = [
        "même si je nettoie la syntaxe",
        "quand j'ajoute une virgule",
        "si je retire une hésitation",
        "dans la copie finale",
        "quand je coupe une précision",
        "dans le résumé du ticket",
        "sur la note de sprint",
        "dans la page d'incident",
        "dans la relance interne",
        "dans la version courte",
        "dans le texte du changelog",
        "sur la capture annotée",
        "dans le guide partagé",
        "dans le compte rendu final",
        "quand je simplifie le contexte",
        "dans la réponse au reviewer",
        "dans la note envoyée au client interne",
        "sur la fiche de validation",
        "dans le brief du soir",
        "dans la synthèse d'équipe",
        "dans la note d'onboarding",
        "quand je retire un doublon oral",
        "sur la procédure d'astreinte",
        "dans la version relue",
        "dans la note consolidée",
    ]
    boundaries = [
        "et pas une traduction partielle",
        "sans franciser les termes",
        "même si le reste devient plus fluide",
        "dans la phrase qu'on partage",
        "sur la capture jointe",
        "dans la doc d'incident",
        "dans le mail interne",
        "sur la checklist de production",
        "dans le résumé du sprint",
        "dans le ticket client",
        "dans le message épinglé",
        "dans la note de backlog",
        "dans la slide finale",
        "même quand je reformule autour",
        "dans le journal d'exploitation",
        "dans la procédure finale",
        "dans la consigne lue en réunion",
        "dans le patch qu'on décrit",
        "sur la fiche d'architecture",
        "dans le guide d'équipe",
        "dans la relance support",
        "dans la note de crise",
        "sur le point de production",
        "dans la version envoyée",
        "dans la synthèse qu'on cite",
    ]
    rows: list[dict[str, str]] = []
    for i in range(25):
        left, right = token_pairs[i]
        token = f"{left} et {right}"
        note = f"Préserver les termes mixtes {left} et {right} tels quels."
        opener = openers[i]
        context = f"{contexts[i]} pour {left} et {right}"
        stake = f"{stakes[i]} quand je parle de {left} et {right}"
        boundary = f"{boundaries[i]} autour de {left} et {right}"
        rows.extend(build_triplet(token, sub, opener, context, stake, boundary, note))
    return rows


def main() -> None:
    builders = [
        build_config_env_vars,
        build_package_names,
        build_terminal_commands,
        build_framework_names,
        build_product_names,
        build_version_numbers,
        build_filenames_and_paths,
        build_mixed_fr_en_terms,
    ]
    rows: list[dict[str, str]] = []
    for builder in builders:
        rows.extend(builder())

    assert len(rows) == 600

    required_tokens = [
        "JWT_SECRET",
        "NEXT_PUBLIC_API_URL",
        "schema.prisma",
        "package.json",
        "tsconfig.json",
        "vite.config.ts",
        "docker-compose.yml",
        "docker-compose.prod.yml",
        "next.config.js",
        "PrismaClient",
        "React Query",
        "TanStack Query",
        "useQuery",
        "useMutation",
        "GitHub Actions",
        "Playwright",
        "Vitest",
        "OAuth 2.0",
        "Docker",
        "Redis",
        "rollback",
        "deploy",
        "hotfix",
        "feature flag",
        "backend",
        "frontend",
        "endpoint",
        "prompt",
        "dataset",
        "build",
        "cache",
        "validation",
        "production",
    ]

    seen_ids = set()
    seen_pairs = set()
    coverage = Counter()
    for idx, item in enumerate(rows, start=1):
        item["id"] = f"zphyr-round5-protected-terms-verbatim-{idx:04d}"
        assert item["language"] == "fr"
        assert item["category"] == "round5_patch"
        assert item["raw"] and item["expected"] and item["notes"]
        assert "<think>" not in item["raw"] and "</think>" not in item["raw"]
        assert "<think>" not in item["expected"] and "</think>" not in item["expected"]
        assert item["id"] not in seen_ids
        seen_ids.add(item["id"])
        pair = (item["subcategory"], item["raw"], item["expected"])
        assert pair not in seen_pairs
        seen_pairs.add(pair)
        for token in required_tokens:
            if token in item["raw"] and token in item["expected"]:
                coverage[token] += 1

    for token in required_tokens:
        assert coverage[token] > 0, token

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as handle:
        for item in rows:
            handle.write(json.dumps(item, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
