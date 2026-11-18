#!/usr/bin/env python3
# Estado de las versiones de Alma en App Store Connect (TestFlight). Lee la llave de las variables de entorno
# ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_P8 (secretos de GitHub) y nunca la imprime.
#   python3 .github/estado-testflight.py                 -> tabla de las últimas 20 versiones
#   python3 .github/estado-testflight.py --esperar 123   -> espera a que Apple procese la versión 123 (máx. 40 min);
#                                                           sale con error si queda INVALID o FAILED.
import json, os, sys, time, urllib.request, urllib.parse
import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.spacioam.alma"


def token():
    ahora = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": ahora, "exp": ahora + 1100,
                       "aud": "appstoreconnect-v1"}, os.environ["ASC_KEY_P8"], algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def pedir(ruta, params=None):
    url = API + ruta + ("?" + urllib.parse.urlencode(params, safe="[],") if params else "")
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print(f"::error::App Store Connect respondió {e.code} en {ruta}: {e.read()[:400].decode(errors='replace')}")
        sys.exit(1)


def app_id():
    d = pedir("/apps", {"filter[bundleId]": BUNDLE, "fields[apps]": "name,bundleId"})
    if not d.get("data"):
        print(f"::error::No encontré la app {BUNDLE} en App Store Connect."); sys.exit(1)
    return d["data"][0]["id"]


def builds(app, limite=20, version=None):
    p = {"filter[app]": app, "sort": "-uploadedDate", "limit": str(limite),
         "fields[builds]": "version,uploadedDate,processingState,expired,minOsVersion,buildBetaDetail",
         "include": "buildBetaDetail",
         "fields[buildBetaDetails]": "internalBuildState,externalBuildState"}
    if version:
        p["filter[version]"] = str(version)
    d = pedir("/builds", p)
    beta = {i["id"]: i["attributes"] for i in d.get("included", []) if i["type"] == "buildBetaDetails"}
    filas = []
    for b in d.get("data", []):
        a = b["attributes"]
        rel = (b.get("relationships", {}).get("buildBetaDetail", {}).get("data") or {}).get("id")
        bb = beta.get(rel, {})
        filas.append({"build": a.get("version"), "fecha": (a.get("uploadedDate") or "")[:16].replace("T", " "),
                      "estado": a.get("processingState"), "testflight": bb.get("internalBuildState") or "",
                      "ios_min": a.get("minOsVersion") or "", "vencida": a.get("expired")})
    return filas


def tabla(filas):
    print(f"{'build':>6}  {'subida (UTC)':16}  {'estado':11}  {'TestFlight interno':28}  iOS mín.")
    for f in filas:
        print(f"{f['build']:>6}  {f['fecha']:16}  {f['estado'] or '':11}  {f['testflight']:28}  {f['ios_min']}"
              + ("  (vencida)" if f["vencida"] else ""))


def main():
    for v in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
        if not os.environ.get(v):
            print(f"::error::Falta el secreto {v}."); sys.exit(1)
    app = app_id()
    if len(sys.argv) > 2 and sys.argv[1] == "--esperar":
        n = sys.argv[2]
        fin = time.time() + 40 * 60
        while time.time() < fin:
            f = builds(app, 1, n)
            estado = f[0]["estado"] if f else "AÚN NO APARECE"
            print(f"build {n}: {estado}", flush=True)
            if estado == "VALID":
                return
            if estado in ("INVALID", "FAILED"):
                print(f"::error::Apple marcó la build {n} como {estado}. El motivo (ITMS-…) llega por correo a la cuenta "
                      "de App Store Connect y sale en App Store Connect → TestFlight.")
                sys.exit(1)
            time.sleep(60)
        print(f"::warning::La build {n} sigue sin procesar tras 40 min."); return
    filas = builds(app)
    tabla(filas)
    malas = [f for f in filas if f["estado"] in ("INVALID", "FAILED")]
    if malas:
        print(f"\n{len(malas)} build(s) rechazadas por Apple: " + ", ".join(f["build"] for f in malas))


if __name__ == "__main__":
    main()
