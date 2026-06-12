# Guida: Release GitHub con Changelog e Aggiornamento Automatici

Questo progetto usa `GlobalSettings` per controllare `api.github.com/repos/Ekt0re/tfa-agents/releases`
e scaricare aggiornamenti direttamente in-game. Perché tutto funzioni correttamente,
ogni rilascio deve seguire queste convenzioni.

---

## Come funziona l'aggiornamento automatico

```
project.godot  →  config/version = "0.1.2"
                           ↓
GlobalSettings  →  chiama api.github.com/.../releases
                           ↓
              confronta tag della release con version corrente
                           ↓
              mostra popup changelog + pulsante Download
```

Il codice legge il tag di ogni release GitHub e lo confronta con `config/version`
in `project.godot`. Se il tag è più recente → mostra il popup di aggiornamento.

---

## Procedura passo-passo per ogni release

### 1. Aggiorna la versione in `project.godot`

Apri `project.godot` (o il pannello *Project → Project Settings → Config → Version*)
e cambia il numero di versione seguendo il formato `MAJOR.MINOR.PATCH`:

```ini
config/version="0.1.2"   ; era 0.1.1-dev → rimuovi -dev per le release stabili
```

> [!IMPORTANT]
> Il tag GitHub **deve corrispondere esattamente** alla versione (con o senza `v` iniziale).
> Il codice accetta entrambe le forme: `0.1.2` e `v0.1.2`.

---

### 2. Aggiorna `CHANGELOG.md`

Il popup in-game mostra il corpo della release GitHub **oppure**, come fallback,
la sezione corrispondente di `CHANGELOG.md`. Usa il formato:

```markdown
## 0.1.2

- Corretti bug di tipo inferenza in global_settings.gd.
- Migliorata stabilità del menu principale.
- Aggiunto supporto lingua inglese.

## 0.1.1

- Prima release pubblica.
- ...
```

> [!NOTE]
> Ogni sezione `##` deve avere **esattamente** il numero di versione come titolo
> (senza `v`). Il codice fa `_extract_changelog_section(raw_text, version)` cercando
> `## 0.1.2` oppure `## v0.1.2`.

---

### 3. Esporta i file di gioco

Esegui l'export da Godot per le piattaforme supportate:

| Piattaforma | File da allegare        | Convezione nome consigliata              |
|-------------|-------------------------|------------------------------------------|
| Windows     | `.zip` con l'eseguibile | `tfa-agents-0.1.2-windows-x86_64.zip`   |
| Android     | `.apk`                  | `tfa-agents-0.1.2-android-arm64.apk`    |

Il codice in `_score_release_asset()` seleziona automaticamente il file migliore
in base alla piattaforma, favorendo:
- **Windows**: `.zip` > `.exe`, con bonus per `windows`/`win` e `x86_64`/`64` nel nome.
- **Android**: `.apk`, con bonus per `android` e `arm64` nel nome.

---

### 4. Fai commit e push

```powershell
git add project.godot CHANGELOG.md
git commit -m "chore: bump version to 0.1.2"
git push origin main
```

---

### 5. Crea la Release su GitHub

Vai su **github.com/Ekt0re/tfa-agents → Releases → Draft a new release**.

| Campo            | Valore                                                      |
|------------------|-------------------------------------------------------------|
| **Tag**          | `0.1.2`  (oppure `v0.1.2`, entrambi funzionano)            |
| **Target**       | `main`                                                      |
| **Release title**| `Release 0.1.2`                                            |
| **Description**  | Incolla il contenuto della sezione `## 0.1.2` dal CHANGELOG |
| **Assets**       | Allega `.zip` Windows e/o `.apk` Android                   |
| **Draft**        | ❌ Non spuntare Draft → il codice salta le draft release    |

Clicca **Publish release**.

---

## Verifica che tutto funzioni

In-game, apri il menu principale: il sistema chiama automaticamente
`request_release_check()` e confronta la versione. Se il tag della release
è più alto di `config/version`, appare il popup di aggiornamento.

Per testare senza pubblicare una vera release:
1. Imposta temporaneamente `config/version="0.0.0"` in `project.godot`.
2. Avvia il gioco → il sistema rileva la release esistente come più recente.
3. Ripristina la versione corretta.

---

## Riepilogo checklist per ogni release

- `[ ]` Versione aggiornata in `project.godot` (es. `0.1.2`, senza `-dev`)
- `[ ]` Sezione `## 0.1.2` aggiunta in cima a `CHANGELOG.md`
- `[ ]` Export Windows (`.zip`) e/o Android (`.apk`) eseguito
- `[ ]` Commit + push su `main`
- `[ ]` Release GitHub creata con tag `0.1.2` (non draft)
- `[ ]` Asset allegati con nome contenente piattaforma e architettura
