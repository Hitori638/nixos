#!/usr/bin/env python3
"""lyrics.py KEY ARTIST TITLE [DURATION_S]
Synced lyrics from LRCLIB (lrclib.net, free, no key) for the bar.
Prints one JSON line: {"key": KEY, "ok": true, "lines": [[sec, "text"], ...]}
                  or {"key": KEY, "ok": false, "why": "..."}
Results (hits and misses) are cached in ~/.cache/quickshell/lyrics/.
"""
import hashlib, json, os, re, sys, time, urllib.parse, urllib.request

key = sys.argv[1] if len(sys.argv) > 1 else ""
artist = sys.argv[2] if len(sys.argv) > 2 else ""
title = sys.argv[3] if len(sys.argv) > 3 else ""
try:
    duration = float(sys.argv[4]) if len(sys.argv) > 4 else 0
except ValueError:
    duration = 0

CACHE = os.path.expanduser("~/.cache/quickshell/lyrics")
UA = "quickshell-bar-lyrics/1.0 (personal use)"


def out(obj):
    obj["key"] = key
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(0)


def clean_title(t):
    t = re.sub(r"\s*[\(\[\{][^\)\]\}]*[\)\]\}]", "", t)          # (Official Video) [Lyrics] ...
    t = re.sub(r"(?i)\s*[|•].*$", "", t)                              # "song | channel stuff"
    t = re.sub(r"(?i)\b(official\s+(music\s+)?video|official\s+audio|lyric(s)?\s+video|lyrics?|audio|hd|4k|mv|visualizer)\b", "", t)
    t = re.sub(r"(?i)\s+(ft\.?|feat\.?|featuring)\s+.*$", "", t)
    return re.sub(r"\s{2,}", " ", t).strip(" -–—_")


def clean_artist(a):
    a = re.sub(r"(?i)\s*-\s*topic$", "", a)
    a = re.sub(r"(?i)vevo$", "", a)
    a = re.sub(r"(?i)\s*(official|music)$", "", a)
    a = re.split(r"(?i)\s*(,|&| x | feat\.?| ft\.?)\s*", a)[0]
    return a.strip()


t = clean_title(title)
a = clean_artist(artist)
# YouTube-style "Artist - Song" titles: the channel name is often not the artist
if re.search(r"\s[-–—]\s", t):
    left, right = re.split(r"\s[-–—]\s", t, maxsplit=1)
    if left and right:
        a, t = clean_artist(left), clean_title(right)
if not t:
    out({"ok": False, "why": "no title"})

os.makedirs(CACHE, exist_ok=True)
cf = os.path.join(CACHE, hashlib.sha1(f"{a.lower()}|{t.lower()}".encode()).hexdigest() + ".json")
try:
    with open(cf, encoding="utf-8") as f:
        c = json.load(f)
    if c.get("ok") or time.time() - c.get("at", 0) < 86400:   # misses retried after a day
        out(c)
except Exception:
    pass


def api(path, params):
    url = "https://lrclib.net/api/" + path + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def parse(lrc):
    lines = []
    for raw in lrc.splitlines():
        tags = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", raw)
        text = re.sub(r"\[[^\]]*\]", "", raw).strip()
        for m, s in tags:
            lines.append([round(int(m) * 60 + float(s), 2), text])
    lines.sort(key=lambda x: x[0])
    return lines


def pick(items):
    best = None
    for it in items or []:
        if not it or not it.get("syncedLyrics"):
            continue
        d = abs((it.get("duration") or 0) - duration) if duration else 0
        if best is None or d < best[0]:
            best = (d, it)
    if best and (not duration or best[0] <= 8):
        return best[1]
    return None


try:
    hit = None
    if a:
        p = {"track_name": t, "artist_name": a}
        if duration:
            p["duration"] = int(round(duration))
        g = api("get", p)
        if g and g.get("syncedLyrics"):
            hit = g
        if not hit:
            hit = pick(api("search", {"track_name": t, "artist_name": a}))
    if not hit:
        hit = pick(api("search", {"q": (a + " " + t).strip()}))
    if not hit:
        res = {"ok": False, "why": "no synced lyrics", "at": time.time()}
    else:
        res = {"ok": True, "lines": parse(hit["syncedLyrics"]), "at": time.time(),
               "track": hit.get("trackName", ""), "artist": hit.get("artistName", "")}
    with open(cf, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False)
    out(res)
except Exception as e:
    out({"ok": False, "why": "network: " + str(e)[:60]})
