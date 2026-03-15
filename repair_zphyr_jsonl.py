#!/usr/bin/env python3
import json
import re
import shutil
from pathlib import Path

ROOT = Path(".")
DATA_DIR = ROOT / "Evals" / "datasets" / "raw" / "v2"
BACKUP_DIR = DATA_DIR / "_backup_before_autofix"
QUARANTINE_DIR = DATA_DIR / "_quarantine"

FRENCH_WORDS = {
    "je","tu","il","elle","on","nous","vous","ils","elles","le","la","les","un","une",
    "des","de","du","et","est","suis","es","sommes","êtes","sont","pour","avec","dans",
    "sur","au","aux","ce","cette","ces","mon","ton","son","ma","ta","sa","mes","tes","ses",
    "bonjour","merci","demain","aujourd","hui","réunion","projet","fichier","commande",
    "application","mettre","supprimer","aller","ligne","paragraphe","gras","italique"
}
ENGLISH_WORDS = {
    "the","a","an","and","is","are","am","to","for","with","in","on","my","your","this","that",
    "these","those","hello","thanks","tomorrow","today","meeting","project","file","command",
    "application","set","delete","move","line","paragraph","bold","italic","quote","next",
    "previous","open","close","insert","mode"
}

ID_ABBR = {
    ("technical", "code_identifiers"): "ci",
    ("technical", "terminal_commands"): "tc",
    ("technical", "urls_paths"): "up",
    ("technical", "package_names"): "pkg",
    ("technical", "config_env_vars"): "cfg",
    ("technical", "version_numbers"): "ver",
    ("technical", "data_values"): "dat",

    ("multilingual", "fr_primary_en_terms"): "fren",
    ("multilingual", "en_primary_fr_terms"): "enfr",
    ("multilingual", "code_switching"): "csw",
    ("multilingual", "quoted_foreign"): "qf",
    ("multilingual", "other_pairs"): "oth",

    ("commands", "trigger_mode"): "trg",
    ("commands", "spoken_punctuation"): "sp",
    ("commands", "formatting_commands"): "fmt",
    ("commands", "navigation_commands"): "nav",
    ("commands", "ambiguous_command_content"): "amb",

    ("corrections", "filler_removal"): "fil",
    ("corrections", "word_repetition"): "rep",
    ("corrections", "spoken_restart"): "res",
    ("corrections", "filler_and_repetition"): "far",
    ("corrections", "intentional_repetition"): "irep",

    ("short", "short_sentence"): "ss",
    ("short", "single_word_phrase"): "swp",
    ("short", "title"): "ttl",
    ("short", "filename_tag"): "tag",
    ("short", "near_empty"): "ne",

    ("prose", "narrative"): "nar",
    ("prose", "expository"): "exp",
    ("prose", "email_message"): "mail",
    ("prose", "mixed_register"): "mix",

    ("lists", "unordered_items"): "uli",
    ("lists", "ordered_steps"): "ost",
    ("lists", "mixed_list_content"): "mlc",
    ("lists", "shopping_todo"): "std",
}

def read_jsonl(path: Path):
    rows = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows

def write_jsonl(path: Path, rows):
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

def tokenize(text: str):
    return re.findall(r"[A-Za-zÀ-ÿ0-9_@./:+#~-]+", text.lower())

def mostly_french(text: str):
    toks = tokenize(text)
    fr = sum(t in FRENCH_WORDS for t in toks)
    en = sum(t in ENGLISH_WORDS for t in toks)
    return fr > en

def mostly_english(text: str):
    toks = tokenize(text)
    fr = sum(t in FRENCH_WORDS for t in toks)
    en = sum(t in ENGLISH_WORDS for t in toks)
    return en > fr

def looks_like_url_or_path(text: str):
    patterns = [
        r"https?://", r"\bs3://", r"\b[a-z]+://", r"(^| )~/", r"(^| )\./", r"(^| )\.\./",
        r"/[A-Za-z0-9._/\-]+", r"[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:/", r"\b[A-Za-z]:\\"
    ]
    return any(re.search(p, text) for p in patterns)

