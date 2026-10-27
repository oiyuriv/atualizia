# Atualiz.IA

App pessoal (PWA para iPhone) para ler todo dia as matérias mais recentes sobre semiótica, design, comunicação, criatividade e publicidade, com meta diária de leitura.

**Abrir:** https://oiyuriv.github.io/atualizia/ no Safari → Compartilhar → *Adicionar à Tela de Início*.

## Como funciona

- `tools/sources.json`: as fontes (revistas, blogs, jornais e revistas acadêmicas do Brasil e de fora). Para incluir ou tirar uma fonte, é só editar esta lista.
- `tools/build-feed.ps1`: busca os feeds, traduz títulos e resumos de fora para o português, marca os temas e grava `data/feed.json`.
- `.github/workflows/feed.yml`: roda o coletor a cada 2 horas no GitHub Actions e publica o site.
- `index.html`: o app inteiro. Notas, salvos, metas e o que o feed aprendeu ficam só no aparelho (localStorage).

Para testar no Windows: `powershell -File tools/build-feed.ps1` e depois `powershell -File serve.ps1` (porta 8802).
