import fitz

try:
    doc_light = fitz.open("light.svg")
    pix_light = doc_light[0].get_pixmap(dpi=300, alpha=True)
    pix_light.save("assets/splash_icon_light.png")

    doc_dark = fitz.open("dark.svg")
    pix_dark = doc_dark[0].get_pixmap(dpi=300, alpha=True)
    pix_dark.save("assets/splash_icon_dark.png")
    print("Renderizado completo con PyMuPDF")
except Exception as e:
    print(f"Error: {e}")
