# Hosted photo recognition for private testing

The iOS app currently uses the Mac as a local development backend. That is
why photo recognition stops when the Mac sleeps or shuts down. The checked-in
`render.yaml` describes a private Render deployment for personal testing:

- Render runs the existing Node backend away from the Mac.
- Render supplies an HTTPS URL.
- Gemini and the Diafit development token are entered as Render secrets.
- No provider key is shipped in the iOS app or committed to Git.

## Deploy

1. Push this repository to GitHub.
2. In Render, choose **New → Blueprint** and select the DiaFit repository.
3. Render reads `render.yaml`. Enter these two secret values when prompted:
   - `DIAFIT_DEVELOPMENT_TOKEN`: a new random private token (at least 8 characters).
   - `GEMINI_API_KEY`: the server-only Gemini key.
4. Wait for the `/health` check to become healthy. Copy the HTTPS service URL,
   for example `https://diafit-analysis.onrender.com`.
5. In the user-only Xcode scheme, set:

   ```text
   DIAFIT_BACKEND_URL=https://diafit-analysis.onrender.com
   DIAFIT_BACKEND_ACCESS_TOKEN=<the same DIAFIT_DEVELOPMENT_TOKEN>
   ```

   Run the app once from Xcode. The DEBUG build stores this app-to-backend
   credential in the device Keychain, so later launches do not need Xcode's
   environment variables.

6. Confirm `GET https://.../health` returns HTTP 200, then upload a photo in
   Diafit. The Mac can now be asleep or shut down.

## Important limitations

This blueprint is for one-person testing, not public release. Render's Free
web service sleeps after inactivity and may take about a minute to wake. The
app intentionally allows that cold-start window for photo recognition, so the
first scan after idle can remain on “Checking the full plate…” for up to about
two minutes before showing a recoverable timeout. Its filesystem is ephemeral,
which is safe here because the backend does not store
meal photos or user diary data. Do not share the development token or expose
this endpoint to other users.

Before public distribution, switch the deployment to production settings:

- `DIAFIT_DEPLOYMENT_ENV=production`
- `DIAFIT_AUTH_MODE=jwks`
- HTTPS JWKS URL, issuer and audience
- managed provider secrets
- an authoritative nutrition provider
- persistent monitoring, rate limiting and privacy/retention controls
