# SearchWork

Script PowerShell per supportare una ricerca assistita di aziende partendo da profili LinkedIn con skill simili al proprio stack tecnico.

## Obiettivo

Lo script genera query mirate, apre le ricerche nel browser e guida l'inserimento manuale dei profili utili e delle rispettive aziende. Non effettua scraping di LinkedIn, non automatizza login e non richiede Microsoft Office.

## File principali

- `Search-LinkedInCompanies.ps1`: script principale.
- `Data/profile-skills.json`: profilo tecnico e query base.
- `Output/`: cartella degli output locali, esclusa dal repository per evitare pubblicazione di dati personali o sensibili.

## Uso

Elencare le query generate:

```powershell
.\Search-LinkedInCompanies.ps1 -NoBrowser -ListQueries
```

Avviare il flusso interattivo:

```powershell
.\Search-LinkedInCompanies.ps1
```

Aggiungere un risultato da riga di comando:

```powershell
.\Search-LinkedInCompanies.ps1 -NoBrowser `
  -PersonName "Nome Cognome" `
  -ProfileUrl "https://www.linkedin.com/in/..." `
  -CompanyName "Nome Azienda" `
  -Website "https://azienda.it" `
  -MatchedSkills "C#; ASP.NET Core; Angular" `
  -SearchQuery 'site:linkedin.com/in "ASP.NET Core" "Angular" "Italia"' `
  -Notes "Nota"
```

## Output locale

Lo script crea localmente:

- `Output/LinkedInCompanyTargets.xlsx`
- `Output/state.json`
- `Output/search-queries.csv`

Questi file non vengono pubblicati su GitHub, perche' possono contenere dati personali o informazioni sulla ricerca lavoro.

## Requisiti

- Windows PowerShell o PowerShell 7+
- Browser predefinito per aprire le query
- LibreOffice o altro programma compatibile con `.xlsx` per analizzare il file generato

