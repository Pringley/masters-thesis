OUTPUT = thesis.pdf
SOURCE = main.markdown
TEMPLATE = template.tex

PANDOC = pandoc
FLAGS = --chapter \
		--smart

INTERMEDIATE = intermediate.tex
DEPENDENCIES = $(SOURCE) $(TEMPLATE)

.PHONY: clean

all: $(INTERMEDIATE) $(OUTPUT)

$(OUTPUT): $(DEPENDENCIES)
	$(PANDOC) $(FLAGS) \
			  --output $@ \
			  --template $(TEMPLATE) \
			  -- $<

# intermediate TeX
$(INTERMEDIATE): $(DEPENDENCIES)
	$(PANDOC) $(FLAGS) \
			  --to latex \
			  --no-highlight \
			  --output $@ \
			  --template $(TEMPLATE) \
			  -- $<

clean:
	rm -f $(OUTPUT)
