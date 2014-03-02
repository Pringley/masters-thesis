OUTPUT = thesis.pdf
SOURCE = main.markdown
TEMPLATE = template.tex

PANDOC = pandoc
FLAGS = --chapter \
		--smart

.PHONY: clean

$(OUTPUT): $(SOURCE) $(TEMPLATE)
	$(PANDOC) $(FLAGS) \
			  --output $(OUTPUT) \
			  --template $(TEMPLATE) \
			  -- \
			  $(SOURCE)

clean:
	rm -f $(OUTPUT)
