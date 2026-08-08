# ordinary latex
$latex = 'uplatex %O -kanji=utf8 -no-guess-input-enc -synctex=1 -interaction=nonstopmode %S';
# for pdfLaTeX
$pdflatex = 'pdflatex %O -synctex=1 -interaction=nonstopmode %S';
# for LuaLaTeX
$lualatex = 'lualatex %O -synctex=1 -interaction=nonstopmode %S';
# XeLaTeX
$xelatex = 'xelatex %O -no-pdf -synctex=1 -shell-escape -interaction=nonstopmode %S';
# Biber, BibTeX
$biber = 'biber %O --bblencoding=utf8 -u -U --output_safechars %B';
$bibtex = 'upbibtex %O %B';
# makeindex
$makeindex = 'upmendex %O -o %D %S';
# dvipdf
$dvipdf = 'dvipdfmx %O -o %D %S';
# dvipd
$dvips = 'dvips %O -z -f %S | convbkmk -u > %D';
$ps2pdf = 'ps2pdf.exe %O %S %D';

# pdf option
# 0:not create 1: use pdflatex 2: use ps2pdf 3: use dvipdf 4: use lualatex 5: use xdvipdfmx
$pdf_mode = 4;

$postscript_mode = 0;
$dvi_mode = 0;

$out_dir = 'out';

$clean_ext = 'aux bbl blg idx ilg ind lof log lot out toc synctex.gz fdb_latexmk fls';
