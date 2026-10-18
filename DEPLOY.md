# Deploy EcoGraph to one public link

The API serves the built web app from the same URL, so one container is the whole product: `https://<your-host>/` is the app,
`https://<your-host>/api/health` is the API. All data is synthetic.

## 1. Build the web app (on your Mac)

```bash
cd app
flutter build web --release
rm -rf ../web_app && cp -r build/web ../web_app
```

Commit `web_app/` with the rest of the repo. (Check it first: with the backend running, `python -m eco.server 8000`, open
http://localhost:8000 and the app should load from the API itself.)

## 2. Render (free, no card)

1. Push the repo to GitHub (public).
2. render.com > **New > Blueprint** > choose the repo. It reads `render.yaml`.
3. When asked, paste `ECO_LLM_API_KEY` (a free Gemini key from https://aistudio.google.com/apikey). Use a different provider by
   changing `ECO_LLM_PROVIDER` to `groq`, or set `ANTHROPIC_API_KEY` instead.
4. Apply. The first build takes a few minutes. Then open the URL Render shows you.
5. Check `https://<your-host>/api/health`: it should say `"agent": true` and name the model.

The free plan sleeps after about 15 minutes without traffic, and the first request afterwards takes around a minute. Open the
link before you record or submit, and tell reviewers about the wait.

Any container host works with the `Dockerfile` (Railway, Fly.io, Cloud Run). Set the same environment variables; the app listens on `$PORT`.

## 3. Test the image locally (optional)

```bash
docker build -t ecograph .
docker run --rm -p 8000:8000 -e ECO_LLM_PROVIDER=gemini -e ECO_LLM_API_KEY=your-key ecograph
```

## Notes for a public link

* Do not set `ECO_TOKEN` for a public web demo: the web app would have to carry the token, and anyone could read it from the page.
  The data is synthetic and Ask is rate limited (`ECO_ASK_PER_MIN`, `ECO_ASK_PER_DAY`). Use `ECO_TOKEN` for private deployments.
* Visitors share one ledger. After people have decided cases, use **Reset demo data** in the app (audit log screen, or the console's
  top bar) to rebuild it.
* Keys live in the host's environment settings only. `.env` is git-ignored and `.dockerignore` keeps it out of the image.
