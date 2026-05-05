# VSL LaTeX Paper
# TeX Live completo para compilar o paper acadêmico
# Usado por: latex-paper

FROM texlive/texlive:latest

# ── Dependências extras ───────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # Para minted (syntax highlight de código)
    python3 \
    python3-pygments \
    # Para latexmk watch mode
    perl \
    # Git para sync com Overleaf
    git \
    && rm -rf /var/lib/apt/lists/*

# ── Verificar pacotes LaTeX necessários ──────────────────────────
# Instala pacotes que podem não estar no texlive:latest
RUN tlmgr update --self && tlmgr install \
    biblatex \
    biber \
    siunitx \
    booktabs \
    minted \
    cleveref \
    pgfplots \
    tikz-cd \
    algorithms \
    algorithmicx \
    listings \
    microtype \
    geometry \
    fancyhdr \
    hyperref \
    doi \
    || true
# || true porque alguns pacotes já podem estar incluídos

WORKDIR /workspace/paper

# ── Configuração do latexmk ───────────────────────────────────────
RUN echo "\$pdf_mode = 1;" > /root/.latexmkrc && \
    echo "\$bibtex_use = 2;" >> /root/.latexmkrc && \
    echo "\$out_dir = 'build';" >> /root/.latexmkrc && \
    echo "\$pdflatex = 'pdflatex -shell-escape -interaction=nonstopmode %O %S';" >> /root/.latexmkrc

# ── Cria diretório de output ──────────────────────────────────────
RUN mkdir -p /workspace/paper/build

CMD ["latexmk", "-pdf", "-pvc", "-interaction=nonstopmode", "-outdir=build", "main.tex"]
