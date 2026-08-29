# ROMs Downloader
A tool to download files from an index page.

Coincidentally, it can be used for downloading ROM collections in cases where you **legally** own those ROMs.

I plan to add more utilities that I often need for my voluntary work at my church and dog shelter, like described below in the [Features/Future](#featuresfuture) section.

## Data

No catalog ships with the app. A **fictional** example is provided at
[`docs/consoles.example.json`](docs/consoles.example.json) to document the schema — it points at
`example.com` placeholders only. Bring your own index URLs; the maintainers do not own nor recommend any source.

Provide a catalog in either of these ways:

- **In the app** — General Settings → *Catalog Source* → import a JSON file or load one from a URL. It's saved to the app's config directory and used on the next load.
- **At build time** (optional) — drop your catalog at `assets/catalog/consoles.json` before building. That path is git-ignored, so it bundles into your build without being committed.

### Auth config

Systems that require authentication can declare an `auth` object:

```json
"auth": {
  "cookies": true,
  "cookie_name": "auth_token",
  "token": "",
  "auth_message": "Instructions shown to the user in settings and on catalog load failures.",
  "signin": {
    "register_url": "https://example.com",
    "url": "https://api.example.com/auth/login",
    "method": "POST",
    "params": ["username", "password"],
    "token_regex": "\"access_token\"\\s*:\\s*\"([^\"]+)\""
  }
}
```

Two ways for the user to provide a token (both available when `signin` is present):

- **Manual token** — the user pastes a token in the system's settings. Sent as `Authorization: Bearer <token>`, or as a `<cookie_name>=<token>` cookie when `cookies` is `true`. A default can be shipped in `token`.
- **Sign in** (`signin` object) — settings render one input per name in `params`, plus a *Create account* link opening `register_url`. Submitting calls `url` with the given `method` and a form-encoded body of the params; the token is extracted from the response body by `token_regex` (capture group 1) and saved as the manual token would be. Credentials are not stored.

For Internet Archive sources use `"type": "ia_s3"` with the IA access/secret keys configured in the general settings instead.

## Downloading builds

I'm currently not relying on releases **JUST BECAUSE**. Meanwhile you can access the latest builds in the [build workflow page](https://github.com/rafaismyname/roms_downloader/actions/workflows/build-and-deploy.yml).
*Note: You must be logged in to GitHub to access the workflow page and download the build.*

## Instructions

- Clone.
- Provide a catalog: import one in-app (General Settings → Catalog Source) or drop it at `assets/catalog/consoles.json` before building. See the [Data](#data) section.
- For NSZ decompression support, package the embedded Python app once before building (repeat after changing `python_app/` or bumping `serious_python`):

  ```sh
  export SERIOUS_PYTHON_APP="$PWD/build/serious_python_app"
  export SERIOUS_PYTHON_SITE_PACKAGES="$PWD/build/site-packages"
  dart run serious_python:main package python_app -p <Darwin|Android|Windows> -r zstandard -r pycryptodome
  # macOS/SwiftPM: export the cache key before EVERY build/run — without it the
  # build drops the Python native frameworks (symbol not found at runtime)
  export SP_NATIVE_SET="$(cat build/.serious_python_spm_key)"
  ```
- Build, run, be happy.
- Treat others as you would like to be treated.

## Features/Future
- [x] Async loading and display of multiple console indexes/catalogs
- [x] Parallel, independent downloads with background support and tasks queue
- [x] Search and filter titles (by country/language, type, extension, etc.)
- [x] Change and customize download destination folder and settings per console
- [x] Unzip and auto-extract downloaded files (background unzip, in-library detection (extracted/similar-named files))
- [x] Allow custom consoles and settings via JSON
- [x] Navigate/search other consoles while downloads/extractions are in progress
- [ ] Collections/Lists
- [x] Permissions control
- [x] Boxart fetching
- [x] Favorites, filter favorites and favorite list export/import
- [x] Filter by in-library
- [ ] Settings for file cache folder
- [x] Grid viewer
- [ ] Game metadata (rating, description, etc.)
- [ ] List sorting
- [x] Info/About page
- [x] Android, Mac, and Windows support
- [ ] Linux and handheld Linux support (untested)
- [ ] ~~iOS support~~ No iOS support for now, *cry about it*.

## Technologies

- Flutter
- Serotonin

## Tests

Not yet! Feel free to add tests.

## Stable?

**Heck no!** I will still bring a lot of breaking changes to this.

## License

MIT

## Author(s)

- [rafaismyname](https://github.com/rafaismyname)
- Your name here? open a PR!
