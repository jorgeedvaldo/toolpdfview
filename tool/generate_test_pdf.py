#!/usr/bin/env python3
"""Generates the small PDFs the integration tests open.

- sample.pdf     twelve pages of real, selectable text
- protected.pdf  the same kind of page behind the password "secret"
- broken.pdf     not a PDF at all, to exercise the failure screen

Run from the repository root:  python3 tool/generate_test_pdf.py
"""
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

OUT = "integration_test/assets"


def write(name: str, pages: int, **options) -> None:
    width, height = A4
    c = canvas.Canvas(f"{OUT}/{name}", pagesize=A4, invariant=1, **options)
    c.setTitle("ToolPDF View test document")
    for page in range(1, pages + 1):
        c.setFont("Helvetica-Bold", 30)
        c.drawString(60, height - 100, f"ToolPDF View page {page}")
        c.setFont("Helvetica", 16)
        y = height - 160
        for line in range(1, 26):
            c.drawString(
                60,
                y,
                f"Line {line} of page {page}: the quick brown fox jumps over the lazy dog.",
            )
            y -= 24
        c.showPage()
    c.save()


def main() -> None:
    write("sample.pdf", 12)
    write("protected.pdf", 2, encrypt="secret")
    with open(f"{OUT}/broken.pdf", "wb") as broken:
        broken.write(b"This file only pretends to be a PDF.\n" * 8)
    print(f"test PDFs written to {OUT}/")


if __name__ == "__main__":
    main()