def looks_like_env(text: str):
    if "process.env" in text:
        return True
    return bool(re.search(r"\b[A-Z][A-Z0-9_]{2,}\b", text))

def looks_like_package(text: str):
    package_markers = [
        "npm ", "yarn ", "pnpm ", "pip ", "poetry ", "composer ", "cargo ",
        "gem ", "bundle ", "go mod ", "@types/", "create-next-app", "prisma ",
        "flutter pub ", "laravel/", "github.com/"
    ]
    return any(m in text for m in package_markers) or bool(re.search(r"@[A-Za-z0-9._/\-]+", text))

def looks_like_version(text: str):
    return bool(re.search(r"\bv?\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9._-]+)?\b", text))

def looks_like_command(text: str):
    starters = [
        "git ","npm ","npx ","yarn ","pnpm ","pip ","python ","pytest ","curl ","docker ","docker compose ",
        "kubectl ","terraform ","aws ","rsync ","ffmpeg ","ssh-keygen ","grep ","go ","cargo ","make ",
        "chmod ","ln ","cat ","sed ","php ","rails ","dotnet ","flutter ","xcodebuild ","swift ",
        "gradle ","mvn ","composer ","deno ","bun ","vite ","wrangler ","serverless ","sam ","cdk ",
        "pulumi ","ansible-playbook ","vagrant ","packer ","helm ","istioctl ","podman ","buildah ",
        "crictl ","react-native ","nx ","turbo ","lerna ","rush ","bazel ","buck2 ","pants ",
        "wasm-pack ","trunk ","hardhat ","forge ","solc ","anchor ","sbt ","mill "
    ]
    if any(text.startswith(s) for s in starters):
        return True
    return bool(re.match(r"^[a-z0-9._-]+(?: [^\n]+)+$", text))

def looks_like_code(text: str):
    markers = [
        "import ", "const ", "let ", "var ", "function ", "class ", "export ", "return ",
        "SELECT ", "INSERT ", "UPDATE ", "DELETE ", " FROM ", " WHERE ", "{", "}", "=>"
    ]
    return any(m in text for m in markers)

def infer_technical_subcategory(text: str):
    if looks_like_env(text):
        return "config_env_vars"
    if looks_like_package(text):
        return "package_names"
    if looks_like_url_or_path(text):
        return "urls_paths"
    if looks_like_version(text):
        return "version_numbers"
    if looks_like_command(text):
        return "terminal_commands"
    if looks_like_code(text):
        return "code_identifiers"
    return "data_values"

def infer_multilingual_subcategory(text: str):
    lowered = text.lower()
    if any(q in lowered for q in ['"', "«", "»", "“", "”", "'"]):
        if mostly_french(text) or mostly_english(text):
            return "quoted_foreign"
    if mostly_french(text):
        return "fr_primary_en_terms"
    if mostly_english(text):
        return "en_primary_fr_terms"
    return "code_switching"

def infer_command_subcategory(text: str):
    t = text.lower()
    punctuation_terms = [
        "comma", "period", "full stop", "semicolon", "colon", "question mark", "exclamation mark",
        "open quote", "close quote", "open parenthesis", "close parenthesis", "newline", "new line",
        "virgule", "point", "point final", "point-virgule", "deux-points", "point d'interrogation",
        "point d’exclamation", "guillemets", "ouvrir les parenthèses", "fermer les parenthèses",
        "nouvelle ligne", "retour à la ligne"
    ]
    formatting_terms = [
        "bold", "italic", "underline", "capitalize", "title case", "uppercase", "lowercase",
        "mettre en gras", "italique", "souligner", "majuscule", "minuscule", "titre"
    ]
    navigation_terms = [
        "go to", "move to", "cursor", "next line", "previous line", "next paragraph", "previous paragraph",
        "select", "highlight", "left", "right", "up", "down", "delete line", "insert before", "insert after",
        "aller à", "curseur", "ligne suivante", "ligne précédente", "paragraphe suivant", "paragraphe précédent",
        "sélectionner", "mettre en surbrillance", "gauche", "droite", "haut", "bas", "supprimer la ligne"
    ]
    trigger_terms = [
        "command mode", "dictation mode", "literal mode", "trigger word",
        "mode commande", "mode dictée", "mode littéral", "mot déclencheur"
    ]
    if any(x in t for x in trigger_terms):
        return "trigger_mode"
    if any(x in t for x in punctuation_terms):
        return "spoken_punctuation"
    if any(x in t for x in formatting_terms):
        return "formatting_commands"
    if any(x in t for x in navigation_terms):
        return "navigation_commands"
    return "ambiguous_command_content"

