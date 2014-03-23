SOURCE = main.markdown
TEMPLATE = template.tex

BASENAME = thesis
INTERMEDIATE = $(BASENAME).tex
OUTPUT = $(BASENAME).pdf

PANDOC = pandoc
PANDOC_FLAGS = --chapter \
		--smart

LATEX = pdflatex
#LATEX_FLAGS = --output $(OUTPUT)
BIBTEX = biber

BIBLIOGRAPHY = references.bib
MAKEFILE = Makefile

DEPENDENCIES = $(SOURCE) $(TEMPLATE) $(BIBLIOGRAPHY) $(MAKEFILE)

AUXFILES = *.aux *.lof *.log *.lot *.fls *.out *.toc *.bbl *.bcf *.blg \
		   *-blx.aux *-blx.bib *.run.xml

.PHONY: clean

all: $(OUTPUT)

$(OUTPUT): $(INTERMEDIATE)
	$(LATEX) $(LATEX_FLAGS) -- $(BASENAME) && \
		$(BIBTEX) $(BASENAME) && \
		$(LATEX) $(LATEX_FLAGS) -- $(BASENAME) && \
		$(LATEX) $(LATEX_FLAGS) -- $(BASENAME)

# intermediate TeX
$(INTERMEDIATE): $(DEPENDENCIES)
	$(PANDOC) $(PANDOC_FLAGS) \
			  --to latex \
			  --no-highlight \
			  --biblatex \
			  --output $@ \
			  --template $(TEMPLATE) \
			  -- $<
clean:
	rm -f $(AUXFILES)

distclean: clean
	rm -f $(OUTPUT) $(INTERMEDIATE)
