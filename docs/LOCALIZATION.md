# Localization

Grand Exhibit ships in English, Spanish, French, German, Brazilian Portuguese
and Italian. Players pick a language in Settings (Automatic follows the
device); the choice is saved with the game.

## How it works

- Catalogs are gettext files: `locale/<code>.po`, one per language, with the
  template `locale/messages.pot`. The message id is the English text itself,
  so English needs no catalog and anything untranslated falls back to English.
- Godot translates Label and Button text by itself. A screen built with
  `_label("Settings")` or `button.text = "Close"` needs no code change, and
  open screens re-label when the language changes.
- Text built from pieces must translate the English template first:
  `tr("Need $%s more") % amount`, never `"Need $" + amount + " more"`. In a
  static function use `TranslationServer.translate("...")`.
- Data names (museums, decor, artifacts, managers...) come from `data/*.json`
  and are in the catalog too. Labels translate them automatically; code that
  puts one inside a sentence wraps it: `tr("Welcome to %s!") % tr(name)`.
- Room names are written in capitals for the 3D signs.
  `DataLoader.venue_dept_name()` translates them and title-cases them for the
  panels ("Sala de la Naturaleza"). Pass `localized = false` when logic needs
  the English words.
- Plurals get two strings (`"...%d active post."` / `"...%d active posts."`),
  never an `"s"` passed through `%s`.
- `scripts/ui/languages.gd` holds the language list, maps the device locale
  (es_MX → es, pt_PT → pt_BR, anything else → en) and applies the choice.

## Adding or changing text

1. Write the English in code or data as above.
2. Run `python3 tools/i18n_extract.py`. It rebuilds `locale/messages.pot`
   from tr() calls, UI text literals, scenes and the data files, and merges it
   into every `.po`: existing translations stay, new strings arrive with an
   empty `msgstr`, removed ones move to `#~` comments at the bottom.
3. Fill the empty `msgstr` lines in each `.po` (any PO editor, e.g. Poedit,
   works). Keep every placeholder (`%s`, `%d`, `%.2f`, `%%`) in the same
   order, and keep `\n` line breaks.
4. Run `tests/core/test_i18n.gd`. It fails if a listed language is missing a
   string, if placeholders changed, or if the pot is stale.

`python3 tools/i18n_extract.py --check` exits 1 when the pot doesn't match the
code, for CI.

## Adding a language

1. `cp locale/messages.pot locale/<code>.po`, set `"Language: <code>\n"` in
   the header, translate every entry.
2. Add `res://locale/<code>.po` to `internationalization/locale/translations`
   in `project.godot`.
3. Add `["<code>", "<name in that language>"]` to `LANGUAGES` in
   `scripts/ui/languages.gd`. The test then requires the catalog to be
   complete.
4. Fonts: the UI face, Inter (subset in `assets/fonts/`), covers Latin, Latin Extended and Vietnamese. Cyrillic,
   Greek, CJK, Thai or Arabic need a fallback font (e.g. a Noto subset) added
   to `UI.install_default_font()` first. Watch the pack size budget.

## Checking it on screen

`tools/shot.gd` takes `lang=<code>`:

```bash
GRAND_EXHIBIT_TEST_RUN=1 xvfb-run -a -s "-screen 0 800x1400x24" \
  godot --path . -s tools/shot.gd -- out=/tmp/de.png lang=de warm=4 \
  open=res://scenes/meta/settings_screen.tscn
```

German runs about 30% longer than English; check tight buttons there first.
