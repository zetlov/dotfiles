---
name: obsidian-note
description: Convert a handwritten note image into atomic Zettelkasten Markdown notes in the Obsidian vault. Use when given a handwritten note image and asked to "ノートを作って" or "ノートにして".
metadata:
  short-description: Handwritten note image to Zettelkasten notes
---

Resolve the vault root from `$OBSIDIAN_VAULT`; if it is unset, use `$HOME/Obsidian/main`. You are converting a handwritten note image into atomic Zettelkasten notes in that vault.

## Step 1 — Read the image

The user will have provided an image. Examine it carefully. Extract all content: definitions, theorems, proofs, concepts, examples, diagrams descriptions, problem sets, etc.

## Step 2 — Identify atomic units

Apply Zettelkasten principles:
- One idea per note (atomic)
- Split by concept: each theorem, definition, proof technique, or concept → separate note
- Use the content to infer meaningful Japanese or English titles (match the language used in the notes)

## Step 3 — Choose the right template

Templates are in `$OBSIDIAN_VAULT/99_Extra/Templates/`. Reference them when creating notes:

| Content type | Template |
|---|---|
| Theorem / proposition | `note-theorem.md` → frontmatter: `type: note`, `kind: theorem`; sections: `## Statement`, `## Proof`, `## Notes`, `## Related links`, `## Anki` |
| Definition | `note-definition.md` → frontmatter: `type: note`, `kind: definition`; sections: `## Definition`, `## Note`, `## Related`, `## Anki` |
| General concept / fact | `note.md` → frontmatter: `type: note` |
| MOC | `note-moc.md` → frontmatter: `type: note`, `kind: moc`; sections: `## Related`, `## Activity` |
| Problem / exercise | `note-problem.md` → frontmatter: `type: note`; sections: `## Problem`, `## My Solution`, `## Reference Solution` |

## Step 4 — Search for related existing notes

Before creating notes, search the vault for related content:

```
Glob: $OBSIDIAN_VAULT/10_Note/**/*.md  (for MOCs)
Grep: search by key terms to find existing notes to link
```

Find notes that are:
- On the same topic / concept
- Parent MOCs where these new notes belong
- Prerequisites or follow-on concepts

## Step 5 — Create the notes

Create each atomic note in `$OBSIDIAN_VAULT/00_INBOX/`.

File naming: use the concept name as the filename (Japanese OK, match the handwriting's language).

Example note structure:

```markdown
---
type: note
kind: theorem
---

## Statement

[statement here]

## Proof

[proof here]

## Notes

[intuition, examples, edge cases]

## Related links

[[related note 1]]
[[related note 2]]

## Anki

Q:
A:
```

Rules:
- Use `[[wikilink]]` syntax for ALL internal links — never markdown links
- Include aliases in wikilinks when needed: `[[Note Name|display text]]`
- Transcribe math faithfully using LaTeX: `$inline$` or `$$block$$`
- Keep each note self-contained but linked
- Do not add content not present in the handwriting (no hallucination)

## Step 6 — Link to existing MOCs and notes

After creating notes:
1. Identify which existing MOC(s) these notes belong to
2. Add `[[new note name]]` entries to the appropriate section of those MOCs
3. If no suitable MOC exists and there are 3+ related new notes, create a new MOC in `00_INBOX/` using the `note-moc.md` template

## Step 7 — Report

After all files are created/edited, output a summary:

```
## Created Notes
- [[Note 1]] — (type: theorem/definition/etc.)
- [[Note 2]] — ...

## MOCs Updated
- [[MOC name]] — notes added

## New MOCs Created (if any)
- [[New MOC]]
```
