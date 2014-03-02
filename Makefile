thesis.pdf: thesis.tex intro.tex bifrost.tex citenet.tex conclusion.tex
	pdflatex $< && pdflatex $<

intro.tex: intro.markdown
	pandoc --to latex --output $@ -- $<

bifrost.tex: bifrost.markdown
	pandoc --to latex --output $@ -- $<

citenet.tex: citenet.markdown
	pandoc --to latex --output $@ -- $<

conclusion.tex: conclusion.markdown
	pandoc --to latex --output $@ -- $<

