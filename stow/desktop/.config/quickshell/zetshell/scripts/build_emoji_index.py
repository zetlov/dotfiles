#!/usr/bin/env python3

import json
import re
import unicodedata
from pathlib import Path


EMOJI_DATA_PATH = Path("/usr/share/texmf-dist/tex/generic/unicode-data/emoji-data.txt")
VARIATION_SELECTOR_16 = "\ufe0f"


def load_emoji_presentation_set(lines):
    values = set()
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#") or "; Emoji_Presentation" not in line:
            continue

        code_spec = line.split(";", 1)[0].strip()
        if ".." in code_spec:
            start, end = [int(part, 16) for part in code_spec.split("..", 1)]
            values.update(range(start, end + 1))
            continue

        values.add(int(code_spec, 16))
    return values


def keyword_tokens(name):
    return sorted(set(re.findall(r"[a-z0-9]+", name.lower())))


def main():
    lines = EMOJI_DATA_PATH.read_text(encoding="utf-8").splitlines()
    emoji_presentation = load_emoji_presentation_set(lines)
    items = []
    seen = set()

    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#") or "; Extended_Pictographic" not in line:
            continue

        code_spec = line.split(";", 1)[0].strip()
        if ".." in code_spec:
            start, end = [int(part, 16) for part in code_spec.split("..", 1)]
            codepoints = range(start, end + 1)
        else:
            codepoints = [int(code_spec, 16)]

        for codepoint in codepoints:
            if codepoint in seen:
                continue

            seen.add(codepoint)
            char = chr(codepoint)
            try:
                name = unicodedata.name(char)
            except ValueError:
                continue

            display = char if codepoint in emoji_presentation else char + VARIATION_SELECTOR_16
            items.append({
                "emoji": display,
                "name": name.title(),
                "keywords": keyword_tokens(name),
            })

    print(json.dumps(items, ensure_ascii=False))


if __name__ == "__main__":
    main()
