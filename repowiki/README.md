# TFA Agents Wiki - Guida Navigazione

Benvenuto nella Wiki ufficiale di TFA Agents! Questa wiki è disponibile in **Inglese** e **Italiano**.

## 📖 Come Accedere alla Wiki

### Opzione 1: Browser HTML Interattivo
Apri il file `index.html` direttamente nel browser per un'esperienza di navigazione completa:
- **Posizione:** `.vscode/repowiki/index.html`
- **Funzionalità:**
  - Cambio lingua EN/IT con 1 click
  - Sidebar con indice gerarchico
  - Ricerca articoli
  - Rendering markdown con styling

### Opzione 2: Editor Markdown
Leggi i file markdown direttamente dall'editor:

**Inglese:**
```
.vscode/repowiki/en/content/
  ├── Project Overview.md
  ├── Getting Started.md
  ├── Development Guidelines.md
  ├── Build and Deployment.md
  ├── Troubleshooting.md
  └── [Sottocartelle di approfondimento]
```

**Italiano:**
```
.vscode/repowiki/it/content/
  ├── Panoramica Progetto.md
  ├── Guida Introduttiva.md
  ├── Linee Guida Sviluppo.md
  ├── Build e Deployment.md
  ├── Risoluzione Problemi.md
  └── [Sottocartelle di approfondimento]
```

## 🗂️ Struttura Wiki

### Sezioni Principali

#### 📚 Introduzione
- **Project Overview / Panoramica Progetto**: Panoramica architetturale del progetto
- **Getting Started / Guida Introduttiva**: Come iniziare con il progetto

#### 🛠️ Sviluppo
- **Development Guidelines / Linee Guida Sviluppo**: Standard di codifica e best practice
- **Build and Deployment / Build e Deployment**: Come buildare e deployare il gioco
- **Troubleshooting / Risoluzione Problemi**: Risolvere problemi comuni

#### 🏗️ Architettura e Sistemi
- **Architecture Overview / Panoramica Architettura**: Struttura del sistema
- **Core Systems / Sistemi Core**: Componenti principali
- **API Reference / Riferimento API**: Documentazione API

#### 🎮 Gameplay
- **Game Maps and Levels / Mappe Gioco e Livelli**: Design e layout delle mappe
- **Addons and Development Tools / Componenti Aggiuntivi**: Tool di sviluppo

#### 🎨 Grafica e Effetti
- **Visual Effects and Graphics / Effetti Visivi e Grafica**: Shader e effetti visivi

## 🌍 Selezione Lingua

Puoi cambiare lingua in qualsiasi momento:
1. Apri `index.html` nel browser
2. Clicca su **EN** o **IT** in alto a destra
3. La wiki si aggiorna istantaneamente

## 🔍 Ricerca

Usa il campo di ricerca in alto per trovare articoli:
1. Digita il termine di ricerca
2. Premi Enter o clicca "Cerca"
3. Verrai reindirizzato all'articolo corrispondente

## 📝 Modifica Wiki

Per aggiungere o modificare contenuti:

### Aggiungere un nuovo articolo
1. Crea un file `.md` nella cartella appropriata:
   - EN: `.vscode/repowiki/en/content/[categoria]/Titolo.md`
   - IT: `.vscode/repowiki/it/content/[categoria]/Titolo.md`
2. Usa il formato Markdown
3. L'articolo apparirà automaticamente nel browser

### Aggiornare la struttura di navigazione
Modifica l'oggetto `WIKI_STRUCTURE` in `index.html`:
```javascript
WIKI_STRUCTURE: {
    en: {
        'page-id': { title: 'Page Title', category: 'Category' }
    },
    it: {
        'page-id': { title: 'Titolo Pagina', category: 'Categoria' }
    }
}
```

## 💡 Consigli di Utilizzo

- **Per sviluppatori:** Consulta le "Development Guidelines" prima di contribuire
- **Per principianti:** Inizia con "Getting Started"
- **Per debug:** Consulta "Troubleshooting" quando hai problemi
- **Per richieste di build:** Vedi "Build and Deployment"

## 🤝 Contribuire alla Wiki

La wiki è un documento vivo. Se noti errori o mancanze:
1. Modifica il file markdown direttamente
2. Aggiungi nuovo contenuto seguendo il formato esistente
3. Aggiorna sia la versione EN che IT per coerenza

## 📊 Struttura File Locale

```
.vscode/repowiki/
├── index.html                  # Browser interattivo
├── README.md                   # Questo file
├── en/                         # Contenuto Inglese
│   ├── content/
│   ├── meta/
│   └── knowledge/
├── it/                         # Contenuto Italiano
│   ├── content/
│   ├── meta/
│   └── knowledge/
└── knowledge/                  # Indici condivisi
```

## ✨ Funzionalità Future

Potenziali miglioramenti:
- [ ] Caricamento dinamico dei file markdown via AJAX
- [ ] Indice di ricerca full-text
- [ ] Dark mode
- [ ] Esportazione PDF
- [ ] Versioning della documentazione
- [ ] Integrazione con GitHub Pages

---

**Ultima aggiornamento:** 21 Giugno 2026
**Lingua primaria:** Italiano e Inglese
