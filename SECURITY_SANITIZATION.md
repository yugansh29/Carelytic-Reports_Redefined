# Secret Sanitization Checklist

## Immediate actions
1. Rotate all exposed credentials in your provider consoles (AWS and OpenAI).
2. Delete secret-bearing local files:
   - .env
   - backend/.env
   - Reportify_accessKeys.csv
3. Recreate local env files from .env.example and backend/.env.example.

## Git history sanitization
Use git-filter-repo to remove secrets from all history.

### Remove files from history
```bash
git filter-repo --path Reportify_accessKeys.csv --path .env --path backend/.env --invert-paths --force
```

### Replace leaked key strings if they appeared in other files
Create a replacements file named replacements.txt:
```text
literal:<EXPOSED_AWS_ACCESS_KEY>==>REDACTED_AWS_ACCESS_KEY
literal:<EXPOSED_AWS_SECRET_KEY>==>REDACTED_AWS_SECRET_KEY
```
Then run:
```bash
git filter-repo --replace-text replacements.txt --force
```

### Push rewritten history
```bash
git push --force --all
git push --force --tags
```

## Verification
1. Search for key remnants before pushing:
```bash
rg -n "AKIA|AWS_SECRET_ACCESS_KEY|OPENAI_API_KEY|BEGIN RSA PRIVATE KEY|ghp_" .
```
2. Confirm .gitignore blocks sensitive files.
3. Confirm new keys work and old keys are disabled.

## Team note
If this repository is shared, everyone must re-clone after history rewrite.
