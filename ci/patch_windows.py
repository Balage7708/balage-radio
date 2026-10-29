"""A `flutter create` által generált Windows-fájlok testreszabása (ablakcím, termékinfó)."""
import pathlib, re

root = pathlib.Path(__file__).resolve().parent.parent / "windows" / "runner"

main = root / "main.cpp"
s = main.read_text(encoding="utf-8")
s = s.replace('L"balage_radio"', 'L"Balage R\\u00e1di\\u00f3"')
main.write_text(s, encoding="utf-8")

rc = root / "Runner.rc"
if rc.exists():
    t = rc.read_text(encoding="utf-8", errors="ignore")
    t = re.sub(r'VALUE "FileDescription", "[^"]*"', 'VALUE "FileDescription", "Balage Radio"', t)
    t = re.sub(r'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "Balage Radio"', t)
    t = re.sub(r'VALUE "CompanyName", "[^"]*"', 'VALUE "CompanyName", "Balage Drone Services"', t)
    rc.write_text(t, encoding="utf-8")
print("windows patched")
