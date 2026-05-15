# LLM prompts

Bundled prompt templates used by `EuroLLMTranslator` and `ChatService`,
loaded at runtime via `PromptLoader.load(_:vars:)`. Variables are
substituted at load time as `{{key}}` → value.

## Layout

```
Prompts/
├── default/      ← baseline prompts. PromptLoader falls back here
│   ├── chat-system.md
│   ├── chat-actions.md
│   ├── classify-pos.md
│   ├── define-with-examples.md
│   ├── translate-en-to-pt.md
│   ├── translate-pt-to-en.md
│   ├── translate-plain-en-to-pt.md
│   ├── translate-plain-pt-to-en.md
│   └── verb-infinitive.md
├── 1.7B/         ← per-model overrides (create files as needed)
├── 9B/
└── 22B/
```

## How lookup works

Given the currently-loaded `ModelVariant.parameterScale` (e.g. `1.7B`),
`PromptLoader.load(name)` looks first in `<scale>/<name>.md`. If that
file doesn't exist (or the variant directory itself doesn't exist),
it falls back to `default/<name>.md`.

This means **you only need to create override files for the prompts
that need to differ for a given model**. The rest are inherited from
`default/`. Adding a single tweaked prompt for 1.7B is just:

```
$ touch 1.7B/translate-en-to-pt.md
# edit with the 1.7B-friendly variant
```

No three-way sync, no duplicated files.

## Variables

Variables inside a prompt are written as `{{name}}` and substituted
when the prompt is loaded. Each call site passes the variable values
in a `[String: String]` dict.

| Prompt                       | Variables           |
|------------------------------|---------------------|
| `chat-system`                | —                   |
| `chat-actions`               | —                   |
| `classify-pos`               | `labels`, `text`    |
| `define-with-examples`       | `text`              |
| `translate-en-to-pt`         | `text`              |
| `translate-pt-to-en`         | `text`              |
| `translate-plain-en-to-pt`   | `text`              |
| `translate-plain-pt-to-en`   | `text`              |
| `verb-infinitive`            | `text`              |

## Editing tips

- 1.7B models (1–2B params) struggle with: nested JSON, multi-step
  instructions, holding more than 2–3 constraints at once, generating
  related-example arrays. Prefer the plain-text retry prompts over
  JSON when tailoring for 1.7B.
- 9B and 22B handle the strict JSON envelopes reliably. The default
  prompts were tuned against 9B.
- Keep `{{var}}` placeholders intact — they're how runtime values
  flow into the prompt. Removing a placeholder doesn't remove the
  variable at the call site; the value just won't appear in the
  prompt.
