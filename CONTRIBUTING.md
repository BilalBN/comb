# How work gets into Comb

**The rule:** nothing reaches `main` until it has passed CI and been tested
on a real device. `main` is always something you could install and use.

## The flow for every change

1. **Start from an up-to-date `main`.**
   ```bash
   git switch main
   git pull
   ```
2. **Make a branch for the change.** One branch per feature or fix, named
   after the milestone and topic: `m1/matrix-view`, `m2/whatsapp-share`,
   `fix/pairing-expiry`.
   ```bash
   git switch -c m1/matrix-view
   ```
3. **Do the work, commit, push the branch** (never `main`).
   ```bash
   git add -A
   git commit -m "Matrix view: four boxes by priority and urgency"
   git push -u origin m1/matrix-view
   ```
4. **Open a pull request** on GitHub from the branch into `main`. Fill in
   the checklist in the template.
5. **Wait for CI to go green.** If it fails, fix it on the same branch and
   push again; the pull request updates by itself.
6. **Test it yourself** on the devices listed in the pull request (for now:
   the Android phone and the Mac). Tick the boxes.
7. **Merge** with "Squash and merge", then delete the branch.
8. **Back to `main`** for the next change:
   ```bash
   git switch main
   git pull
   ```

## Protecting `main` on GitHub

Settings → Branches (or Rules → Rulesets) → add a rule for `main`:

- Require a pull request before merging
- Require status checks to pass: **Server tests**, **App tests**, **Mac app
  builds**
- Block force pushes

GitHub enforces these rules for free on **public** repositories. On a
private repository they need a paid plan, so until then follow the flow by
habit.

## Changing the API

The app's API client follows `docs/openapi.json`, and the app tests sync
through the real server, so a mismatch fails CI. After any server change
that touches an endpoint or model:

```bash
cd server
python -m comb_server openapi ../docs/openapi.json
```

CI fails if the file is out of date.

## Things that never go in the repository

- Anything from `comb-data/` (the server's data folder)
- Setup codes, device tokens, recovery keys
- Your notes or vault folder

## Changing the encryption format

`docs/test-vectors.json` holds fixed inputs and the exact bytes the
protocol produces, made by the Python reference client. If you change the
protocol, run `python tools/refclient/make_vectors.py`, commit the result,
and make the app tests pass against it.
