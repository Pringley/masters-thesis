SOURCE = main.markdown
TEMPLATE = template.tex
SLIDE_SOURCE = slides.markdown

BASENAME = thesis
INTERMEDIATE = $(BASENAME).tex
OUTPUT = $(BASENAME).pdf
SLIDE_OUTPUT = slides.pdf

PANDOC = pandoc
PANDOC_FLAGS = --chapter \
		--smart

LATEX = pdflatex
BIBTEX = biber

BIBLIOGRAPHY = references.bib

DEPENDENCIES = $(SOURCE) $(TEMPLATE) $(BIBLIOGRAPHY)

AUXFILES = *.aux *.lof *.log *.lot *.fls *.out *.toc *.bbl *.bcf *.blg \
		   *-blx.aux *-blx.bib *.run.xml

.PHONY: clean all thesis slides

all: slides thesis

thesis: $(OUTPUT)

slides: $(SLIDE_OUTPUT)

$(OUTPUT): $(INTERMEDIATE)
	$(LATEX) $(BASENAME) && \
		$(BIBTEX) $(BASENAME) && \
		$(LATEX) $(BASENAME) && \
		$(LATEX) $(BASENAME)

# intermediate TeX
$(INTERMEDIATE): $(DEPENDENCIES)
	$(PANDOC) $(PANDOC_FLAGS) \
			  --to latex \
			  --biblatex \
			  --output $@ \
			  --template $(TEMPLATE) \
			  -- $<

$(SLIDE_OUTPUT): $(SLIDE_SOURCE)
	$(PANDOC) --smart \
				--chapter \
				--to beamer \
				--output $@ \
				-- $<

clean:
	rm -f $(AUXFILES)

distclean: clean
	rm -f $(OUTPUT) $(INTERMEDIATE) $(SLIDE_OUTPUT)