def fix_ids(rows, category):
    counters = {}
    for row in rows:
        sub = row.get("subcategory", "misc")
        counters.setdefault(sub, 0)
        counters[sub] += 1
        abbr = ID_ABBR.get((category, sub), sub[:3].lower())
        row["id"] = f"zphyr-{category}-{abbr}-{counters[sub]:03d}"

def backup_file(path: Path):
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, BACKUP_DIR / path.name)

def repair_technical(path: Path):
    rows = read_jsonl(path)
    for row in rows:
        if row.get("subcategory") == "term_preservation":
            row["subcategory"] = infer_technical_subcategory(row.get("raw_asr_text", ""))
    fix_ids(rows, "technical")
    write_jsonl(path, rows)

def repair_multilingual(path: Path):
    rows = read_jsonl(path)
    for row in rows:
        if row.get("subcategory") == "fr_en_preserve":
            row["subcategory"] = infer_multilingual_subcategory(row.get("raw_asr_text", ""))
    fix_ids(rows, "multilingual")
    write_jsonl(path, rows)

def repair_commands(path: Path):
    rows = read_jsonl(path)
    for row in rows:
        if row.get("subcategory") == "direct_command":
            row["subcategory"] = infer_command_subcategory(row.get("raw_asr_text", ""))
    fix_ids(rows, "commands")
    write_jsonl(path, rows)

def repair_corrections(path: Path):
    rows = read_jsonl(path)
    kept = []
    quarantined = []
    for row in rows:
        if row.get("difficulty") == "low":
            row["difficulty"] = "easy"
        if row.get("subcategory") == "number_normalization":
            quarantined.append(row)
            continue
        kept.append(row)

    fix_ids(kept, "corrections")
    write_jsonl(path, kept)

    if quarantined:
        QUARANTINE_DIR.mkdir(parents=True, exist_ok=True)
        for i, row in enumerate(quarantined, start=1):
            row["category"] = "technical"
            row["subcategory"] = "data_values"
            row["id"] = f"zphyr-technical-dat-q{i:03d}"
        write_jsonl(QUARANTINE_DIR / "moved_from_corrections_number_normalization.jsonl", quarantined)

def repair_short(path: Path):
    rows = read_jsonl(path)
    for row in rows:
        if row.get("difficulty") == "low":
            row["difficulty"] = "easy"
        sub = row.get("subcategory")
        if sub in {"short_sentence_filler", "short_sentence_question"}:
            row["subcategory"] = "short_sentence"
    fix_ids(rows, "short")
    write_jsonl(path, rows)

def repair_ids_only(path: Path, category: str):
    rows = read_jsonl(path)
    fix_ids(rows, category)
    write_jsonl(path, rows)

def main():
    targets = {
        "technical.jsonl": repair_technical,
        "multilingual.jsonl": repair_multilingual,
        "commands.jsonl": repair_commands,
        "corrections.jsonl": repair_corrections,
        "short.jsonl": repair_short,
        "prose.jsonl": lambda p: repair_ids_only(p, "prose"),
        "lists.jsonl": lambda p: repair_ids_only(p, "lists"),
    }

    missing = []
    for name in targets:
        path = DATA_DIR / name
        if not path.exists():
            missing.append(str(path))
    if missing:
        print("Missing files:")
        for m in missing:
            print(" -", m)
        raise SystemExit(1)

    for name, fn in targets.items():
        path = DATA_DIR / name
        backup_file(path)
        fn(path)
        print(f"Patched {path}")

    print("\nDone.")
    print(f"Backups: {BACKUP_DIR}")
    print(f"Quarantine: {QUARANTINE_DIR} (used only if invalid corrections rows were moved)")

if __name__ == "__main__":
    main()
