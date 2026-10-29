"""A `flutter create` által generált android/app/build.gradle(.kts) testreszabása:
állandó aláíró kulcs, core library desugaring (értesítésekhez), minSdk 24."""
import pathlib, re, sys

app = pathlib.Path(__file__).resolve().parent.parent / "android" / "app"
kts = app / "build.gradle.kts"
if not kts.exists():
    sys.exit("build.gradle.kts not found – a Flutter sablon megváltozott")
s = kts.read_text(encoding="utf-8")

# importok a fájl elejére
s = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s

# kulcsfájl betöltése az android blokk előtt
loader = '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

'''
s = re.sub(r"(?m)^android \{", loader + "android {", s, count=1)

# aláírás
signing = '''
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
'''
s = re.sub(r"(?m)^android \{\n", "android {\n" + signing, s, count=1)
s = s.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')

# desugaring
if "sourceCompatibility" in s:
    s = re.sub(r"(?m)^(\s*)(sourceCompatibility\s*=.*)$", r"\1\2\n\1isCoreLibraryDesugaringEnabled = true", s, count=1)
else:
    s = re.sub(r"(?m)^android \{\n", "android {\n    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n    }\n", s, count=1)

# minSdk
s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = maxOf(24, flutter.minSdkVersion)", s)

s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'
kts.write_text(s, encoding="utf-8")
print("----- patched build.gradle.kts -----")
print(s)
